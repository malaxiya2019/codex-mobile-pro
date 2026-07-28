import 'dart:async';
import '../../../core/ai/ai_provider.dart';

/// 代码解释结果
class CodeExplanation {
  /// 功能解释
  final String explanation;

  /// 时间复杂度
  final String? timeComplexity;

  /// 空间复杂度
  final String? spaceComplexity;

  /// 优化建议列表
  final List<String> suggestions;

  /// 是否包含错误
  final bool hasError;
  final String? errorMessage;

  const CodeExplanation({
    required this.explanation,
    this.timeComplexity,
    this.spaceComplexity,
    this.suggestions = const [],
    this.hasError = false,
    this.errorMessage,
  });

  /// 是否为有效结果
  bool get isValid => !hasError && explanation.isNotEmpty;
}

/// 代码解释器状态
enum CodeExplainState {
  /// 空闲
  idle,

  /// 正在解释
  loading,

  /// 完成
  done,

  /// 错误
  error,
}

/// 代码解释器
///
/// 使用 AI 分析选中的代码，返回功能解释、复杂度分析和优化建议。
class CodeExplainer {
  final AiProvider _aiProvider;
  CancelToken? _cancelToken;
  CodeExplainState _state = CodeExplainState.idle;
  CodeExplanation? _lastResult;

  CodeExplainer(this._aiProvider);

  /// 当前状态
  CodeExplainState get state => _state;

  /// 最后结果
  CodeExplanation? get lastResult => _lastResult;

  /// 是否有正在进行的请求
  bool get isLoading => _state == CodeExplainState.loading;

  /// 解释选中的代码
  Future<CodeExplanation> explain({
    required String code,
    required String language,
  }) async {
    // 取消之前的请求
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    _state = CodeExplainState.loading;
    _notifyListeners();

    try {
      final systemPrompt = _buildSystemPrompt();
      final userPrompt = _buildUserPrompt(code, language);

      final result = await _aiProvider.chat(
        messages: [
          ChatMessageInput(role: 'system', content: systemPrompt),
          ChatMessageInput(role: 'user', content: userPrompt),
        ],
        temperature: 0.3,
        maxTokens: 2048,
        cancelToken: _cancelToken,
      );

      if (_cancelToken?.isCancelled == true) {
        _state = CodeExplainState.idle;
        _notifyListeners();
        return CodeExplanation(explanation: '');
      }

      final explanation = _parseResponse(result);

      _lastResult = explanation;
      _state = CodeExplainState.done;
      _notifyListeners();

      return explanation;
    } catch (e) {
      _state = CodeExplainState.error;
      _lastResult = CodeExplanation(
        explanation: '',
        hasError: true,
        errorMessage: '解释失败: $e',
      );
      _notifyListeners();
      return _lastResult!;
    }
  }

  /// 取消当前解释
  void cancel() {
    _cancelToken?.cancel();
    _state = CodeExplainState.idle;
    _notifyListeners();
  }

  /// 重置状态
  void reset() {
    _cancelToken?.cancel();
    _state = CodeExplainState.idle;
    _lastResult = null;
    _notifyListeners();
  }

  /// 释放资源
  void dispose() {
    _cancelToken?.cancel();
    _listeners.clear();
  }

  // ── 内部方法 ──

  String _buildSystemPrompt() {
    return '''You are an expert code reviewer and educator. Analyze the provided code and return a structured explanation in JSON format.

Return ONLY valid JSON with this exact structure:
{
  "explanation": "Clear, concise explanation of what this code does",
  "timeComplexity": "O(n) etc. or null if not applicable",
  "spaceComplexity": "O(n) etc. or null if not applicable",
  "suggestions": ["Suggestion 1", "Suggestion 2"]
}

Rules:
- Keep explanation under 500 characters
- Be specific to the actual code shown
- If complexity analysis isn't meaningful, set to null
- Provide 0-3 actionable optimization suggestions
- Use Chinese for explanation when appropriate
- Use English for Big-O notation''';
  }

  String _buildUserPrompt(String code, String language) {
    return '''Explain this $language code:

\`\`\`$language
$code
\`\`\`

Return JSON output only.''';
  }

  CodeExplanation _parseResponse(String response) {
    try {
      // Try to extract JSON from the response
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');

      if (jsonStart != -1 && jsonEnd != -1) {
        final jsonStr = response.substring(jsonStart, jsonEnd + 1);
        // Parse the JSON (simple parsing to avoid dart:convert dependency)
        final Map<String, dynamic> data = _parseSimpleJson(jsonStr);

        final explanation = data['explanation']?.toString() ?? response;
        final timeComplexity = data['timeComplexity']?.toString();
        final spaceComplexity = data['spaceComplexity']?.toString();
        final suggestionsRaw = data['suggestions'];

        final List<String> suggestions = [];
        if (suggestionsRaw is List) {
          for (final s in suggestionsRaw) {
            suggestions.add(s.toString());
          }
        }

        return CodeExplanation(
          explanation: explanation,
          timeComplexity: timeComplexity == 'null' || timeComplexity == null
              ? null
              : timeComplexity,
          spaceComplexity: spaceComplexity == 'null' || spaceComplexity == null
              ? null
              : spaceComplexity,
          suggestions: suggestions,
        );
      }
    } catch (_) {
      // JSON parsing failed, return raw response as explanation
    }

    return CodeExplanation(explanation: response.trim());
  }

  /// 简单的 JSON 解析（避免 dart:convert 依赖）
  Map<String, dynamic> _parseSimpleJson(String json) {
    final result = <String, dynamic>{};
    final clean = json.trim();

    int i = 1; // skip opening {
    final buffer = StringBuffer();
    String currentKey = '';
    bool inKey = false;
    bool inString = false;
    bool inValue = false;
    bool escaped = false;

    while (i < clean.length - 1) {
      final char = clean[i];

      if (escaped) {
        buffer.write(char);
        escaped = false;
        i++;
        continue;
      }

      if (char == '\\') {
        buffer.write(char);
        escaped = true;
        i++;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        if (!inString) {
          // End of string
          final str = buffer.toString();
          buffer = StringBuffer();
          if (!inKey && !inValue) {
            currentKey = str;
            inKey = true;
          } else if (inValue) {
            result[currentKey] = str;
            currentKey = '';
            inKey = false;
            inValue = false;
          }
        }
        i++;
        continue;
      }

      if (!inString) {
        if (char == ':') {
          inValue = true;
          inKey = false;
          i++;
          continue;
        }
        if (char == ',' || char == '}') {
          inValue = false;
          inKey = false;
          if (currentKey.isNotEmpty && buffer.isNotEmpty) {
            final val = buffer.toString().trim();
            if (val == 'null') {
              result[currentKey] = null;
            } else if (val == 'true') {
              result[currentKey] = true;
            } else if (val == 'false') {
              result[currentKey] = false;
            } else if (RegExp(r'^\d+\.?\d*$').hasMatch(val)) {
              if (val.contains('.')) {
                result[currentKey] = double.tryParse(val);
              } else {
                result[currentKey] = int.tryParse(val);
              }
            } else if (val.startsWith('[')) {
              // Simple array parsing
              result[currentKey] = _parseSimpleJsonArray(val);
            }
          }
          buffer = StringBuffer();
          currentKey = '';
          if (char == '}') break;
          i++;
          continue;
        }
      }

      buffer.write(char);
      i++;
    }

    return result;
  }

  List<dynamic> _parseSimpleJsonArray(String json) {
    final result = <dynamic>[];
    final clean = json.trim();
    int i = 1; // skip [

    final buffer = StringBuffer();
    bool inString = false;

    while (i < clean.length - 1) {
      final char = clean[i];
      if (char == '"') {
        inString = !inString;
        if (!inString) {
          result.add(buffer.toString());
          buffer = StringBuffer();
        }
        i++;
        continue;
      }
      if (!inString && (char == ',' || char == ']')) {
        final val = buffer.toString().trim();
        if (val.isNotEmpty) {
          result.add(val);
        }
        buffer = StringBuffer();
        if (char == ']') break;
        i++;
        continue;
      }
      buffer.write(char);
      i++;
    }

    return result;
  }

  // ── 监听器 ──

  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback callback) {
    _listeners.add(callback);
  }

  void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  void _notifyListeners() {
    for (final listener in List.from(_listeners)) {
      listener();
    }
  }
}
