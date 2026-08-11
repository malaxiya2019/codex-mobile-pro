import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/ai/attachment.dart';

/// 附件管理：选择 / 校验 / 去重 / 删除 / 路径穿越防护。
///
/// 只负责本地附件生命周期：不上传、不写日志内容、不输出完整本地敏感路径、
/// 不塞进 AI Context（本阶段）。平台选择器可注入，便于测试。
class AttachmentManager extends ChangeNotifier {
  /// 单张图片大小上限（10 MB）
  static const int maxImageSizeBytes = 10 * 1024 * 1024;

  /// 单个文件大小上限（25 MB）
  static const int maxFileSizeBytes = 25 * 1024 * 1024;

  /// 单条消息最大附件数
  static const int maxAttachments = 9;

  AttachmentManager({ImagePicker? imagePicker, FilePicker? filePicker})
      : _imagePicker = imagePicker ?? ImagePicker(),
        _filePicker = filePicker ?? FilePicker.platform;

  final ImagePicker _imagePicker;
  final FilePicker _filePicker;

  final List<Attachment> _attachments = [];
  int _seq = 0;

  /// 当前待发送附件（只读）
  List<Attachment> get attachments => List.unmodifiable(_attachments);

  bool get isFull => _attachments.length >= maxAttachments;

  String _newId() => 'att-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// 相册选择图片（多张，用户取消返回空）
  Future<List<Attachment>> pickImagesFromGallery() async {
    final picked = await _safe(() => _imagePicker.pickMultiImage(
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 90,
        ));
    if (picked == null) return const [];
    final out = <Attachment>[];
    for (final x in picked) {
      final a = await _addImageFile(x.path);
      if (a != null) out.add(a);
    }
    return out;
  }

  /// 拍照
  Future<Attachment?> pickImageFromCamera() async {
    final picked = await _safe(() => _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 90,
        ));
    if (picked == null) return null; // 用户取消
    return _addImageFile(picked.path);
  }

  /// 选择任意文件（单文件，用户取消返回 null）
  Future<Attachment?> pickFile() async {
    final result = await _safe(() => _filePicker.pickFiles());
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return null;
    return _addFile(File(path), AttachmentType.file);
  }

  /// 添加项目内文件（必须位于 [root] 范围内，防 ../ 穿越）
  Future<List<Attachment>> addProjectFiles(
    List<String> paths, {
    required String root,
  }) async {
    final out = <Attachment>[];
    for (final path in paths) {
      if (!AttachmentManager.isWithinRoot(path, root)) continue; // 穿越拒绝
      final a = await _addFile(File(path), AttachmentType.projectFile);
      if (a != null) out.add(a);
    }
    return out;
  }

  /// 删除附件
  void remove(String id) {
    _attachments.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  /// 清空待发送附件
  void clear() {
    _attachments.clear();
    notifyListeners();
  }

  // ── 内部 ─────────────────────────────────────────────────

  Future<Attachment?> _addImageFile(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final size = await file.length();
    if (size <= 0 || size > maxImageSizeBytes) {
      return _error('图片大小超出限制');
    }
    return _add(
      Attachment(
        id: _newId(),
        type: AttachmentType.image,
        name: p.basename(path),
        mimeType: _mimeOf(p.basename(path)),
        size: size,
        path: path,
        thumbnail: path,
      ),
    );
  }

  Future<Attachment?> _addFile(File file, AttachmentType type) async {
    if (!await file.exists()) return null; // 文件不存在
    final size = await file.length();
    if (size <= 0 || size > maxFileSizeBytes) {
      return _error('文件大小超出限制');
    }
    final name = p.basename(file.path);
    return _add(
      Attachment(
        id: _newId(),
        type: type,
        name: name,
        mimeType: _mimeOf(name),
        size: size,
        path: file.path,
      ),
    );
  }

  /// 去重：同类型同名同大小视为重复附件
  Attachment? _add(Attachment a) {
    final dup = _attachments.any(
      (e) => e.type == a.type && e.name == a.name && e.size == a.size,
    );
    if (dup) return null;
    if (isFull) return null;
    _attachments.add(a);
    notifyListeners();
    return a;
  }

  Attachment? _error(String msg) {
    final a = Attachment(
      id: _newId(),
      type: AttachmentType.file,
      name: '校验失败',
      status: AttachmentStatus.error,
      error: msg,
    );
    _attachments.add(a);
    notifyListeners();
    return a;
  }

  /// 平台异常（权限拒绝 / 不可用）与取消统一吞掉，不崩溃。
  Future<T?> _safe<T>(Future<T?> Function() fn) async {
    try {
      return await fn();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── 静态工具（可独立测试） ─────────────────────────────

  /// MIME 粗推断（仅供 UI 展示；不用于安全边界）
  static String _mimeOf(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.md':
        return 'text/markdown';
      case '.json':
        return 'application/json';
      case '.yaml':
      case '.yml':
        return 'application/yaml';
      case '.txt':
      case '.log':
        return 'text/plain';
      case '.dart':
        return 'application/dart';
      case '.py':
        return 'text/x-python';
      case '.js':
        return 'text/javascript';
      case '.ts':
        return 'text/typescript';
      case '.rs':
        return 'text/rust';
      default:
        return 'application/octet-stream';
    }
  }

  /// 路径是否位于 [root] 范围内（防 ../ 穿越、防绝对路径逃逸）。
  ///
  /// 使用 package:path 的 isWithin：规范化后校验前缀，天然拒绝 `..` 逃逸。
  static bool isWithinRoot(String path, String root) {
    if (path.isEmpty || root.isEmpty) return false;
    final normRoot = p.normalize(p.absolute(root));
    final normPath = p.normalize(p.absolute(path));
    return p.isWithin(normRoot, normPath);
  }

  /// 人类可读文件大小
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
