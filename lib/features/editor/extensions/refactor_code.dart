import 'dart:async';
import '../../../core/ai/ai_provider.dart';

/// 重构结果
class RefactorResult {
  final String explanation;
  final String refactoredCode;
  final List<String> changes;
  final bool hasError;
  final String? errorMessage;

  const RefactorResult({
    required this.explanation,
    required this.refactoredCode,
    this.changes = const [],
    this.hasError = false,
    this.errorMessage,
  });

  bool get isValid => !hasError && refactoredCode.isNotEmpty;
}

/// 重构引擎
class RefactorEngine {
  final AiProvider _aiProvider;
  CancelToken? _cancelToken;
  RefactorResult? _lastResult;

  RefactorEngine(this._aiProvider);

  RefactorResult? get lastResult => _lastResult;

  /// 重构代码
  Future<RefactorResult> refactor({
    required String code,
    required String language,
  }) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    try {
      final systemPrompt = _buildSystemPrompt();
      final userPrompt = _buildUserPrompt(code, language);

      final response = await _aiProvider.chat(
        messages: [
          ChatMessageInput(role: 'system', content: systemPrompt),
          ChatMessageInput(role: 'user', content: userPrompt),
        ],
        temperature: 0.3,
        cancelToken: _cancelToken,
      );

      if (_cancelToken?.isCancelled == true) {
        return const RefactorResult(explanation: '', refactoredCode: '');
      }

      final result = _parseResponse(response);
      _lastResult = result;
      return result;
    } catch (e) {
      _lastResult = RefactorResult(
        explanation: '',
        refactoredCode: '',
        hasError: true,
        errorMessage: '重构失败: $e',
      );
      return _lastResult!;
    }
  }

  void cancel() {
    _cancelToken?.cancel();
  }

  void dispose() {
    _cancelToken?.cancel();
  }

  String _buildSystemPrompt() {
    return '''你是一个代码重构专家。分析用户提供的代码，给出重构方案。

返回 JSON 格式：
{
  "explanation": "重构说明（中文，描述做了什么改进，为什么）",
  "code": "重构后的完整代码",
  "changes": ["变更1", "变更2"]
}

规则：
- 只输出有效的 JSON
- code 字段必须包含可运行的完整代码（不是 diff）
- changes 字段列出每个改动的简要说明
- 优先推荐：提取函数、提取 Widget、简化条件、消除重复''';
  }

  String _buildUserPrompt(String code, String language) {
    return '''重构这段 $language 代码：

```$language
$code
```

请分析问题并给出重构后的完整代码。''';
  }

  RefactorResult _parseResponse(String response) {
    try {
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        final jsonStr = response.substring(jsonStart, jsonEnd + 1);
        final data = _parseSimpleJson(jsonStr, response);

        return RefactorResult(
          explanation: data['explanation']?.toString() ?? '',
          refactoredCode: data['code']?.toString() ?? '',
          changes: _extractList(data['changes']),
        );
      }
    } catch (_) {}

    return RefactorResult(
      explanation: response,
      refactoredCode: '',
      hasError: true,
      errorMessage: '无法解析 AI 响应',
    );
  }

  List<String> _extractList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  Map<String, dynamic> _parseSimpleJson(String json, String fallback) {
    final result = <String, dynamic>{};
    final clean = json.trim();
    int i = 1;
    var buf = StringBuffer();
    String k = '';
    bool inStr = false, inVal = false, esc = false;

    while (i < clean.length - 1) {
      final c = clean[i];
      if (esc) { buf.write(c); esc = false; i++; continue; }
      if (c == '\\') { esc = true; i++; continue; }
      if (c == '"') {
        inStr = !inStr;
        if (!inStr) {
          final s = buf.toString(); buf = StringBuffer();
          if (!inVal) { k = s; } else { result[k] = s; k = ''; inVal = false; }
        }
        i++; continue;
      }
      if (!inStr) {
        if (c == ':') { inVal = true; i++; continue; }
        if (c == ',' || c == '}') {
          if (k.isNotEmpty && buf.isNotEmpty) {
            final v = buf.toString().trim();
            if (v == 'null') {
              result[k] = null;
            } else if (v == 'true') result[k] = true;
            else if (v == 'false') result[k] = false;
            else result[k] = v;
          }
          buf = StringBuffer(); k = ''; inVal = false;
          if (c == '}') break;
          i++; continue;
        }
      }
      buf.write(c);
      i++;
    }
    return result;
  }
}
