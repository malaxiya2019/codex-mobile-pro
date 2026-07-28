import '../models/editor_models.dart';

/// 诊断严重级别
enum DiagnosticSeverity {
  error,
  warning,
  info,
  hint,
}

/// 诊断信息
class Diagnostic {
  final String message;
  final DiagnosticSeverity severity;
  final int line;
  final int column;
  final int length;
  final String? code;
  final String? source;

  const Diagnostic({
    required this.message,
    required this.severity,
    required this.line,
    required this.column,
    this.length = 0,
    this.code,
    this.source,
  });
}

/// 诊断提供者接口
///
/// 为编辑器提供代码诊断信息（错误、警告、提示）。
/// 可扩展：实现此接口以添加自定义诊断源。
abstract class DiagnosticsProvider {
  String get name;

  /// 获取文件的诊断信息
  Future<List<Diagnostic>> getDiagnostics({
    required String filePath,
    required String text,
    required FileLanguage language,
  });

  /// 是否应为此语言激活
  bool supportsLanguage(FileLanguage language);
}

/// 诊断管理器
class DiagnosticsManager {
  final List<DiagnosticsProvider> _providers = [];
  List<Diagnostic> _cachedDiagnostics = [];
  String? _cachedFilePath;

  void register(DiagnosticsProvider provider) {
    _providers.add(provider);
  }

  /// 获取文件的诊断信息
  Future<List<Diagnostic>> getDiagnostics({
    required String filePath,
    required String text,
    required FileLanguage language,
  }) async {
    // 如果文件未变，返回缓存
    if (_cachedFilePath == filePath && _cachedDiagnostics.isNotEmpty) {
      return _cachedDiagnostics;
    }

    final results = <Diagnostic>[];
    for (final provider in _providers) {
      if (provider.supportsLanguage(language)) {
        try {
          final diags = await provider.getDiagnostics(
            filePath: filePath,
            text: text,
            language: language,
          );
          results.addAll(diags);
        } catch (_) {}
      }
    }

    _cachedFilePath = filePath;
    _cachedDiagnostics = results;
    return results;
  }

  void clearCache() {
    _cachedFilePath = null;
    _cachedDiagnostics = [];
  }
}
