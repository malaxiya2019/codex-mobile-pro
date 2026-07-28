import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/file_service.dart';

/// 文件浏览状态
class FileBrowserState {
  final String rootPath;
  final String currentPath;
  final List<FileEntry> currentEntries;
  final FileTreeNode? treeRoot;
  final String? fileContent;
  final String? filePath;
  final bool isLoading;
  final bool isSearching;
  final String searchQuery;
  final List<FileEntry> searchResults;

  const FileBrowserState({
    this.rootPath = '',
    this.currentPath = '',
    this.currentEntries = const [],
    this.treeRoot,
    this.fileContent,
    this.filePath,
    this.isLoading = false,
    this.isSearching = false,
    this.searchQuery = '',
    this.searchResults = const [],
  });

  FileBrowserState copyWith({
    String? rootPath,
    String? currentPath,
    List<FileEntry>? currentEntries,
    FileTreeNode? treeRoot,
    String? fileContent,
    String? filePath,
    bool? isLoading,
    bool? isSearching,
    String? searchQuery,
    List<FileEntry>? searchResults,
    bool clearFile = false,
    bool clearTree = false,
    bool clearSearch = false,
  }) {
    return FileBrowserState(
      rootPath: rootPath ?? this.rootPath,
      currentPath: currentPath ?? this.currentPath,
      currentEntries: currentEntries ?? this.currentEntries,
      treeRoot: clearTree ? null : (treeRoot ?? this.treeRoot),
      fileContent: clearFile ? null : (fileContent ?? this.fileContent),
      filePath: clearFile ? null : (filePath ?? this.filePath),
      isLoading: isLoading ?? this.isLoading,
      isSearching: isSearching ?? this.isSearching,
      searchQuery: clearSearch ? '' : (searchQuery ?? this.searchQuery),
      searchResults: clearSearch
          ? const []
          : (searchResults ?? this.searchResults),
    );
  }
}

/// 文件浏览 Provider
final fileBrowserProvider =
    StateNotifierProvider<FileBrowserNotifier, FileBrowserState>((ref) {
      return FileBrowserNotifier();
    });

class FileBrowserNotifier extends StateNotifier<FileBrowserState> {
  FileBrowserNotifier() : super(const FileBrowserState());

  /// 打开目录
  Future<void> openDirectory(String path) async {
    state = state.copyWith(isLoading: true);
    final entries = await FileService.listDirectory(path);
    state = state.copyWith(
      currentPath: path,
      rootPath: state.rootPath.isEmpty ? path : state.rootPath,
      currentEntries: entries,
      isLoading: false,
    );
  }

  /// 构建文件树
  Future<void> buildTree(String rootPath) async {
    state = state.copyWith(isLoading: true);
    final root = await FileService.getDirectoryTree(rootPath);
    state = state.copyWith(
      rootPath: rootPath,
      currentPath: rootPath,
      treeRoot: root,
      isLoading: false,
    );
  }

  /// 展开树节点
  Future<void> expandNode(FileTreeNode node) async {
    if (node.isExpanded) return;
    await node.expand();
    // 触发 UI 刷新
    state = state.copyWith();
  }

  /// 收起树节点
  void collapseNode(FileTreeNode node) {
    node.collapse();
    state = state.copyWith();
  }

  /// 打开文件
  Future<void> openFile(String path) async {
    state = state.copyWith(isLoading: true, filePath: path);
    final content = await FileService.readFile(path);
    state = state.copyWith(fileContent: content, isLoading: false);
  }

  /// 读取文件前 N 行
  Future<void> openFilePreview(String path, {int maxLines = 50}) async {
    state = state.copyWith(isLoading: true, filePath: path);
    final content = await FileService.readFileLines(path, maxLines: maxLines);
    state = state.copyWith(fileContent: content, isLoading: false);
  }

  /// 关闭文件
  void closeFile() {
    state = state.copyWith(clearFile: true);
  }

  /// 搜索文件
  Future<void> search(String query) async {
    if (query.isEmpty) {
      state = state.copyWith(clearSearch: true);
      return;
    }

    state = state.copyWith(isSearching: true, searchQuery: query);
    final results = await FileService.searchFiles(
      rootPath: state.rootPath,
      query: query,
    );
    state = state.copyWith(searchResults: results, isSearching: false);
  }

  /// 清除搜索
  void clearSearch() {
    state = state.copyWith(clearSearch: true);
  }

  /// 进入子目录
  Future<void> enterDirectory(String path) async {
    await openDirectory(path);
  }

  /// 返回上级目录
  Future<void> goUp() async {
    final current = state.currentPath;
    if (current.isEmpty) return;

    final parent = current.substring(0, current.lastIndexOf('/'));
    if (parent.isNotEmpty && parent != current) {
      await openDirectory(parent);
    }
  }

  /// 切换到指定路径
  Future<void> navigateTo(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await openDirectory(path);
    }
  }
}
