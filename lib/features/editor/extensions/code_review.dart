import 'dart:async';
import 'dart:convert';

import '../../../core/ai/ai_provider.dart';

/// VoidCallback 等价类型（用于监听器模式）
typedef _VoidCallback = void Function();

/// 审查严重级别
enum ReviewSeverity {
  critical,
  warning,
  info,
  suggestion,
}

/// 审查类别
enum ReviewCategory {
  bug,           // 可能的 Bug
  performance,   // 性能问题
  security,      // 安全问题
  style,         // 代码风格
  refactor,      // 重构建议
  bestPractice,  // 最佳实践
}

/// 单条审查结果
class ReviewItem {
  final ReviewCategory category;
  final ReviewSeverity severity;
  final String title;
  final String description;
  final int? line;
  final String? suggestion; // 改进建议代码

  const ReviewItem({
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    this.line,
    this.suggestion,
  });
}

/// 代码审查结果
class CodeReviewResult {
  final List<ReviewItem> items;
  final int totalIssues;
  final double overallScore; // 0.0 ~ 10.0
  final String? summary;
  final bool hasError;
  final String? errorMessage;

  const CodeReviewResult({
    this.items = const [],
    this.totalIssues = 0,
    this.overallScore = 10.0,
    this.summary,
    this.hasError = false,
    this.errorMessage,
  });

  /// 按类别分组
  Map<ReviewCategory, List<ReviewItem>> get groupedByCategory {
    final map = <ReviewCategory, List<ReviewItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.category, () => []);
      map[item.category]!.add(item);
    }
    return map;
  }

  /// 按严重级别分组
  Map<ReviewSeverity, List<ReviewItem>> get groupedBySeverity {
    final map = <ReviewSeverity, List<ReviewItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.severity, () => []);
      map[item.severity]!.add(item);
    }
    return map;
  }

  int get criticalCount =>
      items.where((i) => i.severity == ReviewSeverity.critical).length;
  int get warningCount =>
      items.where((i) => i.severity == ReviewSeverity.warning).length;

  bool get isValid => !hasError && items.isNotEmpty;
}

/// ReviewProvider 抽象接口
///
/// 所有代码审查能力通过此接口暴露。
/// UI 层不依赖具体实现。
abstract class ReviewProvider {
  String get name;

  /// 审查整个文件
  Future<CodeReviewResult> reviewFile({
    required String code,
    required String language,
    required String filePath,
  });

  /// 审查选中的代码
  Future<CodeReviewResult> reviewSelection({
    required String code,
    required String language,
  });

  /// 取消审查
  void cancel();
}

/// AI 代码审查引擎
///
/// 使用 AI 对代码进行审查，输出：
/// - 可能的 Bug
/// - 性能问题
/// - 安全问题
/// - 代码风格问题
/// - 重构建议
class CodeReviewEngine implements ReviewProvider {
  final AiProvider _aiProvider;
  CancelToken? _cancelToken;
  bool _isReviewing = false;
  CodeReviewResult? _lastResult;

  CodeReviewEngine(this._aiProvider);

  @override
  String get name => 'AI Review';

  bool get isReviewing => _isReviewing;
  CodeReviewResult? get lastResult => _lastResult;

  @override
  Future<CodeReviewResult> reviewFile({
    required String code,
    required String language,
    required String filePath,
  }) async {
    return _review(code: code, language: language, scope: 'file');
  }

  @override
  Future<CodeReviewResult> reviewSelection({
    required String code,
    required String language,
  }) async {
    return _review(code: code, language: language, scope: 'selection');
  }

  @override
  void cancel() {
    _cancelToken?.cancel();
    _isReviewing = false;
    _notifyListeners();
  }

  void dispose() {
    _cancelToken?.cancel();
    _listeners.clear();
  }

  // ── 内部方法 ──

  Future<CodeReviewResult> _review({
    required String code,
    required String language,
    required String scope,
  }) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    _isReviewing = true;
    _notifyListeners();

    try {
      final systemPrompt = _buildSystemPrompt();
      final userPrompt = _buildUserPrompt(code, language, scope);

      final response = await _aiProvider.chat(
        messages: [
          ChatMessageInput(role: 'system', content: systemPrompt),
          ChatMessageInput(role: 'user', content: userPrompt),
        ],
        temperature: 0.2,
        cancelToken: _cancelToken,
      );

      if (_cancelToken?.isCancelled == true) {
        _isReviewing = false;
        _notifyListeners();
        return const CodeReviewResult();
      }

      final result = _parseResponse(response);
      _lastResult = result;
      _isReviewing = false;
      _notifyListeners();
      return result;
    } catch (e) {
      _isReviewing = false;
      _lastResult = CodeReviewResult(
        hasError: true,
        errorMessage: '审查失败: $e',
      );
      _notifyListeners();
      return _lastResult!;
    }
  }

  String _buildSystemPrompt() {
    return '''You are an expert code reviewer. Analyze the provided code and produce a structured review.

Return ONLY valid JSON with this exact structure:
{
  "summary": "Overall assessment (1-2 sentences)",
  "score": 8.5,
  "issues": [
    {
      "category": "bug|performance|security|style|refactor|bestPractice",
      "severity": "critical|warning|info|suggestion",
      "title": "Short issue title",
      "description": "Detailed explanation (in Chinese)",
      "line": 12,
      "suggestion": "Suggestion code or fix description"
    }
  ]
}

Rules:
- score: 0.0-10.0, where 10 is perfect
- Use Chinese for descriptions
- Be specific about the actual code
- Focus on real issues, don't make up problems
- line number is 0-based, omit if not applicable
- For bug category: actual bugs or logic errors
- For performance: inefficient operations
- For security: injection risks, unsafe operations
- For style: formatting, naming conventions
- For refactor: code structure improvements''';
  }

  String _buildUserPrompt(String code, String language, String scope) {
    final scopeLabel = scope == 'file' ? 'entire file' : 'selected code';
    return 'Review this $language code ($scopeLabel):\n\n```$language\n$code\n```\n\nReturn JSON output only.';
  }

  CodeReviewResult _parseResponse(String response) {
    try {
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');

      if (jsonStart != -1 && jsonEnd != -1) {
        final jsonStr = response.substring(jsonStart, jsonEnd + 1);
        final dynamic decoded = jsonDecode(jsonStr);
        final data = Map<String, dynamic>.from(decoded as Map);

        final summary = data['summary']?.toString();
        final score = (data['score'] as num?)?.toDouble() ?? 10.0;
        final issuesRaw = data['issues'] as List<dynamic>? ?? [];

        final items = <ReviewItem>[];
        for (final raw in issuesRaw) {
          if (raw is! Map) continue;
          final item = _parseIssue(Map<String, dynamic>.from(raw));
          if (item != null) items.add(item);
        }

        return CodeReviewResult(
          items: items,
          totalIssues: items.length,
          overallScore: score,
          summary: summary,
        );
      }
    } catch (_) {}

    return const CodeReviewResult(
      hasError: true,
      errorMessage: '无法解析审查结果',
    );
  }

  ReviewItem? _parseIssue(Map<String, dynamic> data) {
    try {
      final category = _parseCategory(data['category']?.toString());
      final severity = _parseSeverity(data['severity']?.toString());
      final title = data['title']?.toString() ?? '';
      final description = data['description']?.toString() ?? '';
      final line = data['line'] as int?;
      final suggestion = data['suggestion']?.toString();

      if (title.isEmpty) return null;

      return ReviewItem(
        category: category,
        severity: severity,
        title: title,
        description: description,
        line: line,
        suggestion: suggestion,
      );
    } catch (_) {
      return null;
    }
  }

  ReviewCategory _parseCategory(String? value) {
    switch (value?.toLowerCase()) {
      case 'bug':
        return ReviewCategory.bug;
      case 'performance':
        return ReviewCategory.performance;
      case 'security':
        return ReviewCategory.security;
      case 'style':
        return ReviewCategory.style;
      case 'refactor':
        return ReviewCategory.refactor;
      default:
        return ReviewCategory.bestPractice;
    }
  }

  ReviewSeverity _parseSeverity(String? value) {
    switch (value?.toLowerCase()) {
      case 'critical':
        return ReviewSeverity.critical;
      case 'warning':
        return ReviewSeverity.warning;
      case 'info':
        return ReviewSeverity.info;
      default:
        return ReviewSeverity.suggestion;
    }
  }

  // ── 监听器 ──

  final List<_VoidCallback> _listeners = [];

  void addListener(_VoidCallback callback) => _listeners.add(callback);
  void removeListener(_VoidCallback callback) => _listeners.remove(callback);

  void _notifyListeners() {
    for (final l in List<_VoidCallback>.from(_listeners)) {
      l();
    }
  }
}
