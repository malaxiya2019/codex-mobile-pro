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
}
