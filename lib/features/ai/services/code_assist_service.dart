import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ai/chat_engine.dart';
import '../../../../core/ai/ai_message.dart';
import '../../../../core/ai/ai_provider_manager.dart';
import '../../../../core/context/workspace_context_provider.dart';

// ══════════════════════════════════════════════
// Provider
// ══════════════════════════════════════════════

/// AI 编程助手服务 Provider
final codeAssistServiceProvider = Provider<CodeAssistService>((ref) {
  final engine = ref.watch(chatEngineProvider);
  return CodeAssistService(engine: engine);
});

// ══════════════════════════════════════════════
// 辅助类型
// ══════════════════════════════════════════════

/// AI 分析结果
class AiAssistResult {
  final String explanation;
  final String? codeSnippet;
  final List<String> suggestions;

  const AiAssistResult({
    required this.explanation,
    this.codeSnippet,
    this.suggestions = const [],
  });
}

/// AI 代码审查报告
class CodeReviewReport {
  final int totalIssues;
  final List<CodeIssue> issues;
  final String summary;

  const CodeReviewReport({
    required this.totalIssues,
    required this.issues,
    required this.summary,
  });
}

/// 代码问题
class CodeIssue {
  final String category; // performance, security, quality, duplicate, complexity
  final String severity; // critical, major, minor, suggestion
  final String title;
  final String description;
  final String? suggestion;

  const CodeIssue({
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    this.suggestion,
  });
}

/// 提交信息生成结果
class CommitMessageResult {
  final String title;
  final String body;
  final String fullMessage;

  const CommitMessageResult({
    required this.title,
    required this.body,
    required this.fullMessage,
  });
}

// ══════════════════════════════════════════════
// 系统提示词
// ══════════════════════════════════════════════

class _Prompts {
  static const String fixBug = '''
你是一个 Flutter/Dart 调试专家。用户会粘贴报错日志和相关代码。
请：
1. 分析错误根因（用中文）
2. 给出修复方案（含可运行的代码）
3. 列出可能相关的文件

格式要求：
- 用 ```dart 包裹代码
- 根因用 **粗体** 标注
- 如果问题可复现，说明复现步骤
''';

  static const String explainCode = '''
你是一个资深 Flutter/Dart 工程师。用户会粘贴代码。
请用中文解释：
1. 这段代码的功能
2. 关键逻辑和设计模式
3. 使用的 API 的作用
4. 可能的改进点（如果有时）

保持简洁，避免过度解读。
''';

  static const String refactorCode = '''
你是一个代码重构专家。用户会粘贴需要重构的代码。
请：
1. 分析当前代码存在的问题（重复、过长、耦合等）
2. 给出重构后的代码（完整可运行）
3. 说明做了哪些改进

格式：用 ```dart 包裹重构后的代码。
优先推荐：提取函数、提取 Widget、使用设计模式、简化条件表达式。
''';

  static const String generateTest = '''
你是一个 Flutter 测试专家。用户会粘贴一个 Dart 类/函数。
请生成完整的单元测试代码：
1. 使用 flutter_test 框架
2. 覆盖正常路径和边界情况
3. 使用 mockito/mocktail mock 依赖
4. 包含必要的 import

格式：用 ```dart 包裹测试代码。
只输出可运行的测试代码，不包含解释说明。
''';

  static const String commitMessage = '''
你是一个 Git Commit Message 专家。用户会粘贴 git diff 输出。
请生成规范的 Commit Message：

格式：
<type>(<scope>): <简短描述>

<详细说明（可选）>

类型：feat/fix/refactor/docs/style/test/chore/ci
scope：影响范围

要求：
- 第一行不超过 72 字符
- 用中文写描述
- 列出关键变更点
- 如果 breaking change，在正文末尾标注 BREAKING CHANGE
''';

  static const String codeReview = '''
你是一个代码审查专家。用户会粘贴需要审查的代码。
请从以下维度分析：

1. 🐛 潜在 Bug（critical）
2. ⚡ 性能问题（major）
3. 🛡️ 安全问题（major）
4. 📐 代码质量（minor）
5. 🔄 重复代码（minor）
6. 🧩 复杂度（suggestion）

对每个问题给出：严重级别、问题描述、改进建议。
最后给出总体评价和优先级建议。
''';
}

// ══════════════════════════════════════════════
// CodeAssistService
// ══════════════════════════════════════════════

/// AI 编程辅助服务
///
/// 基于 ChatEngine 提供 6 个 Sprint 8 功能：
/// - 修 Bug（fixBug）
/// - 解释代码（explainCode）
/// - 重构（refactorCode）
/// - 生成测试（generateTest）
/// - 生成 Commit Message（generateCommitMessage）
/// - 代码审查（codeReview）
class CodeAssistService {
  final IChatEngine _engine;

  CodeAssistService({required IChatEngine engine}) : _engine = engine;

  /// 临时会话 ID（每个辅助功能使用独立会话）
  String? _assistSessionId;

  /// 获取或创建辅助会话
  IChatEngine get engine => _engine;

  String _getOrCreateSession() {
    if (_assistSessionId == null || _engine.getSession(_assistSessionId!) == null) {
      final session = _engine.createSession(metadata: const {'type': 'assist'});
      _assistSessionId = session.sessionId;
    }
    return _assistSessionId!;
  }

  /// 发送辅助请求并获取完整响应
  Future<String> _sendAssist({
    required String systemPrompt,
    required String userContent,
  }) async {
    final sessionId = _getOrCreateSession();
    final session = _engine.getSession(sessionId)!;

    // 使用引擎的 streamMessage 获取非流式响应
    final result = await _engine.sendMessage(
      sessionId: sessionId,
      content: userContent,
    );
    return result.content;
  }

  /// 流式发送辅助请求
  Stream<String> _streamAssist({
    required String systemPrompt,
    required String userContent,
  }) async* {
    final sessionId = _getOrCreateSession();

    // 临时替换 system prompt
    final originalPrompt = _engine.systemPrompt;
    _engine.systemPrompt = systemPrompt;

    try {
      await for (final chunk in _engine.streamMessage(
        sessionId: sessionId,
        content: userContent,
      )) {
        yield chunk;
      }
    } finally {
      _engine.systemPrompt = originalPrompt;
    }
  }

  // ══════════════════════════════════════════════
  // 1. AI 修 Bug
  // ══════════════════════════════════════════════

  /// 分析错误日志并给出修复方案
  Future<AiAssistResult> fixBug({
    required String errorLog,
    String? relatedCode,
    String? filePath,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('## 错误日志');
    buffer.writeln('```');
    buffer.writeln(errorLog);
    buffer.writeln('```');

    if (relatedCode != null && relatedCode.isNotEmpty) {
      buffer.writeln('\n## 相关代码');
      buffer.writeln('```dart');
      buffer.writeln(relatedCode);
      buffer.writeln('```');
    }

    if (filePath != null && filePath.isNotEmpty) {
      buffer.writeln('\n文件路径: $filePath');
    }

    final response = await _sendAssist(
      systemPrompt: _Prompts.fixBug,
      userContent: buffer.toString(),
    );

    return _parseAssistResult(response);
  }

  /// 流式分析错误
  Stream<String> fixBugStream({
    required String errorLog,
    String? relatedCode,
    String? filePath,
  }) async* {
    final buffer = StringBuffer();
    buffer.writeln('## 错误日志');
    buffer.writeln('```');
    buffer.writeln(errorLog);
    buffer.writeln('```');

    if (relatedCode != null && relatedCode.isNotEmpty) {
      buffer.writeln('\n## 相关代码');
      buffer.writeln('```dart');
      buffer.writeln(relatedCode);
      buffer.writeln('```');
    }

    if (filePath != null && filePath.isNotEmpty) {
      buffer.writeln('\n文件路径: $filePath');
    }

    yield* _streamAssist(
      systemPrompt: _Prompts.fixBug,
      userContent: buffer.toString(),
    );
  }

  // ══════════════════════════════════════════════
  // 2. AI 解释代码
  // ══════════════════════════════════════════════

  /// 解释代码
  Future<AiAssistResult> explainCode({
    required String code,
    String? language,
    String? filePath,
  }) async {
    final buffer = StringBuffer();
    if (filePath != null && filePath.isNotEmpty) {
      buffer.writeln('文件: $filePath\n');
    }
    buffer.writeln('```${language ?? 'dart'}');
    buffer.writeln(code);
    buffer.writeln('```');

    final response = await _sendAssist(
      systemPrompt: _Prompts.explainCode,
      userContent: buffer.toString(),
    );

    return _parseAssistResult(response);
  }

  /// 流式解释代码
  Stream<String> explainCodeStream({
    required String code,
    String? language,
    String? filePath,
  }) async* {
    final buffer = StringBuffer();
    if (filePath != null && filePath.isNotEmpty) {
      buffer.writeln('文件: $filePath\n');
    }
    buffer.writeln('```${language ?? 'dart'}');
    buffer.writeln(code);
    buffer.writeln('```');

    yield* _streamAssist(
      systemPrompt: _Prompts.explainCode,
      userContent: buffer.toString(),
    );
  }

  // ══════════════════════════════════════════════
  // 3. AI 重构
  // ══════════════════════════════════════════════

  /// 重构代码
  Future<AiAssistResult> refactorCode({
    required String code,
    String? language,
    String? filePath,
  }) async {
    final buffer = StringBuffer();
    if (filePath != null && filePath.isNotEmpty) {
      buffer.writeln('文件: $filePath\n');
    }
    buffer.writeln('```${language ?? 'dart'}');
    buffer.writeln(code);
    buffer.writeln('```');

    final response = await _sendAssist(
      systemPrompt: _Prompts.refactorCode,
      userContent: buffer.toString(),
    );

    return _parseAssistResult(response);
  }

  // ══════════════════════════════════════════════
  // 4. AI 生成测试
  // ══════════════════════════════════════════════

  /// 生成单元测试
  Future<AiAssistResult> generateTest({
    required String sourceCode,
    required String className,
    String? filePath,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('类名: $className\n');
    if (filePath != null && filePath.isNotEmpty) {
      buffer.writeln('源文件: $filePath\n');
    }
    buffer.writeln('```dart');
    buffer.writeln(sourceCode);
    buffer.writeln('```');

    final response = await _sendAssist(
      systemPrompt: _Prompts.generateTest,
      userContent: buffer.toString(),
    );

    return _parseAssistResult(response);
  }

  // ══════════════════════════════════════════════
  // 5. AI 生成 Commit Message
  // ══════════════════════════════════════════════

  /// 根据 git diff 生成 Commit Message
  Future<CommitMessageResult> generateCommitMessage({
    required String gitDiff,
    String? branchInfo,
  }) async {
    final buffer = StringBuffer();
    if (branchInfo != null && branchInfo.isNotEmpty) {
      buffer.writeln('分支: $branchInfo\n');
    }
    buffer.writeln('```diff');
    buffer.writeln(gitDiff);
    buffer.writeln('```');

    final response = await _sendAssist(
      systemPrompt: _Prompts.commitMessage,
      userContent: buffer.toString(),
    );

    return _parseCommitResult(response);
  }

  // ══════════════════════════════════════════════
  // 6. AI 代码审查
  // ══════════════════════════════════════════════

  /// 代码审查
  Future<CodeReviewReport> codeReview({
    required String code,
    String? language,
    String? filePath,
  }) async {
    final buffer = StringBuffer();
    if (filePath != null && filePath.isNotEmpty) {
      buffer.writeln('文件: $filePath\n');
    }
    buffer.writeln('```${language ?? 'dart'}');
    buffer.writeln(code);
    buffer.writeln('```');

    final response = await _sendAssist(
      systemPrompt: _Prompts.codeReview,
      userContent: buffer.toString(),
    );

    return _parseReviewResult(response);
  }

  // ══════════════════════════════════════════════
  // 解析辅助方法
  // ══════════════════════════════════════════════

  AiAssistResult _parseAssistResult(String text) {
    // 提取代码块
    final codeRegex = RegExp(r'```(\w*)\n([\s\S]*?)```');
    final codeMatch = codeRegex.firstMatch(text);
    final codeSnippet = codeMatch?.group(2);

    // 提取列表项作为建议
    final suggestionRegex = RegExp(r'^[-*]\s+(.+)$', multiLine: true);
    final suggestions = suggestionRegex
        .allMatches(text)
        .map((m) => m.group(1)!)
        .where((s) => s.length > 10)
        .toList();

    return AiAssistResult(
      explanation: text,
      codeSnippet: codeSnippet,
      suggestions: suggestions,
    );
  }

  CommitMessageResult _parseCommitResult(String text) {
    final lines = text.trim().split('\n');
    final title = lines.isNotEmpty ? lines.first.trim() : 'chore: update';
    final body = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';

    return CommitMessageResult(
      title: title,
      body: body,
      fullMessage: text.trim(),
    );
  }

  CodeReviewReport _parseReviewResult(String text) {
    final issues = <CodeIssue>[];

    // 按 emoji 分类解析
    final categoryMap = {
      '🐛': 'bug',
      '⚡': 'performance',
      '🛡️': 'security',
      '📐': 'quality',
      '🔄': 'duplicate',
      '🧩': 'complexity',
    };

    final severityMap = {
      'critical': 'critical',
      'major': 'major',
      'minor': 'minor',
      'suggestion': 'suggestion',
    };

    // 提取问题行
    final issueRegex = RegExp(
      r'[-*]\s+\*\*(.+?)\*\*\s*[：:]\s*(.+?)(?=\n[-*]\s+\*\*|\Z)',
      dotAll: true,
    );

    for (final match in issueRegex.allMatches(text)) {
      final title = match.group(1)?.trim() ?? '';
      final description = match.group(2)?.trim() ?? '';

      // 推断分类
      String category = 'quality';
      for (final entry in categoryMap.entries) {
        if (text.contains(entry.key)) {
          category = entry.value;
          break;
        }
      }

      // 推断严重级别
      String severity = 'minor';
      for (final entry in severityMap.entries) {
        if (description.contains(entry.key)) {
          severity = entry.value;
          break;
        }
      }

      issues.add(CodeIssue(
        category: category,
        severity: severity,
        title: title,
        description: description,
      ));
    }

    // 取第一段作为总结
    final summary = text.split('\n').firstWhere(
      (l) => l.contains('总结') || l.contains('总体') || l.contains('建议'),
      orElse: () => text.split('\n').first,
    );

    return CodeReviewReport(
      totalIssues: issues.length,
      issues: issues,
      summary: summary,
    );
  }
}
