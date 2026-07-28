import '../models/editor_models.dart';

/// Outline 节点类型
enum OutlineNodeKind {
  file,
  module,
  namespace,
  `package`,
  `class`,
  method,
  property,
  field,
  constructor,
  `enum`,
  interface,
  function,
  variable,
  constant,
  string,
  number,
  boolean,
  array,
  object,
  key,
  null_,
  enumMember,
  `struct`,
  event,
  `operator`,
  typeParameter,
}

/// Outline 节点
class OutlineNode {
  final String name;
  final OutlineNodeKind kind;
  final int line;
  final int column;
  final int length;
  final int? childrenCount;
  final List<OutlineNode> children;
  final String? detail;

  const OutlineNode({
    required this.name,
    required this.kind,
    required this.line,
    required this.column,
    this.length = 0,
    this.childrenCount,
    this.children = const [],
    this.detail,
  });
}

/// Outline 提供者接口
///
/// 为编辑器提供文件概览（结构大纲）。
/// 可扩展：实现此接口以添加自定义 Outline 源。
abstract class OutlineProvider {
  String get name;

  /// 获取文件的 Outline 结构
  Future<List<OutlineNode>> getOutline({
    required String filePath,
    required String text,
    required FileLanguage language,
  });

  /// 是否应为此语言激活
  bool supportsLanguage(FileLanguage language);
}

/// Dart 基础 Outline 提取器
class DartOutlineProvider extends OutlineProvider {
  @override
  String get name => 'Dart Outline';

  @override
  bool supportsLanguage(FileLanguage language) =>
      language == FileLanguage.dart;

  @override
  Future<List<OutlineNode>> getOutline({
    required String filePath,
    required String text,
    required FileLanguage language,
  }) async {
    final nodes = <OutlineNode>[];
    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      // 类定义
      final classMatch = RegExp(r'^(abstract\s+)?(class|mixin|enum|extension)\s+(\w+)').firstMatch(trimmed);
      if (classMatch != null) {
        final kind = classMatch.group(2);
        nodes.add(OutlineNode(
          name: classMatch.group(3)!,
          kind: kind == 'enum'
              ? OutlineNodeKind.enum_
              : kind == 'mixin'
                  ? OutlineNodeKind.module
                  : OutlineNodeKind.class_,
          line: i,
          column: line.length - trimmed.length,
        ));
        continue;
      }

      // 函数/方法定义
      final funcMatch = RegExp(r'^(static\s+)?(Future<)?\w+\s+(\w+)\s*\(').firstMatch(trimmed);
      if (funcMatch != null) {
        nodes.add(OutlineNode(
          name: funcMatch.group(3)!,
          kind: OutlineNodeKind.function,
          line: i,
          column: line.length - trimmed.length,
          detail: funcMatch.group(0),
        ));
        continue;
      }

      // 顶层 const/final/var
      final topMatch = RegExp(r'^(const|final|late\s+final|var)\s+(\w+)').firstMatch(trimmed);
      if (topMatch != null) {
        nodes.add(OutlineNode(
          name: topMatch.group(2)!,
          kind: OutlineNodeKind.variable,
          line: i,
          column: line.length - trimmed.length,
        ));
        continue;
      }

      // typedef
      final typedefMatch = RegExp(r'^typedef\s+(\w+)').firstMatch(trimmed);
      if (typedefMatch != null) {
        nodes.add(OutlineNode(
          name: typedefMatch.group(1)!,
          kind: OutlineNodeKind.typeParameter,
          line: i,
          column: line.length - trimmed.length,
        ));
        continue;
      }
    }

    return nodes;
  }
}

/// Outline 管理器
class OutlineManager {
  final List<OutlineProvider> _providers = [];

  OutlineManager() {
    _providers.add(DartOutlineProvider());
  }

  void register(OutlineProvider provider) {
    _providers.add(provider);
  }

  Future<List<OutlineNode>> getOutline({
    required String filePath,
    required String text,
    required FileLanguage language,
  }) async {
    for (final provider in _providers) {
      if (provider.supportsLanguage(language)) {
        try {
          return await provider.getOutline(
            filePath: filePath,
            text: text,
            language: language,
          );
        } catch (_) {
          return [];
        }
      }
    }
    return [];
  }
}
