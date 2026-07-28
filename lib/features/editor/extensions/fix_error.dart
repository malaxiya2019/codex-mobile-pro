import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/ai/ai_provider.dart';
import 'diagnostics_provider.dart';

/// AI 修复建议
class FixSuggestion {
  /// 错误原因
  final String reason;

  /// 修复描述
  final String description;

  /// 修改建议（替换的代码块）
  final String patch;

  /// 原始代码（被替换的部分）
  final String original;

  /// 行号（从 0 开始）
  final int line;

  /// 列号
  final int column;

  /// 长度
  final int length;

  /// 关联的诊断
  final Diagnostic diagnostic;

  const FixSuggestion({
    required this.reason,
    required this.description,
    required this.patch,
    required this.original,
    required this.line,
    required this.column,
    required this.length,
    required this.diagnostic,
  });

  /// 是否有有效的补丁
  bool get hasValidPatch => patch.isNotEmpty && patch != original;
}

/// AI 修复引擎状态
enum FixEngineState {
  idle,
  fixing,
  done,
  error,
}

/// 诊断修复结果
class FixResult {
  final List<FixSuggestion> suggestions;
  final String? error;

  const FixResult({
    this.suggestions = const [],
    this.error,
  });

  bool get hasSuggestions => suggestions.isNotEmpty;
  bool get hasError => error != null;
}

/// AI Fix Error 引擎
///
/// 根据诊断信息，使用 AI 生成修复建议。
/// 支持 Diff Preview、Accept、Reject。
class FixEngine {
  final AiProvider _aiProvider;
  CancelToken? _cancelToken;
  FixEngineState _state = FixEngineState.idle;
  FixResult? _lastResult;

  FixEngine(this._aiProvider);

  FixEngineState get state => _state;
  FixResult? get lastResult => _lastResult;
  bool get isFixing => _state == FixEngineState.fixing;

  /// 根据诊断信息请求 AI 修复
  Future<FixResult> fixDiagnostic({
    required Diagnostic diagnostic,
    required String filePath,
    required String code,
    required String language,
  }) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    _state = FixEngineState.fixing;
    _notifyListeners();

    try {
      final systemPrompt = _buildSystemPrompt();
      final userPrompt = _buildUserPrompt(diagnostic, code, language);

      final response = await _aiProvider.chat(
        messages: [
          ChatMessageInput(role: 'system', content: systemPrompt),
          ChatMessageInput(role: 'user', content: userPrompt),
        ],
        temperature: 0.2,
        maxTokens: 2048,
        cancelToken: _cancelToken,
      );

      if (_cancelToken?.isCancelled == true) {
        _state = FixEngineState.idle;
        _notifyListeners();
        return const FixResult();
      }

      final result = _parseResponse(response, diagnostic);
      _lastResult = result;
      _state = FixEngineState.done;
      _notifyListeners();

      return result;
    } catch (e) {
      _state = FixEngineState.error;
      _lastResult = FixResult(error: '修复失败: $e');
      _notifyListeners();
      return _lastResult!;
    }
  }

  /// 取消修复
  void cancel() {
    _cancelToken?.cancel();
    _state = FixEngineState.idle;
    _notifyListeners();
  }

  /// 重置
  void reset() {
    _cancelToken?.cancel();
    _state = FixEngineState.idle;
    _lastResult = null;
    _notifyListeners();
  }

  void dispose() {
    _cancelToken?.cancel();
    _listeners.clear();
  }

  // ── 内部方法 ──

  String _buildSystemPrompt() {
    return '''You are an expert code debugger and fixer. Analyze the code error and provide a fix.

Return ONLY valid JSON with this exact structure:
{
  "reason": "Root cause of the error (1-2 sentences)",
  "description": "How to fix it (1-2 sentences)",
  "patch": "The complete replacement code snippet that fixes the error",
  "line": 0,
  "column": 0,
  "length": 0
}

Rules:
- "patch" must contain the complete replacement for the problematic section
- "line" and "column" should be the starting position of the fix
- "length" is the number of characters to replace
- Be precise and minimal - only change what's needed
- Ensure the patch compiles correctly after replacement
- Use Chinese for reason and description''';
  }

  String _buildUserPrompt(Diagnostic diagnostic, String code, String language) {
    return '''Fix this $language code error:

Error: ${diagnostic.message}
${diagnostic.code != null ? "Error code: ${diagnostic.code}" : ""}
Line: ${diagnostic.line + 1}, Column: ${diagnostic.column + 1}

Code:
\`\`\`$language
$code
\`\`\`

Return JSON output only.''';
  }

  FixResult _parseResponse(String response, Diagnostic diagnostic) {
    try {
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');

      if (jsonStart != -1 && jsonEnd != -1) {
        final jsonStr = response.substring(jsonStart, jsonEnd + 1);
        final data = _parseSimpleJson(jsonStr);

        final reason = data['reason']?.toString() ?? '未知错误';
        final description = data['description']?.toString() ?? '';
        final patch = data['patch']?.toString() ?? '';
        final line = _parseInt(data['line']) ?? diagnostic.line;
        final column = _parseInt(data['column']) ?? diagnostic.column;
        final length = _parseInt(data['length']) ?? diagnostic.length;

        // 获取原始代码片段
        final lines = diagnostic.source?.split('\n') ?? [];
        String original = '';
        if (line < lines.length) {
          final lineText = lines[line];
          if (column < lineText.length) {
            final end = (column + length).clamp(0, lineText.length);
            original = lineText.substring(column, end);
          }
        }

        final suggestion = FixSuggestion(
          reason: reason,
          description: description,
          patch: patch,
          original: original,
          line: line,
          column: column,
          length: length,
          diagnostic: diagnostic,
        );

        return FixResult(suggestions: [suggestion]);
      }
    } catch (_) {}

    return FixResult(
      error: '无法解析 AI 响应，请重试',
      suggestions: [
        FixSuggestion(
          reason: '解析失败',
          description: 'AI 响应格式异常',
          patch: '',
          original: '',
          line: diagnostic.line,
          column: diagnostic.column,
          length: diagnostic.length,
          diagnostic: diagnostic,
        ),
      ],
    );
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// 简单 JSON 解析器
  Map<String, dynamic> _parseSimpleJson(String json) {
    final result = <String, dynamic>{};
    final clean = json.trim();
    int i = 1;
    var buf = StringBuffer();
    String key = '';
    bool inStr = false;
    bool inVal = false;
    bool esc = false;

    while (i < clean.length - 1) {
      final c = clean[i];
      if (esc) { buf.write(c); esc = false; i++; continue; }
      if (c == '\\') { buf.write(c); esc = true; i++; continue; }
      if (c == '"') {
        inStr = !inStr;
        if (!inStr) {
          final str = buf.toString();
          buf = StringBuffer();
          if (!inVal) { key = str; } else { result[key] = str; key = ''; inVal = false; }
        }
        i++; continue;
      }
      if (!inStr) {
        if (c == ':') { inVal = true; i++; continue; }
        if (c == ',' || c == '}') {
          if (key.isNotEmpty && buf.isNotEmpty) {
            final v = buf.toString().trim();
            if (v == 'null') result[key] = null;
            else if (v == 'true') result[key] = true;
            else if (v == 'false') result[key] = false;
            else result[key] = v;
          }
          buf = StringBuffer(); key = ''; inVal = false;
          if (c == '}') break;
          i++; continue;
        }
      }
      buf.write(c);
      i++;
    }
    return result;
  }

  // ── 监听器 ──

  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback callback) => _listeners.add(callback);
  void removeListener(VoidCallback callback) => _listeners.remove(callback);

  void _notifyListeners() {
    for (final l in List.from(_listeners)) l();
  }
}
