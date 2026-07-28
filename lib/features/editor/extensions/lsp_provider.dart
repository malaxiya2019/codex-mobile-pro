import '../models/editor_models.dart';
import 'completion_provider.dart';
import 'diagnostics_provider.dart';

/// LSP 能力标记
enum LspCapability {
  completion,
  diagnostics,
  hover,
  gotoDefinition,
  findReferences,
  codeAction,
  rename,
  formatting,
  signatureHelp,
  documentSymbols,
}

/// LSP 提供者接口（预留）
///
/// 预留 Language Server Protocol 集成接口。
/// 未来可对接 lsp-server、Dart Analysis Server 等。
abstract class LspProvider {
  String get name;

  /// 支持的语言
  Set<FileLanguage> get supportedLanguages;

  /// 支持的能力
  Set<LspCapability> get capabilities;

  /// 初始化 LSP 服务器
  Future<bool> initialize(String workspacePath);

  /// 关闭 LSP 服务器
  Future<void> shutdown();

  /// 获取补全
  Future<List<CompletionItem>> getCompletions({
    required String filePath,
    required String text,
    required int offset,
    required int line,
    required int column,
  });

  /// 获取诊断
  Future<List<Diagnostic>> getDiagnostics({
    required String filePath,
    required String text,
  });

  /// 跳转到定义
  Future<CursorPosition?> gotoDefinition({
    required String filePath,
    required int line,
    required int column,
  });

  /// 查找引用
  Future<List<CursorPosition>> findReferences({
    required String filePath,
    required int line,
    required int column,
  });

  /// 获取 Hover 信息
  Future<String?> getHover({
    required String filePath,
    required int line,
    required int column,
  });

  /// 代码动作
  Future<List<CodeAction>> getCodeActions({
    required String filePath,
    required String text,
    required int line,
    required int column,
  });

  /// 重命名符号
  Future<String?> renameSymbol({
    required String filePath,
    required String text,
    required int line,
    required int column,
    required String newName,
  });

  /// 格式化文档
  Future<String?> formatDocument({
    required String filePath,
    required String text,
  });
}

/// 代码动作
class CodeAction {
  final String title;
  final String kind; // 'quickfix', 'refactor', 'source'
  final String? edit; // 编辑内容

  const CodeAction({
    required this.title,
    this.kind = 'quickfix',
    this.edit,
  });
}

/// LSP 管理器
class LspManager {
  final List<LspProvider> _providers = [];

  void register(LspProvider provider) {
    _providers.add(provider);
  }

  LspProvider? getProvider(FileLanguage language) {
    for (final provider in _providers) {
      if (provider.supportedLanguages.contains(language)) {
        return provider;
      }
    }
    return null;
  }
}
