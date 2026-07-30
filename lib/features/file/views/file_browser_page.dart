import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../providers/file_provider.dart';
import '../services/file_service.dart';

/// 文件浏览器页面
class FileBrowserPage extends ConsumerStatefulWidget {
  final String initialPath;

  const FileBrowserPage({super.key, this.initialPath = ''});

  @override
  ConsumerState<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends ConsumerState<FileBrowserPage> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialPath.isNotEmpty) {
        ref.read(fileBrowserProvider.notifier).buildTree(widget.initialPath);
      } else {
        // 默认路径
        ref
            .read(fileBrowserProvider.notifier)
            .buildTree('/storage/emulated/0');
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(fileBrowserProvider);
    final locale = ref.watch(localeProvider);
    final s = Strings.get(locale);

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '${s.search}...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                style: theme.textTheme.titleMedium,
                onChanged: (q) =>
                    ref.read(fileBrowserProvider.notifier).search(q),
              )
            : Text(s.fileBrowserTitle),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  ref.read(fileBrowserProvider.notifier).clearSearch();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(fileBrowserProvider.notifier).buildTree(state.rootPath);
            },
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showSearch
          ? _buildSearchResults(state, theme, colorScheme)
          : state.treeRoot != null
          ? _buildFileTree(state, theme, colorScheme, s)
          : const Center(child: Text('无法加载目录')),
    );
  }

  Widget _buildSearchResults(
    FileBrowserState state,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (state.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              '未找到匹配的文件',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: state.searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = state.searchResults[index];
        return ListTile(
          leading: Text(entry.icon, style: const TextStyle(fontSize: 20)),
          title: Text(entry.name),
          subtitle: Text(
            entry.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: entry.size != null
              ? Text(_formatSize(entry.size!), style: theme.textTheme.bodySmall)
              : null,
          onTap: () {
            if (entry.type == FileEntryType.directory) {
              ref.read(fileBrowserProvider.notifier).buildTree(entry.path);
              setState(() {
                _showSearch = false;
                _searchController.clear();
              });
            } else {
              _openFile(entry.path);
            }
          },
        );
      },
    );
  }

  Widget _buildFileTree(
    FileBrowserState state,
    ThemeData theme,
    ColorScheme colorScheme,
    Strings s,
  ) {
    return Column(
      children: [
        // 路径导航
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.currentPath.isNotEmpty
                      ? state.currentPath
                      : state.rootPath,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (state.currentPath.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: '上级目录',
                  onPressed: () =>
                      ref.read(fileBrowserProvider.notifier).goUp(),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),

        // 文件内容显示
        if (state.fileContent != null)
          Expanded(
            child: Column(
              children: [
                // 文件头
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                  child: Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file_outlined,
                        size: 16,
                        color: colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.filePath?.split('/').last ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () =>
                            ref.read(fileBrowserProvider.notifier).closeFile(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                // 内容
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      state.fileContent!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // 文件树
        if (state.fileContent == null)
          Expanded(
            child: state.treeRoot != null
                ? ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: _buildTreeNodes(
                      context,
                      state.treeRoot!.children ?? [],
                      0,
                      theme,
                      colorScheme,
                    ),
                  )
                : const Center(child: Text('空目录')),
          ),
      ],
    );
  }

  List<Widget> _buildTreeNodes(
    BuildContext context,
    List<FileTreeNode> nodes,
    int depth,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final widgets = <Widget>[];

    for (final node in nodes) {
      widgets.add(
        _FileTreeNodeWidget(
          node: node,
          depth: depth,
          onTap: () {
            if (node.isDirectory) {
              if (node.isExpanded) {
                ref.read(fileBrowserProvider.notifier).collapseNode(node);
              } else {
                ref.read(fileBrowserProvider.notifier).expandNode(node);
              }
            } else {
              _openFile(node.path);
            }
          },
        ),
      );

      // 递归渲染已展开的子节点
      if (node.isExpanded && node.children != null) {
        widgets.addAll(
          _buildTreeNodes(
            context,
            node.children!,
            depth + 1,
            theme,
            colorScheme,
          ),
        );
      }
    }

    return widgets;
  }

  void _openFile(String path) {
    ref.read(fileBrowserProvider.notifier).openFile(path);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 文件树节点 Widget
class _FileTreeNodeWidget extends StatelessWidget {
  final FileTreeNode node;
  final int depth;
  final VoidCallback onTap;

  const _FileTreeNodeWidget({
    required this.node,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final icon = node.isDirectory
        ? (node.isExpanded ? Icons.folder_open : Icons.folder)
        : _getFileIcon(node.name);
    final iconColor = node.isDirectory
        ? Colors.amber.shade600
        : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 16.0 * depth + 8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: node.isDirectory ? FontWeight.w500 : null,
                    fontFamily: node.isDirectory ? null : 'monospace',
                    fontSize: node.isDirectory ? 14 : 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (node.size != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    _formatSize(node.size!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return Icons.code;
      case 'yaml':
      case 'yml':
        return Icons.settings;
      case 'json':
        return Icons.data_object;
      case 'md':
        return Icons.article;
      case 'html':
        return Icons.web;
      case 'css':
        return Icons.style;
      case 'js':
      case 'ts':
        return Icons.javascript;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return Icons.image;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      case 'sh':
      case 'bash':
        return Icons.terminal;
      case 'py':
        return Icons.code;
      case 'rs':
        return Icons.code;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
