import 'dart:async';
import '../../../core/ai/ai_provider.dart';

/// 代码生成器状态
enum GenerateCodeState {
  idle,
  generating,
  done,
  error,
}

/// 代码生成结果
class GeneratedCode {
  final String code;
  final String language;
  final String? description;
  final bool hasError;
  final String? errorMessage;

  const GeneratedCode({
    required this.code,
    required this.language,
    this.description,
    this.hasError = false,
    this.errorMessage,
  });

  bool get isValid => !hasError && code.isNotEmpty;
}

/// AI 代码生成器
///
/// 根据自然语言描述生成代码。
/// 支持 Dart、Rust、Python、Markdown 等语言。
class CodeGenerator {
  final AiProvider _aiProvider;
  CancelToken? _cancelToken;
  GenerateCodeState _state = GenerateCodeState.idle;

  CodeGenerator(this._aiProvider);

  GenerateCodeState get state => _state;
  bool get isLoading => _state == GenerateCodeState.generating;

  /// 生成代码
  Future<GeneratedCode> generate({
    required String prompt,
    required String language,
  }) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    _state = GenerateCodeState.generating;
    _notifyListeners();

    try {
      final systemPrompt = _buildSystemPrompt(language);
      final userPrompt = prompt;

      final response = await _aiProvider.chat(
        messages: [
          ChatMessageInput(role: 'system', content: systemPrompt),
          ChatMessageInput(role: 'user', content: userPrompt),
        ],
        temperature: 0.3,
        cancelToken: _cancelToken,
      );

      if (_cancelToken?.isCancelled == true) {
        _state = GenerateCodeState.idle;
        _notifyListeners();
        return const GeneratedCode(code: '', language: '');
      }

      final code = _extractCode(response, language);
      final description = _extractDescription(response, code);

      final result = GeneratedCode(
        code: code,
        language: language,
        description: description,
      );

      _state = GenerateCodeState.done;
      _notifyListeners();
      return result;
    } catch (e) {
      _state = GenerateCodeState.error;
      _notifyListeners();
      return GeneratedCode(
        code: '',
        language: language,
        hasError: true,
        errorMessage: '生成失败: $e',
      );
    }
  }

  /// 取消生成
  void cancel() {
    _cancelToken?.cancel();
    _state = GenerateCodeState.idle;
    _notifyListeners();
  }

  void dispose() {
    _cancelToken?.cancel();
    _listeners.clear();
  }

  // ── 内部方法 ──

  String _buildSystemPrompt(String language) {
    return '''You are an expert $language code generator. Generate clean, well-documented code.

Rules:
- Output the code in a ``` code block
- Add a brief description before or after the code block
- Include necessary imports and dependencies
- Follow $language best practices and conventions
- Handle errors appropriately
- Add comments for complex logic
- Keep the code production-ready''';
  }

  String _extractCode(String response, String language) {
    // 查找代码块
    final codeBlockPattern = RegExp(r'```' + RegExp.escape(language) + r'\s*\n(.*?)\n```', dotAll: true);
    final match = codeBlockPattern.firstMatch(response);
    if (match != null) {
      return match.group(1)!.trim();
    }

    // 尝试通用代码块
    final genericPattern = RegExp(r'```\s*\n(.*?)\n```', dotAll: true);
    final genericMatch = genericPattern.firstMatch(response);
    if (genericMatch != null) {
      return genericMatch.group(1)!.trim();
    }

    // 如果没有代码块，返回整个响应
    return response.trim();
  }

  String? _extractDescription(String response, String code) {
    // 移除代码块
    final String clean = response.replaceAll(RegExp(r'```[\s\S]*?```'), '').trim();
    if (clean.isEmpty) return null;
    return clean;
  }

  // ── 监听器 ──

  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback callback) => _listeners.add(callback);
  void removeListener(VoidCallback callback) => _listeners.remove(callback);

  void _notifyListeners() {
    for (final l in List.from(_listeners)) {
      l();
    }
  }
}
