import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 搜索结果条目
class SearchResultItem {
  final String filePath;
  final String fileName;
  final int line;
  final int column;
  final String lineContent;
  final int matchLength;
  final List<int> matchPositions;

  const SearchResultItem({
    required this.filePath,
    required this.fileName,
    required this.line,
    required this.column,
    required this.lineContent,
    this.matchLength = 0,
    this.matchPositions = const [],
  });
}

/// 搜索状态
enum SearchState {
  idle,
  searching,
  done,
  cancelled,
  error,
}

/// 搜索配置
class SearchConfig {
  final String query;
  final bool caseSensitive;
  final bool wholeWord;
  final bool useRegex;
  final bool searchFileNames;
  final bool searchContent;
  final int maxResults;
  final int maxFileSize;

  const SearchConfig({
    required this.query,
    this.caseSensitive = false,
    this.wholeWord = false,
    this.useRegex = false,
    this.searchFileNames = true,
    this.searchContent = true,
    this.maxResults = 500,
    this.maxFileSize = 1024 * 1024,
  });
}

/// 替换结果
class ReplaceResult {
  final String filePath;
  final int replacementsCount;

  const ReplaceResult({
    required this.filePath,
    required this.replacementsCount,
  });
}

/// 工作区搜索 Provider
final workspaceSearchProvider =
    StateNotifierProvider<WorkspaceSearchNotifier, WorkspaceSearchState>(
  (ref) => WorkspaceSearchNotifier(),
);

/// 搜索状态
class WorkspaceSearchState {
  final SearchState state;
  final String query;
  final List<SearchResultItem> results;
  final int totalFiles;
  final int totalMatches;
  final String? errorMessage;
  final List<String> searchPaths;

  const WorkspaceSearchState({
    this.state = SearchState.idle,
    this.query = '',
    this.results = const [],
    this.totalFiles = 0,
    this.totalMatches = 0,
    this.errorMessage,
    this.searchPaths = const [],
  });

  WorkspaceSearchState copyWith({
    SearchState? state,
    String? query,
    List<SearchResultItem>? results,
    int? totalFiles,
    int? totalMatches,
    String? errorMessage,
    List<String>? searchPaths,
  }) {
    return WorkspaceSearchState(
      state: state ?? this.state,
      query: query ?? this.query,
      results: results ?? this.results,
      totalFiles: totalFiles ?? this.totalFiles,
      totalMatches: totalMatches ?? this.totalMatches,
      errorMessage: errorMessage ?? this.errorMessage,
      searchPaths: searchPaths ?? this.searchPaths,
    );
  }

  bool get isSearching => state == SearchState.searching;
  bool get hasResults => results.isNotEmpty;
  bool get isDone => state == SearchState.done;
}

class WorkspaceSearchNotifier extends StateNotifier<WorkspaceSearchState> {
  CancelToken? _cancelToken;

  static final Set<String> _binaryExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.svg',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.zip', '.tar', '.gz', '.rar', '.7z',
    '.mp3', '.mp4', '.wav', '.avi', '.mov', '.flv',
    '.exe', '.dll', '.so', '.dylib', '.class',
    '.ttf', '.otf', '.woff', '.woff2', '.eot',
    '.o', '.a', '.lib', '.obj',
    '.pyc', '.pyo',
    '.DS_Store', '.gitkeep',
  };

  static final Set<String> _ignoredDirs = {
    '.git', '.svn', '.hg', '.gradle', '.idea', '.vscode',
    'node_modules', '.dart_tool', '.pub-cache', 'build',
    'dist', 'target', 'vendor', '.cache', '__pycache__',
    '.next', '.nuxt', 'coverage', '.flutter-plugins',
  };

  WorkspaceSearchNotifier() : super(const WorkspaceSearchState());

  /// 在工作区路径中搜索
  Future<void> search({
    required List<String> paths,
    required SearchConfig config,
  }) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    state = state.copyWith(
      state: SearchState.searching,
      query: config.query,
      searchPaths: paths,
      results: [],
      totalFiles: 0,
      totalMatches: 0,
      errorMessage: null,
    );

    if (config.query.isEmpty) {
      state = state.copyWith(state: SearchState.done);
      return;
    }

    final results = <SearchResultItem>[];
    int totalFiles = 0;
    int totalMatches = 0;

    try {
      RegExp? regex;
      if (config.useRegex) {
        regex = RegExp(
          config.query,
          caseSensitive: config.caseSensitive,
          multiLine: false,
        );
      }

      for (final path in paths) {
        final dir = Directory(path);
        if (!await dir.exists()) continue;

        await for (final entity in _walkDirectory(dir)) {
          if (_cancelToken?.isCancelled == true) {
            state = state.copyWith(state: SearchState.cancelled);
            return;
          }

          final filePath = entity.path;
          final fileName = entity.path.split('/').last;
          final ext = fileName.contains('.')
              ? '.${fileName.split('.').last}'
              : '';

          if (_binaryExtensions.contains(ext.toLowerCase())) continue;

          totalFiles++;

          if (config.searchFileNames) {
            bool matches = false;
            if (config.useRegex) {
              matches = regex?.hasMatch(fileName) ?? false;
            } else if (config.wholeWord) {
              final sn = config.caseSensitive ? fileName : fileName.toLowerCase();
              final sq = config.caseSensitive ? config.query : config.query.toLowerCase();
              matches = RegExp('\\b${RegExp.escape(sq)}\\b').hasMatch(sn);
            } else {
              final sn = config.caseSensitive ? fileName : fileName.toLowerCase();
              final sq = config.caseSensitive ? config.query : config.query.toLowerCase();
              matches = sn.contains(sq);
            }

            if (matches) {
              results.add(SearchResultItem(
                filePath: filePath, fileName: fileName,
                line: 0, column: 0, lineContent: fileName,
                matchLength: config.query.length,
              ));
              totalMatches++;
            }
          }

          if (config.searchContent && entity is File) {
            try {
              final stat = await entity.stat();
              if (stat.size > config.maxFileSize) continue;

              final lines = await entity.readAsLines();
              for (int i = 0; i < lines.length; i++) {
                if (_cancelToken?.isCancelled == true) return;
                final line = lines[i];

                if (config.useRegex) {
                  final matches = regex?.allMatches(line) ?? [];
                  if (matches.isNotEmpty) {
                    results.add(SearchResultItem(
                      filePath: filePath, fileName: fileName,
                      line: i, column: matches.first.start,
                      lineContent: line,
                      matchLength: matches.first.group(0)?.length ?? 0,
                      matchPositions: matches.map((m) => m.start).toList(),
                    ));
                    totalMatches++;
                  }
                } else if (config.wholeWord) {
                  final sl = config.caseSensitive ? line : line.toLowerCase();
                  final sq = config.caseSensitive ? config.query : config.query.toLowerCase();
                  final m = RegExp('\\b${RegExp.escape(sq)}\\b').allMatches(sl);
                  if (m.isNotEmpty) {
                    results.add(SearchResultItem(
                      filePath: filePath, fileName: fileName,
                      line: i, column: m.first.start,
                      lineContent: line,
                      matchLength: m.first.group(0)?.length ?? 0,
                      matchPositions: m.map((e) => e.start).toList(),
                    ));
                    totalMatches++;
                  }
                } else {
                  final sl = config.caseSensitive ? line : line.toLowerCase();
                  final sq = config.caseSensitive ? config.query : config.query.toLowerCase();
                  int idx = 0;
                  final positions = <int>[];
                  while (true) {
                    final f = sl.indexOf(sq, idx);
                    if (f == -1) break;
                    positions.add(f);
                    idx = f + 1;
                  }
                  if (positions.isNotEmpty) {
                    results.add(SearchResultItem(
                      filePath: filePath, fileName: fileName,
                      line: i, column: positions.first,
                      lineContent: line,
                      matchLength: config.query.length,
                      matchPositions: positions,
                    ));
                    totalMatches++;
                  }
                }

                if (results.length >= config.maxResults) {
                  state = state.copyWith(
                    state: SearchState.done, results: results,
                    totalFiles: totalFiles, totalMatches: totalMatches,
                  );
                  return;
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      state = state.copyWith(
        state: SearchState.error,
        errorMessage: '搜索失败: $e',
      );
      return;
    }

    state = state.copyWith(
      state: SearchState.done, results: results,
      totalFiles: totalFiles, totalMatches: totalMatches,
    );
  }

  /// 替换所有匹配
  Future<List<ReplaceResult>> replaceAll({
    required String searchQuery, required String replaceText,
    bool caseSensitive = false, bool wholeWord = false, bool useRegex = false,
  }) async {
    final replaceResults = <ReplaceResult>[];
    for (final result in state.results) {
      try {
        final file = File(result.filePath);
        final content = await file.readAsString();
        String newContent;

        if (useRegex) {
          newContent = content.replaceAll(
            RegExp(searchQuery, caseSensitive: caseSensitive),
            replaceText,
          );
        } else if (wholeWord) {
          newContent = content.replaceAll(
            RegExp('\\b${RegExp.escape(searchQuery)}\\b', caseSensitive: caseSensitive),
            replaceText,
          );
        } else {
          newContent = caseSensitive
              ? content.replaceAll(searchQuery, replaceText)
              : content.replaceAll(
                  RegExp(RegExp.escape(searchQuery), caseSensitive: false),
                  replaceText,
                );
        }

        if (newContent != content) {
          await file.writeAsString(newContent);
          replaceResults.add(ReplaceResult(
            filePath: result.filePath,
            replacementsCount: 1,
          ));
        }
      } catch (_) {}
    }
    return replaceResults;
  }

  /// 取消搜索
  void cancel() {
    _cancelToken?.cancel();
    state = state.copyWith(state: SearchState.idle);
  }

  /// 重置
  void reset() {
    _cancelToken?.cancel();
    state = const WorkspaceSearchState();
  }

  Stream<FileSystemEntity> _walkDirectory(Directory dir) async* {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (_cancelToken?.isCancelled == true) return;
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          if (_ignoredDirs.contains(name)) continue;
          yield* _walkDirectory(entity);
        } else if (entity is File) {
          yield entity;
        }
      }
    } catch (_) {}
  }
}

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() { _cancelled = true; }
  void reset() { _cancelled = false; }
}
