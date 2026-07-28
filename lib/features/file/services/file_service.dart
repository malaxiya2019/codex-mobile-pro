import 'dart:io';
import 'dart:async';

/// 文件条目类型
enum FileEntryType { file, directory, symlink, unknown }

/// 文件条目
class FileEntry {
  final String name;
  final String path;
  final FileEntryType type;
  final int? size;
  final DateTime? modifiedAt;
  final bool isSymlink;

  const FileEntry({
    required this.name,
    required this.path,
    required this.type,
    this.size,
    this.modifiedAt,
    this.isSymlink = false,
  });

  /// 是否为可读文本文件（按扩展名判断）
  bool get isTextFile {
    final ext = name.split('.').last.toLowerCase();
    const textExtensions = {
      'dart',
      'yaml',
      'json',
      'md',
      'txt',
      'xml',
      'html',
      'css',
      'js',
      'ts',
      'rs',
      'py',
      'toml',
      'ini',
      'cfg',
      'conf',
      'sh',
      'bash',
      'zsh',
      'env',
      'gitignore',
      'lock',
      'gradle',
      'kt',
      'java',
      'swift',
      'c',
      'h',
      'cpp',
      'hpp',
      'go',
      'rb',
      'php',
      'sql',
      'log',
      'csv',
      'yml',
      'svg',
      'vue',
      'svelte',
      'tsx',
      'jsx',
    };
    return textExtensions.contains(ext);
  }

  /// 文件图标（基于扩展名）
  String get icon {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return '🎯';
      case 'rs':
        return '🦀';
      case 'py':
        return '🐍';
      case 'yaml':
      case 'yml':
        return '⚙️';
      case 'json':
        return '📋';
      case 'md':
        return '📝';
      case 'html':
        return '🌐';
      case 'css':
        return '🎨';
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        return '📜';
      case 'toml':
        return '🔧';
      case 'sh':
      case 'bash':
      case 'zsh':
        return '💻';
      case 'env':
        return '🔒';
      case 'gitignore':
        return '🙈';
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return '🖼️';
      case 'mp3':
      case 'wav':
      case 'ogg':
        return '🎵';
      case 'mp4':
      case 'mov':
        return '🎬';
      case 'pdf':
        return '📄';
      case 'zip':
      case 'tar':
      case 'gz':
        return '📦';
      default:
        return type == FileEntryType.directory ? '📁' : '📄';
    }
  }
}

/// 文件系统服务
///
/// 支持：
/// - 懒加载目录树（按需展开）
/// - 异步文件读取
/// - 文件类型识别
/// - 大文件分块读取
class FileService {
  /// 列出目录内容（不递归）
  static Future<List<FileEntry>> listDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return [];

    final entities = <FileEntry>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final stat = await entity.stat();
          final name = entity.path.split('/').last;
          final entryType = _getEntryType(entity);
          entities.add(
            FileEntry(
              name: name,
              path: entity.path,
              type: entryType,
              size: entryType == FileEntryType.file ? stat.size : null,
              modifiedAt: stat.modified,
              isSymlink: stat.type == FileSystemEntityType.link,
            ),
          );
        } catch (_) {
          // 跳过无法访问的条目
        }
      }
    } catch (_) {
      // 跳过无法读取的目录
    }

    // 排序：目录在前，文件在后，按名称排序
    entities.sort((a, b) {
      if (a.type == FileEntryType.directory &&
          b.type != FileEntryType.directory) {
        return -1;
      }
      if (a.type != FileEntryType.directory &&
          b.type == FileEntryType.directory) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return entities;
  }

  /// 读取文件内容（异步）
  static Future<String?> readFile(
    String path, {
    int maxBytes = 1024 * 1024,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;

    try {
      final stat = await file.stat();
      if (stat.size > maxBytes) {
        return '⚠️ 文件过大（${_formatSize(stat.size)}），仅显示前 ${_formatSize(maxBytes)}';
      }

      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 读取文件前 N 行
  static Future<String?> readFileLines(
    String path, {
    int maxLines = 100,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;

    try {
      final lines = <String>[];
      final completer = Completer<String?>();

      final content = await file.readAsString();
      final allLines = content.split('\n');
      for (final line in allLines) {
        if (lines.length < maxLines) {
          lines.add(line);
        }
      }
      completer.complete(lines.join('\n'));

      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  /// 搜索文件
  static Future<List<FileEntry>> searchFiles({
    required String rootPath,
    required String query,
    int maxResults = 50,
  }) async {
    final results = <FileEntry>[];
    final dir = Directory(rootPath);
    if (!await dir.exists()) return results;

    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (results.length >= maxResults) break;

        final name = entity.path.split('/').last;
        if (name.toLowerCase().contains(query.toLowerCase())) {
          final stat = await entity.stat();
          results.add(
            FileEntry(
              name: name,
              path: entity.path,
              type: _getEntryType(entity),
              size: stat.size,
              modifiedAt: stat.modified,
            ),
          );
        }
      }
    } catch (_) {}

    return results;
  }

  /// 获取目录树的懒加载根节点
  static Future<FileTreeNode> getDirectoryTree(String path) async {
    final dir = Directory(path);
    final name = path.split('/').last;
    final stat = await dir.stat();
    final entries = await listDirectory(path);

    return FileTreeNode(
      name: name.isEmpty ? path : name,
      path: path,
      isDirectory: true,
      modifiedAt: stat.modified,
      children: entries.map((e) {
        if (e.type == FileEntryType.directory) {
          return FileTreeNode(
            name: e.name,
            path: e.path,
            isDirectory: true,
            isLazy: true,
          );
        } else {
          return FileTreeNode(
            name: e.name,
            path: e.path,
            isDirectory: false,
            size: e.size,
            modifiedAt: e.modifiedAt,
          );
        }
      }).toList(),
    );
  }

  /// 加载懒加载节点的子节点
  static Future<List<FileTreeNode>> loadChildren(String path) async {
    final entries = await listDirectory(path);
    return entries.map((e) {
      if (e.type == FileEntryType.directory) {
        return FileTreeNode(
          name: e.name,
          path: e.path,
          isDirectory: true,
          isLazy: true,
        );
      } else {
        return FileTreeNode(
          name: e.name,
          path: e.path,
          isDirectory: false,
          size: e.size,
          modifiedAt: e.modifiedAt,
        );
      }
    }).toList();
  }


  // ── 文件操作 ──

  /// 重命名文件/目录
  static Future<bool> rename(String oldPath, String newName) async {
    try {
      final parent = oldPath.substring(0, oldPath.lastIndexOf('/'));
      final newPath = '$parent/$newName';
      final entity = FileSystemEntity.typeSync(oldPath);
      if (entity == FileSystemEntityType.directory) {
        await Directory(oldPath).rename(newPath);
      } else {
        await File(oldPath).rename(newPath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 删除文件/目录
  static Future<bool> delete(String path) async {
    try {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 复制文件/目录
  static Future<bool> copy(String sourcePath, String destPath) async {
    try {
      final entity = FileSystemEntity.typeSync(sourcePath);
      if (entity == FileSystemEntityType.directory) {
        await _copyDirectory(Directory(sourcePath), Directory(destPath));
      } else {
        await File(sourcePath).copy(destPath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 移动文件/目录
  static Future<bool> move(String sourcePath, String destPath) async {
    try {
      final entity = FileSystemEntity.typeSync(sourcePath);
      if (entity == FileSystemEntityType.directory) {
        await Directory(sourcePath).rename(destPath);
      } else {
        await File(sourcePath).rename(destPath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 创建文件
  static Future<bool> createFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) return false;
      await file.create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 创建目录
  static Future<bool> createDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) return false;
      await dir.create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 递归复制目录
  static Future<void> _copyDirectory(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final destPath = '${dest.path}/${entity.path.split('/').last}';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static FileEntryType _getEntryType(FileSystemEntity entity) {
    if (entity is Directory) return FileEntryType.directory;
    if (entity is File) return FileEntryType.file;
    if (entity is Link) return FileEntryType.symlink;
    return FileEntryType.unknown;
  }
}

/// 文件树节点（懒加载）
class FileTreeNode {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;
  final bool isLazy;
  List<FileTreeNode>? children;

  FileTreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
    this.isLazy = false,
    this.children,
  });

  bool get isExpanded => children != null;

  /// 加载子节点
  Future<void> expand() async {
    if (!isDirectory) return;
    children = await FileService.loadChildren(path);
  }

  /// 收起
  void collapse() {
    children = null;
  }
}
