import 'package:codex_mobile_pro/core/ai/ai_message.dart';
import 'package:codex_mobile_pro/core/ai/attachment.dart';
import 'package:codex_mobile_pro/features/ai/services/attachment_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Attachment 模型', () {
    test('toJson / fromJson 往返一致', () {
      const a = Attachment(
        id: 'att-1',
        type: AttachmentType.image,
        name: 'screenshot.png',
        mimeType: 'image/png',
        size: 204800,
        path: '/data/local/tmp/screenshot.png',
        thumbnail: '/data/local/tmp/screenshot.png',
      );
      final json = a.toJson();
      final restored = Attachment.fromJson(json.cast<String, dynamic>());
      expect(restored, isNotNull);
      expect(restored!.id, 'att-1');
      expect(restored.type, AttachmentType.image);
      expect(restored.name, 'screenshot.png');
      expect(restored.mimeType, 'image/png');
      expect(restored.size, 204800);
      expect(restored.path, '/data/local/tmp/screenshot.png');
    });

    test('fromJson 容错（缺 id / 未知类型 / 非法字段不崩溃）', () {
      expect(Attachment.fromJson(<String, dynamic>{}), isNull);
      final restored = Attachment.fromJson(<String, dynamic>{
        'id': 'att-x',
        'type': 'unknown',
        'name': 'a.txt',
        'size': 'abc', // 非法数字
      });
      expect(restored, isNotNull);
      expect(restored!.type, AttachmentType.file); // 兜底 file
      expect(restored.size, 0);
    });

    test('ChatMessage 持有 attachments，且不参与 API 序列化', () {
      const att = Attachment(
        id: 'att-2',
        type: AttachmentType.projectFile,
        name: 'pubspec.yaml',
        size: 4096,
        path: '/proj/pubspec.yaml',
      );
      final msg = ChatMessage(
        id: 'm1',
        role: ChatRole.user,
        content: '看看这个文件',
        timestamp: DateTime(2026, 8, 11),
        attachments: const [att],
      );

      expect(msg.attachments, hasLength(1));
      expect(msg.attachments.single.name, 'pubspec.yaml');

      // API 序列化不包含附件（本阶段不塞 AI Context）
      final api = msg.toApiMap();
      expect(api['content'], '看看这个文件');
      expect(api.containsKey('attachments'), isFalse);
      expect(api.containsKey('metadata'), isFalse);

      // copyWith 保留/替换附件
      final copied = msg.copyWith(content: '改一下');
      expect(copied.attachments, hasLength(1));
      final cleared = msg.copyWith(attachments: const []);
      expect(cleared.attachments, isEmpty);
    });
  });

  group('AttachmentManager 安全边界（纯逻辑，不触碰平台通道）', () {
    test('路径穿越被拒绝，范围内文件允许', () {
      const root = '/data/user/0/app/files/git/codex-mobile-pro';
      expect(
        AttachmentManager.isWithinRoot(
          '/data/user/0/app/files/git/codex-mobile-pro/lib/main.dart',
          root,
        ),
        isTrue,
      );
      expect(
        AttachmentManager.isWithinRoot(
          '/data/user/0/app/files/git/codex-mobile-pro/sub/a.dart',
          root,
        ),
        isTrue,
      );
      // .. 穿越到根之外 → 拒绝
      expect(
        AttachmentManager.isWithinRoot(
          '/data/user/0/app/files/git/codex-mobile-pro/../secret.key',
          root,
        ),
        isFalse,
      );
      // 根之外的绝对路径 → 拒绝
      expect(
        AttachmentManager.isWithinRoot('/data/user/0/other/b.txt', root),
        isFalse,
      );
      // 前缀相似但不属于根（/a 与 /ab 边界）→ 拒绝
      expect(
        AttachmentManager.isWithinRoot(
          '/data/user/0/app/files/git/codex-mobile-pro-secret/x.txt',
          root,
        ),
        isFalse,
      );
      // 空路径 → 拒绝
      expect(AttachmentManager.isWithinRoot('', root), isFalse);
      expect(AttachmentManager.isWithinRoot('/x', ''), isFalse);
    });

    test('formatSize 人类可读', () {
      expect(AttachmentManager.formatSize(512), '512 B');
      expect(AttachmentManager.formatSize(2048), '2.0 KB');
      expect(AttachmentManager.formatSize(5 * 1024 * 1024), '5.0 MB');
    });

    test('大小上限常量合理', () {
      expect(AttachmentManager.maxImageSizeBytes, 10 * 1024 * 1024);
      expect(AttachmentManager.maxFileSizeBytes, 25 * 1024 * 1024);
      expect(AttachmentManager.maxAttachments, 9);
    });
  });
}
