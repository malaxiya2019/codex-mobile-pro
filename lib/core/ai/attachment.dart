import 'dart:convert';
import 'dart:io';

/// 附件类型
enum AttachmentType {
  /// 相册 / 拍照图片
  image,

  /// 任意文件（系统文件选择器）
  file,

  /// 项目内文件（当前工作目录允许范围内）
  projectFile;

  static AttachmentType fromName(String? name) {
    return AttachmentType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => AttachmentType.file,
    );
  }
}

/// 附件状态
enum AttachmentStatus {
  /// 已就绪（可发送）
  ready,

  /// 处理中
  loading,

  /// 校验失败（大小 / 类型等）
  error;

  static AttachmentStatus fromName(String? name) {
    return AttachmentStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => AttachmentStatus.ready,
    );
  }
}

/// 本地附件
///
/// 附件只保存在本地：不上传、不写入日志、不塞进 AI Context（本阶段）。
/// [path] / [thumbnail] 为本地绝对路径，禁止打印到日志 / 异常信息。
class Attachment {
  final String id;
  final AttachmentType type;
  final String name;
  final String mimeType;
  final int size;
  final String? path;
  final String? thumbnail;
  final AttachmentStatus status;
  final String? error;

  const Attachment({
    required this.id,
    required this.type,
    required this.name,
    this.mimeType = 'application/octet-stream',
    this.size = 0,
    this.path,
    this.thumbnail,
    this.status = AttachmentStatus.ready,
    this.error,
  });

  Attachment copyWith({
    String? id,
    AttachmentType? type,
    String? name,
    String? mimeType,
    int? size,
    String? path,
    String? thumbnail,
    AttachmentStatus? status,
    String? error,
  }) {
    return Attachment(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      path: path ?? this.path,
      thumbnail: thumbnail ?? this.thumbnail,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }

  /// 序列化（仅用于 ChatMessage.metadata 内部传递，不参与 AI 请求）。
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'mimeType': mimeType,
    'size': size,
    'path': path,
    'thumbnail': thumbnail,
    'status': status.name,
    'error': error,
  };

  static Attachment? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;
    return Attachment(
      id: id,
      type: AttachmentType.fromName(json['type'] as String?),
      name: (json['name'] as String?) ?? '附件',
      mimeType: (json['mimeType'] as String?) ?? 'application/octet-stream',
      size: json['size'] is num ? (json['size'] as num).toInt() : 0,
      path: json['path'] as String?,
      thumbnail: json['thumbnail'] as String?,
      status: AttachmentStatus.fromName(json['status'] as String?),
      error: json['error'] as String?,
    );
  }
  /// 是否为图片附件（MIME 以 `image/` 开头）。
  ///
  /// 覆盖 image/jpeg、image/png、image/webp 等常见图片格式。
  bool get isImage {
    final m = mimeType.toLowerCase();
    return m.startsWith('image/');
  }

  /// 生成 data URL（`data:<mime>;base64,<base64>`）。
  ///
  /// 仅图片可用。文件不存在 / 读取失败 / 超过 [maxBytes] 时返回 null。
  /// 这是「把图片 bytes 真正传给多模态模型」的通道；**严禁把 [path]
  /// 字符串当作图片内容发送**。当前 DeepSeek 栈不支持图片，调用方
  /// 应先用 [isImage] 拦截并提示，而不是伪造发送。
  Future<String?> toDataUrl({int maxBytes = 10 * 1024 * 1024}) async {
    if (!isImage) return null;
    final p = path;
    if (p == null || p.isEmpty) return null;
    try {
      final file = File(p);
      if (!await file.exists()) return null;
      if (size > 0 && size > maxBytes) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > maxBytes) return null;
      return 'data:$mimeType;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }
}
