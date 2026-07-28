import 'syntax_highlighter.dart';
import '../models/editor_models.dart';

class RustHighlighter extends BaseHighlighter {
  @override
  FileLanguage get language => FileLanguage.rust;

  @override
  Set<String> get keywords => {
    'as', 'async', 'await', 'break', 'const', 'continue', 'crate',
    'dyn', 'else', 'enum', 'extern', 'false', 'fn', 'for', 'if',
    'impl', 'in', 'let', 'loop', 'match', 'mod', 'move', 'mut',
    'pub', 'ref', 'return', 'self', 'Self', 'static', 'struct',
    'super', 'trait', 'true', 'type', 'union', 'unsafe', 'use',
    'where', 'while', 'abstract', 'become', 'box', 'do', 'final',
    'macro', 'override', 'priv', 'try', 'typeof', 'unsized',
    'virtual', 'yield',
  };

  @override
  Set<String> get typeKeywords => {
    'i8', 'i16', 'i32', 'i64', 'i128', 'isize',
    'u8', 'u16', 'u32', 'u64', 'u128', 'usize',
    'f32', 'f64', 'bool', 'char', 'str', 'String',
    'Vec', 'Option', 'Result', 'Box', 'Rc', 'Arc',
    'HashMap', 'HashSet', 'BTreeMap', 'BTreeSet',
    'Iterator', 'IntoIterator', 'Clone', 'Copy',
    'Debug', 'Display', 'Eq', 'PartialEq', 'Ord', 'PartialOrd',
  };

  @override
  Set<String> get builtins => {
    'Some', 'None', 'Ok', 'Err', 'println', 'eprintln',
    'format', 'vec', 'panic', 'assert', 'assert_eq',
    'assert_ne', 'unreachable', 'unimplemented', 'todo',
    'dbg', 'include_str', 'include_bytes', 'stringify',
    'compile_error', 'env', 'cfg',
  };

  @override
  String get commentPrefix => '//';

  @override
  bool get supportsMultiLineComment => true;

  @override
  String get multiLineCommentStart => '/*';

  @override
  String get multiLineCommentEnd => '*/';
}
