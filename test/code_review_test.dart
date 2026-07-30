import 'package:codex_mobile_pro/core/ai/ai_provider.dart';
import 'package:codex_mobile_pro/features/editor/extensions/code_review.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 AI Provider（用于测试）
class MockAiProvider extends AiProvider {
  final String _name;
  final AiProviderStatus _status;
  final Future<String> Function(List<ChatMessageInput> messages, double temperature, int maxTokens, CancelToken? cancelToken)? _chatHandler;

  MockAiProvider({
    String name = 'MockAI',
    AiProviderStatus status = AiProviderStatus.ready,
    Future<String> Function(List<ChatMessageInput> messages, double temperature, int maxTokens, CancelToken? cancelToken)? chatHandler,
  }) : _name = name,
       _status = status,
       _chatHandler = chatHandler;

  @override
  String get name => _name;

  @override
  AiProviderStatus get status => _status;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<InlineCompletion>> getInlineCompletions({
    required InlineCompletionRequest request,
    CompletionTriggerKind triggerKind = CompletionTriggerKind.automatic,
    CancelToken? cancelToken,
  }) async => [];

  @override
  Stream<String> streamChat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
  }) async* {}

  @override
  Future<String> chat({
    required List<ChatMessageInput> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
    CancelToken? cancelToken,
  }) async {
    if (_chatHandler != null) {
      return _chatHandler(messages, temperature, maxTokens, cancelToken);
    }
    return '';
  }

  @override
  Future<bool> healthCheck() async => true;

  @override
  void dispose() {}
}

void main() {
  group('ReviewItem', () {
    test('创建审查条目', () {
      const item = ReviewItem(
        category: ReviewCategory.bug,
        severity: ReviewSeverity.critical,
        title: '空指针异常',
        description: '变量可能为 null 时未判空',
        line: 42,
        suggestion: 'if (x != null) { ... }',
      );

      expect(item.category, ReviewCategory.bug);
      expect(item.severity, ReviewSeverity.critical);
      expect(item.title, '空指针异常');
      expect(item.description, '变量可能为 null 时未判空');
      expect(item.line, 42);
      expect(item.suggestion, 'if (x != null) { ... }');
    });

    test('审查条目支持可选字段为空', () {
      const item = ReviewItem(
        category: ReviewCategory.style,
        severity: ReviewSeverity.suggestion,
        title: '命名规范',
        description: '建议使用驼峰命名',
      );

      expect(item.line, isNull);
      expect(item.suggestion, isNull);
    });
  });

  group('CodeReviewResult', () {
    test('创建空结果', () {
      const result = CodeReviewResult();

      expect(result.items, isEmpty);
      expect(result.totalIssues, 0);
      expect(result.overallScore, 10.0);
      expect(result.summary, isNull);
      expect(result.hasError, false);
      expect(result.isValid, false);
    });

    test('创建带审查条目的结果', () {
      final items = [
        const ReviewItem(
          category: ReviewCategory.bug,
          severity: ReviewSeverity.critical,
          title: 'Bug 1',
          description: '描述',
        ),
        const ReviewItem(
          category: ReviewCategory.performance,
          severity: ReviewSeverity.warning,
          title: 'Perf 1',
          description: '描述',
        ),
      ];

      final result = CodeReviewResult(
        items: items,
        totalIssues: 2,
        overallScore: 7.5,
        summary: '代码整体质量良好，但有一些问题',
      );

      expect(result.items.length, 2);
      expect(result.totalIssues, 2);
      expect(result.overallScore, 7.5);
      expect(result.summary, '代码整体质量良好，但有一些问题');
      expect(result.isValid, true);
    });

    test('按类别分组', () {
      final items = [
        const ReviewItem(
          category: ReviewCategory.bug,
          severity: ReviewSeverity.critical,
          title: 'Bug1',
          description: '',
        ),
        const ReviewItem(
          category: ReviewCategory.bug,
          severity: ReviewSeverity.warning,
          title: 'Bug2',
          description: '',
        ),
        const ReviewItem(
          category: ReviewCategory.performance,
          severity: ReviewSeverity.info,
          title: 'Perf1',
          description: '',
        ),
      ];

      final result = CodeReviewResult(items: items, totalIssues: 3);
      final grouped = result.groupedByCategory;

      expect(grouped[ReviewCategory.bug]?.length, 2);
      expect(grouped[ReviewCategory.performance]?.length, 1);
      expect(grouped[ReviewCategory.style], isNull);
    });

    test('按严重级别分组', () {
      final items = [
        const ReviewItem(
          category: ReviewCategory.security,
          severity: ReviewSeverity.critical,
          title: 'Sec1',
          description: '',
        ),
        const ReviewItem(
          category: ReviewCategory.bug,
          severity: ReviewSeverity.warning,
          title: 'Bug1',
          description: '',
        ),
        const ReviewItem(
          category: ReviewCategory.style,
          severity: ReviewSeverity.suggestion,
          title: 'Style1',
          description: '',
        ),
      ];

      final result = CodeReviewResult(items: items, totalIssues: 3);

      expect(result.criticalCount, 1);
      expect(result.warningCount, 1);
    });

    test('错误结果', () {
      const result = CodeReviewResult(
        hasError: true,
        errorMessage: 'API 连接失败',
      );

      expect(result.hasError, true);
      expect(result.errorMessage, 'API 连接失败');
      expect(result.isValid, false);
    });
  });

  group('CodeReviewEngine', () {
    test('构造引擎', () {
      final provider = MockAiProvider();
      final engine = CodeReviewEngine(provider);

      expect(engine.name, 'AI Review');
      expect(engine.isReviewing, false);
      expect(engine.lastResult, isNull);
    });

    test('解析有效的 JSON 审查响应', () async {
      const jsonResponse = '''
{
  "summary": "代码整体质量不错，但有一处性能问题",
  "score": 8.0,
  "issues": [
    {
      "category": "performance",
      "severity": "warning",
      "title": "不必要的循环",
      "description": "可以使用 map 替代 for 循环",
      "line": 15,
      "suggestion": "使用 .map() 方法"
    },
    {
      "category": "style",
      "severity": "info",
      "title": "缺少类型标注",
      "description": "变量建议添加类型",
      "line": 3
    }
  ]
}
''';

      final provider = MockAiProvider(
        chatHandler: (messages, temperature, maxTokens, cancelToken) async {
          // 验证系统提示中的关键内容
          final systemMsg = messages.firstWhere((m) => m.role == 'system');
          expect(systemMsg.content, contains('expert code reviewer'));

          final userMsg = messages.firstWhere((m) => m.role == 'user');
          expect(userMsg.content, contains('Dart'));

          return jsonResponse;
        },
      );

      final engine = CodeReviewEngine(provider);
      final result = await engine.reviewSelection(
        code: 'void main() { for (var i = 0; i < 10; i++) { print(i); } }',
        language: 'Dart',
      );

      expect(result.isValid, true);
      expect(result.overallScore, 8.0);
      expect(result.summary, '代码整体质量不错，但有一处性能问题');
      expect(result.items.length, 2);

      // 第一个问题
      final first = result.items[0];
      expect(first.category, ReviewCategory.performance);
      expect(first.severity, ReviewSeverity.warning);
      expect(first.title, '不必要的循环');
      expect(first.line, 15);
      expect(first.suggestion, '使用 .map() 方法');

      // 第二个问题
      final second = result.items[1];
      expect(second.category, ReviewCategory.style);
      expect(second.severity, ReviewSeverity.info);
      expect(second.title, '缺少类型标注');
      expect(second.line, 3);
      expect(second.suggestion, isNull);
    });

    test('处理 JSON 解析失败', () async {
      final provider = MockAiProvider(
        chatHandler: (messages, temperature, maxTokens, cancelToken) async {
          return '这不是 JSON 响应';
        },
      );

      final engine = CodeReviewEngine(provider);
      final result = await engine.reviewSelection(
        code: 'int x = 1;',
        language: 'Dart',
      );

      expect(result.hasError, true);
      expect(result.errorMessage, contains('无法解析'));
      expect(result.isValid, false);
    });

    test('处理 AI 异常', () async {
      final provider = MockAiProvider(
        chatHandler: (messages, temperature, maxTokens, cancelToken) async {
          throw Exception('API 超时');
        },
      );

      final engine = CodeReviewEngine(provider);
      final result = await engine.reviewSelection(
        code: 'int x = 1;',
        language: 'Dart',
      );

      expect(result.hasError, true);
      expect(result.errorMessage, contains('审查失败'));
      expect(result.isValid, false);
    });

    test('支持取消审查', () async {
      final provider = MockAiProvider(
        chatHandler: (messages, temperature, maxTokens, cancelToken) async {
          // 模拟长时间运行
          await Future.delayed(const Duration(seconds: 10));
          return '{}';
        },
      );

      final engine = CodeReviewEngine(provider);

      // 启动审查，然后立即取消
      final future = engine.reviewSelection(
        code: 'print("hello");',
        language: 'Dart',
      );

      engine.cancel();

      final result = await future;
      expect(result.items, isEmpty);
      expect(result.isValid, false);
    });

    test('reviewFile 和 reviewSelection 接口一致', () async {
      final provider = MockAiProvider(
        chatHandler: (messages, temperature, maxTokens, cancelToken) async {
          return '{"summary":"OK","score":9.0,"issues":[]}';
        },
      );

      final engine = CodeReviewEngine(provider);

      final fileResult = await engine.reviewFile(
        code: 'int x = 1;',
        language: 'Dart',
        filePath: '/test/test.dart',
      );

      final selResult = await engine.reviewSelection(
        code: 'int x = 1;',
        language: 'Dart',
      );

      expect(fileResult.isValid, false);
      expect(fileResult.summary, 'OK');
      expect(selResult.isValid, false);
      expect(selResult.summary, 'OK');
    });
  });

  group('ReviewProvider 接口', () {
    test('CodeReviewEngine 实现 ReviewProvider', () {
      final provider = MockAiProvider();
      final engine = CodeReviewEngine(provider);

      // 验证引擎实现了 ReviewProvider 接口
      expect(engine, isA<ReviewProvider>());
      expect(engine.name, isNotEmpty);
    });

    test('ReviewProvider 可以取消', () {
      final provider = MockAiProvider();
      final engine = CodeReviewEngine(provider) as ReviewProvider;

      // 取消不应抛出异常
      expect(() => engine.cancel(), returnsNormally);
    });
  });
}
