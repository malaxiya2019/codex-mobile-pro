/// 真实端到端验证：图片 → Gemini API → 模型理解
///
/// 用法：
///   GEMINI_API_KEY=<key> dart run tool/gemini_e2e.dart <image_path> [model]
///
/// 流程（与 GeminiChatEngine 完全一致）：
///   1. 读取图片 bytes → base64 → inline_data（绝不发路径字符串）
///   2. POST https://generativelanguage.googleapis.com/v1beta/models/<model>:streamGenerateContent?alt=sse
///   3. 解析 SSE 增量文本，输出模型对图片的描述
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final key = Platform.environment['GEMINI_API_KEY']?.trim() ?? '';
  if (key.isEmpty) {
    stderr.writeln('❌ 未设置 GEMINI_API_KEY 环境变量');
    exit(2);
  }
  if (args.isEmpty) {
    stderr.writeln('❌ 缺少图片路径参数');
    exit(2);
  }
  final imagePath = args[0];
  final model = args.length > 1 ? args[1] : 'gemini-2.5-flash';

  final f = File(imagePath);
  if (!await f.exists()) {
    stderr.writeln('❌ 图片不存在: $imagePath');
    exit(2);
  }
  final bytes = await f.readAsBytes();
  if (bytes.isEmpty) {
    stderr.writeln('❌ 图片为空');
    exit(2);
  }
  final mime = _mimeOf(imagePath);
  stderr.writeln('✅ 读取图片: $imagePath (${bytes.length} bytes, $mime)');

  final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
  stderr.writeln('✅ data URL 前缀: ${dataUrl.substring(0, 30)}... 总长 ${dataUrl.length}');
  stderr.writeln('   ⚠️ 检查：请求体是否包含文件路径字符串？ '
      '${dataUrl.contains(imagePath) ? "是（错误！）" : "否（正确，纯 base64）"}');

  final body = {
    'contents': [
      {
        'role': 'user',
        'parts': [
          {'text': '请描述这张图片里有什么。'},
          {'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)}},
        ],
      },
    ],
    'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024},
  };

  final url = 'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:streamGenerateContent?alt=sse';
  stderr.writeln('✅ 请求 URL: $url (model=$model)');

  final client = http.Client();
  try {
    final response = await client
        .post(
          Uri.parse(url),
          headers: {
            'x-goog-api-key': key,
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    stderr.writeln('✅ HTTP ${response.statusCode}');
    if (response.statusCode != 200) {
      stderr.writeln('❌ 响应体: ${response.body}');
      exit(1);
    }

    final sb = StringBuffer();
    final lines = LineSplitter().convert(response.body);
    for (final line in lines) {
      final t = line.trim();
      if (!t.startsWith('data: ')) continue;
      final jsonStr = t.substring(6).trim();
      if (jsonStr == '[DONE]') break;
      try {
        final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
        final candidates = obj['candidates'] as List? ?? [];
        for (final cand in candidates) {
          final content = (cand as Map)['content'] as Map?;
          final parts = content?['parts'] as List? ?? [];
          for (final part in parts) {
            final text = (part as Map)['text'];
            if (text is String && text.isNotEmpty) sb.write(text);
          }
        }
      } catch (_) {}
    }

    final answer = sb.toString().trim();
    if (answer.isEmpty) {
      stderr.writeln('❌ 模型未返回文本（可能拒绝图片输入）');
      exit(1);
    }
    stderr.writeln('✅ 模型理解完成（${answer.length} chars）：');
    stderr.writeln('─' * 40);
    stdout.writeln(answer);
  } finally {
    client.close();
  }
}

String _mimeOf(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.mp4') || lower.endsWith('.mov')) return 'video/mp4';
  return 'image/png';
}
