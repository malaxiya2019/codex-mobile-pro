import 'dart:async';
import '../../../core/ai/ai_provider.dart';

/// Ghost Text 建议
class GhostTextSuggestion {
  /// 补全文本（追加在当前行光标之后）
  final String text;

  /// 来源提供者名称
  final String providerName;

  /// 置信度 (0.0 ~ 1.0)
  final double score;

  const GhostTextSuggestion({
    required this.text,
    this.providerName = 'AI',
    this.score = 1.0,
  });

  /// 建议是否有效（非空且合理长度）
  bool get isValid => text.isNotEmpty && text.length <= 500;

  /// 显示用的文本（仅取第一行用于 inline 展示）
  String get displayText {
    final firstLine = text.split('\n').first;
    if (firstLine.length > 120) {
      return firstLine.substring(0, 120);
    }
    return firstLine;
  }
}

/// 内联补全状态
enum InlineCompletionState {
  /// 空闲，无建议
  idle,

  /// 正在请求 AI 补全
  loading,

  /// 有建议可展示
  hasSuggestion,

  /// 发生错误
  error,
}

/// AI 内联补全引擎
///
/// 管理 Ghost Text 的生命周期：
/// 1. 用户输入 → debounce → 请求 AI
/// 2. AI 返回 → 展示灰色建议文本
/// 3. Tab → 接受建议
/// 4. Esc / 继续输入 → 取消建议
/// 5. 换行 / 粘贴 → 清除建议
class InlineCompletionEngine {
  AiProvider? _provider;
  GhostTextSuggestion? _currentSuggestion;
  InlineCompletionState _state = InlineCompletionState.idle;
  Timer? _debounceTimer;
  CancelToken? _cancelToken;
  String _lastPrefix = '';
  int _requestId = 0;

  /// debounce 延迟（毫秒）
  int debounceDelayMs = 300;

  /// 获取当前建议
  GhostTextSuggestion? get currentSuggestion => _currentSuggestion;

  /// 获取当前状态
  InlineCompletionState get state => _state;

  /// 是否有建议
  bool get hasSuggestion =>
      _state == InlineCompletionState.hasSuggestion &&
      _currentSuggestion != null &&
      _currentSuggestion!.isValid;

  /// 设置 AI Provider
  void setProvider(AiProvider? provider) {
    _provider = provider;
  }

  /// 用户输入触发补全
  ///
  /// 会根据 [triggerKind] 决定是否 debounce。
  void onTextChange({
    required String textBeforeCursor,
    required String textAfterCursor,
    required String filePath,
    required String language,
    required int cursorLine,
    required int cursorColumn,
    CompletionTriggerKind triggerKind = CompletionTriggerKind.automatic,
  }) {
    // 如果当前有建议且用户继续输入，清除建议
    if (_state == InlineCompletionState.hasSuggestion && triggerKind == CompletionTriggerKind.automatic) {
      // 检查是否继续输入了（与上次缓存的 prefix 比较）
      if (textBeforeCursor != _lastPrefix) {
        _cancelSuggestion();
      }
    }

    _lastPrefix = textBeforeCursor;

    // 取消之前的请求
    _cancelToken?.cancel();

    // 取消之前的 debounce
    _debounceTimer?.cancel();

    // 最小触发长度
    if (textBeforeCursor.trim().length < 3) {
      _setState(InlineCompletionState.idle);
      return;
    }

    // 获取当前行在光标之前的部分
    final linePrefix = _getLinePrefix(textBeforeCursor, cursorLine);

    // 仅在行末触发（不在单词中间触发）
    final charBeforeCursor = linePrefix.isNotEmpty ? linePrefix[linePrefix.length - 1] : '';
    if (charBeforeCursor.isNotEmpty &&
        RegExp(r'[a-zA-Z0-9_]').hasMatch(charBeforeCursor) &&
        textAfterCursor.isNotEmpty &&
        RegExp(r'[a-zA-Z0-9_]').hasMatch(textAfterCursor.isNotEmpty ? textAfterCursor[0] : '')) {
      // 在单词中间不触发，除非有明确的上下文
      // 但在某些情况下应该触发：行末写 . 或 -> 或 =>
      final shouldTrigger = linePrefix.endsWith('.') ||
          linePrefix.endsWith('->') ||
          linePrefix.endsWith('=>') ||
          linePrefix.endsWith('(') ||
          linePrefix.endsWith('[') ||
          linePrefix.endsWith('{') ||
          linePrefix.endsWith(',') ||
          linePrefix.endsWith(':') ||
          linePrefix.trim().endsWith('return') ||
          linePrefix.trim().endsWith('=');
      if (!shouldTrigger && textBeforeCursor.trim().length < 15) {
        _setState(InlineCompletionState.idle);
        return;
      }
    }

    // Debounce 请求
    _setState(InlineCompletionState.loading);

    if (triggerKind == CompletionTriggerKind.automatic) {
      _debounceTimer = Timer(Duration(milliseconds: debounceDelayMs), () {
        _fetchCompletion(
          textBeforeCursor: textBeforeCursor,
          textAfterCursor: textAfterCursor,
          filePath: filePath,
          language: language,
          cursorLine: cursorLine,
          cursorColumn: cursorColumn,
        );
      });
    } else {
      _fetchCompletion(
        textBeforeCursor: textBeforeCursor,
        textAfterCursor: textAfterCursor,
        filePath: filePath,
        language: language,
        cursorLine: cursorLine,
        cursorColumn: cursorColumn,
      );
    }
  }

  /// 接受当前建议
  String? acceptSuggestion() {
    if (!hasSuggestion) return null;
    final text = _currentSuggestion!.text;
    _currentSuggestion = null;
    _setState(InlineCompletionState.idle);
    return text;
  }

  /// 取消当前建议
  void cancelSuggestion() {
    _cancelSuggestion();
  }

  /// 强制获取补全（手动触发）
  Future<void> forceComplete({
    required String textBeforeCursor,
    required String textAfterCursor,
    required String filePath,
    required String language,
    required int cursorLine,
    required int cursorColumn,
  }) async {
    _cancelSuggestion();
    _setState(InlineCompletionState.loading);

    await _fetchCompletion(
      textBeforeCursor: textBeforeCursor,
      textAfterCursor: textAfterCursor,
      filePath: filePath,
      language: language,
      cursorLine: cursorLine,
      cursorColumn: cursorColumn,
    );
  }

  /// 清除状态
  void reset() {
    _debounceTimer?.cancel();
    _cancelToken?.cancel();
    _currentSuggestion = null;
    _lastPrefix = '';
    _requestId = 0;
    _setState(InlineCompletionState.idle);
  }

  /// 释放资源
  void dispose() {
    _debounceTimer?.cancel();
    _cancelToken?.cancel();
    _provider = null;
    _currentSuggestion = null;
  }

  // ── 内部方法 ──

  void _cancelSuggestion() {
    _debounceTimer?.cancel();
    _cancelToken?.cancel();
    _currentSuggestion = null;
    _setState(InlineCompletionState.idle);
  }

  void _setState(InlineCompletionState newState) {
    _state = newState;
    _notifyListeners();
  }

  /// 获取当前行的前缀（光标之前的部分）
  String _getLinePrefix(String fullPrefix, int cursorLine) {
    final lines = fullPrefix.split('\n');
    if (cursorLine < lines.length) {
      return lines[cursorLine];
    }
    return lines.isNotEmpty ? lines.last : '';
  }

  Future<void> _fetchCompletion({
    required String textBeforeCursor,
    required String textAfterCursor,
    required String filePath,
    required String language,
    required int cursorLine,
    required int cursorColumn,
  }) async {
    if (_provider == null) {
      _setState(InlineCompletionState.idle);
      return;
    }

    final requestId = ++_requestId;
    final token = CancelToken();
    _cancelToken = token;

    try {
      final request = InlineCompletionRequest(
        filePath: filePath,
        language: language,
        prefix: textBeforeCursor,
        suffix: textAfterCursor,
        textBeforeCursor: textBeforeCursor,
        textAfterCursor: textAfterCursor,
        cursorLine: cursorLine,
        cursorColumn: cursorColumn,
      );

      final completions = await _provider!.getInlineCompletions(
        request: request,
        cancelToken: token,
      );

      // 忽略旧请求的结果
      if (requestId != _requestId || token.isCancelled) return;

      if (completions.isNotEmpty) {
        final best = completions.first;
        final suggestion = GhostTextSuggestion(
          text: best.text,
          providerName: best.label ?? _provider!.name,
          score: best.score,
        );

        if (suggestion.isValid) {
          _currentSuggestion = suggestion;
          _setState(InlineCompletionState.hasSuggestion);
          return;
        }
      }

      _setState(InlineCompletionState.idle);
    } catch (e) {
      if (requestId == _requestId && !token.isCancelled) {
        _currentSuggestion = null;
        _setState(InlineCompletionState.idle);
      }
    }
  }

  // ── 监听器（用于 UI 更新） ──

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

typedef VoidCallback = void Function();
