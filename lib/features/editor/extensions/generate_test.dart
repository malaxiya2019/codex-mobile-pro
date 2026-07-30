import 'dart:async';
import '../../../core/ai/ai_provider.dart';

/// 测试生成结果
class TestGenResult {
  final String testCode;
  final String testFileName;
  final bool hasError;
  final String? errorMessage;

  const TestGenResult({
    required this.testCode,
    this.testFileName = '',
    this.hasError = false,
    this.errorMessage,
  });

  bool get isValid => !hasError && testCode.isNotEmpty;
}

/// 测试生成引擎
class TestGenerator {
  final AiProvider _aiProvider;
  CancelToken? _cancelToken;
  TestGenResult? _lastResult;

  TestGenerator(this._aiProvider);

  TestGenResult? get lastResult => _lastResult;

  /// 生成测试
  Future<TestGenResult> generateTest({
    required String sourceCode,
    required String className,
    required String language,
  }) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    try {
      final systemPrompt = _buildSystemPrompt();
      final userPrompt = _buildUserPrompt(sourceCode, className, language);

      final response = await _aiProvider.chat(
        messages: [
          ChatMessageInput(role: 'system', content: systemPrompt),
          ChatMessageInput(role: 'user', content: userPrompt),
        ],
        temperature: 0.2,
        cancelToken: _cancelToken,
      );

      if (_cancelToken?.isCancelled == true) {
        return const TestGenResult(testCode: '');
      }

      final result = _parseResponse(response, className);
      _lastResult = result;
      return result;
    } catch (e) {
      _lastResult = TestGenResult(
        testCode: '',
        hasError: true,
        errorMessage: '生成测试失败: $e',
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
    return '''你是一个 Flutter/Dart 测试专家。根据提供的源代码生成完整的单元测试。

要求：
- 使用 flutter_test 框架
- 使用 mocktail 或 mockito mock 依赖
- 覆盖正常路径和边界情况
- 测试用例命名清晰（中文或英文，参照源文件）
- 包含必要的 import 语句

只输出有效的 JSON：
{
  "code": "完整的测试代码，用 ```dart 包裹",
  "fileName": "建议的测试文件名，如 xxx_test.dart"
}

规则：只输出可运行的测试代码，不包含额外解释。''';
  }

  String _buildUserPrompt(String code, String className, String language) {
    return '''为以下 $language 类生成单元测试：

类名: $className

```$language
$code
```

Return JSON output only.''';
  }

  TestGenResult _parseResponse(String response, String className) {
    try {
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        final jsonStr = response.substring(jsonStart, jsonEnd + 1);
        // Simple key-value extraction
        final codeMatch = RegExp(r'"code"\s*:\s*"(.+?)"\s*[,}]', dotAll: true).firstMatch(jsonStr);
        final nameMatch = RegExp(r'"fileName"\s*:\s*"(.+?)"\s*[,}]').firstMatch(jsonStr);

        String code = codeMatch?.group(1) ?? '';
        code = code.replaceAll('\\n', '\n').replaceAll('\\"', '"').replaceAll('\\t', '\t');

        final fileName = nameMatch?.group(1) ?? '${className.toLowerCase()}_test.dart';

        // Extract code from markdown code block if present
        final blockMatch = RegExp(r'```(?:dart)?\s*\n([\s\S]*?)```').firstMatch(code);
        if (blockMatch != null) {
          code = blockMatch.group(1)!;
        }

        return TestGenResult(
          testCode: code,
          testFileName: fileName,
        );
      }
    } catch (_) {}

    // Fallback: try to extract code block directly
    final blockMatch = RegExp(r'```(?:dart)?\s*\n([\s\S]*?)```').firstMatch(response);
    if (blockMatch != null) {
      return TestGenResult(
        testCode: blockMatch.group(1)!,
        testFileName: '${className.toLowerCase()}_test.dart',
      );
    }

    return TestGenResult(
      testCode: response,
      testFileName: '${className.toLowerCase()}_test.dart',
      hasError: true,
      errorMessage: '无法解析 AI 响应',
    );
  }
}
