import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 日志文件写入器
///
/// 提供：
/// - 自动创建日志目录
/// - 日志轮转（按文件大小）
/// - 最大保留文件数
/// - 高频写入缓冲（防抖动）
class LogFileWriter {
  final String _baseDir;
  final String _fileName;
  final int _maxFileSize;    /// 单文件最大字节
  final int _maxFiles;       /// 最大保留文件数
  final Duration _flushInterval;

  File? _currentFile;
  int _currentSize = 0;
  final List<String> _buffer = [];
  Timer? _flushTimer;
  bool _disposed = false;

  LogFileWriter({
    required String baseDir,
    String fileName = 'app.log',
    int maxFileSize = 1 * 1024 * 1024,  // 默认 1MB
    int maxFiles = 5,
    Duration? flushInterval,
  }) : _baseDir = baseDir,
       _fileName = fileName,
       _maxFileSize = maxFileSize,
       _maxFiles = maxFiles,
       _flushInterval = flushInterval ?? const Duration(seconds: 5);

  /// 初始化日志目录
  Future<void> init() async {
    final dir = Directory(_baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _openCurrentFile();
  }

  /// 打开当前日志文件
  Future<void> _openCurrentFile() async {
    final file = File('$_baseDir/$_fileName');
    if (await file.exists()) {
      _currentSize = await file.length();
    } else {
      await file.create();
      _currentSize = 0;
    }
    _currentFile = file;
  }

  /// 写入日志行
  Future<void> write(String line) async {
    if (_disposed) return;

    _buffer.add(line);

    // 如果没有定时器，启动一个
    _flushTimer ??= Timer(_flushInterval, () => _flush());

    // 如果缓冲区过大，立即刷入
    if (_buffer.length >= 100) {
      await _flush();
    }
  }

  bool _flushing = false;

  /// 立即刷入缓冲区
  Future<void> flush() async {
    if (_disposed || _flushing) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    _flushTimer = null;
    try {
      if (_buffer.isEmpty) return;

      final lines = List<String>.from(_buffer);
      _buffer.clear();

      // 写入文件；异常向上传播以便调用方知晓
      await _writeLines(lines);
    } finally {
      _flushing = false;
    }
  }

  Future<void> _writeLines(List<String> lines) async {
    if (_currentFile == null) {
      // 如果文件未初始化，尝试重新打开
      await _openCurrentFile();
      if (_currentFile == null) return;
    }

    final content = '${lines.join('\n')}\n';
    final bytes = utf8.encode(content);

    // 检查是否需要轮转
    if (_currentSize + bytes.length > _maxFileSize) {
      await _rotate();
    }

    // 轮转后确保文件可写（_openCurrentFile 可能失败）
    if (_currentFile == null) {
      await _openCurrentFile();
      if (_currentFile == null) return;
    }

    await _currentFile!.writeAsBytes(bytes, mode: FileMode.append);
    _currentSize += bytes.length;
  }

  /// 日志轮转
  Future<void> _rotate() async {
    if (_currentFile == null) return;

    // 删除最旧的日志
    final oldestFile = File('$_baseDir/$_fileName.${_maxFiles - 1}');
    if (await oldestFile.exists()) {
      await oldestFile.delete();
    }

    // 依次重命名：.4 → .5, .3 → .4, ... , .log → .1
    for (int i = _maxFiles - 1; i >= 1; i--) {
      final src = File('$_baseDir/$_fileName.${i - 1}');
      if (await src.exists()) {
        await src.rename('$_baseDir/$_fileName.$i');
      }
    }

    // 重命名当前文件
    try {
      await _currentFile!.rename('$_baseDir/$_fileName.0');
    } catch (_) {
      // 如果重命名失败（例如权限问题），继续创建新文件
    }
    await _openCurrentFile();
  }

  /// 获取今日日志总大小
  Future<int> totalSize() async {
    int total = 0;
    for (int i = 0; i < _maxFiles; i++) {
      final file = File(i == 0 ? '$_baseDir/$_fileName' : '$_baseDir/$_fileName.$i');
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  /// 读取最近的日志
  Future<String> readRecent({int maxLines = 100}) async {
    if (_currentFile == null || !await _currentFile!.exists()) return '';
    final lines = await _currentFile!.readAsLines();
    final recent = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;
    return recent.join('\n');
  }

  /// 清理所有日志
  Future<void> clearAll() async {
    for (int i = 0; i < _maxFiles; i++) {
      final file = File(i == 0 ? '$_baseDir/$_fileName' : '$_baseDir/$_fileName.$i');
      if (await file.exists()) {
        await file.delete();
      }
    }
    _currentSize = 0;
    await _openCurrentFile();
  }

  /// 释放资源
  Future<void> dispose() async {
    _disposed = true;
    _flushTimer?.cancel();
    await flush();
    _currentFile = null;
  }
}
