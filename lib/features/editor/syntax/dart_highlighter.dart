import 'syntax_highlighter.dart';
import '../models/editor_models.dart';

class DartHighlighter extends BaseHighlighter {
  @override
  FileLanguage get language => FileLanguage.dart;

  @override
  Set<String> get keywords => {
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default',
    'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends',
    'extension', 'external', 'factory', 'false', 'final', 'finally',
    'for', 'Function', 'get', 'hide', 'if', 'implements', 'import',
    'in', 'interface', 'is', 'late', 'library', 'mixin', 'new',
    'null', 'on', 'operator', 'part', 'required', 'rethrow',
    'return', 'set', 'show', 'static', 'super', 'switch', 'sync',
    'this', 'throw', 'true', 'try', 'typedef', 'var', 'void',
    'while', 'with', 'yield',
  };

  @override
  Set<String> get typeKeywords => {
    'int', 'double', 'num', 'String', 'bool', 'List', 'Map',
    'Set', 'Object', 'Never', 'Null', 'Symbol', 'Record',
    'Comparable', 'Iterable', 'Future', 'Stream',
  };

  @override
  Set<String> get builtins => {
    'print', 'identityHashCode', 'identical', 'runes',
    'DateTime', 'Duration', 'Uri', 'RegExp',
  };
}
