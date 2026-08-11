import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/ai/ai_message.dart';
import '../../../core/ai/attachment.dart';
import '../../../core/ai/chat_engine.dart';
import '../../../core/ai/codex_chat_engine.dart';
import '../../project/providers/project_provider.dart';
import '../models/ai_chat_view_mode.dart';
import '../providers/chat_provider.dart';
import '../services/attachment_manager.dart';

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  /// 待发送附件管理（图片 / 文件 / 项目文件，本地暂存）
  final AttachmentManager _attachmentManager = AttachmentManager();

  @override
  void initState() {
    super.initState();
    _attachmentManager.addListener(_onAttachmentsChanged);
  }

  void _onAttachmentsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _attachmentManager.removeListener(_onAttachmentsChanged);
    _attachmentManager.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final attachments = _attachmentManager.attachments;
    if (text.isEmpty && attachments.isEmpty) return;
    _textController.clear();
    _attachmentManager.clear();

    await ref
        .read(chatProvider.notifier)
        .sendMessage(text, attachments: attachments);
    _scrollToBottom();
  }

  void _stopGeneration() {
    ref.read(chatProvider.notifier).stopGeneration();
  }

  Future<void> _retryLastMessage() async {
    await ref.read(chatProvider.notifier).retryLastMessage();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isStreaming = state.loadingState == ChatLoadingState.streaming;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AI 对话'),
            const SizedBox(width: 8),
            _buildGenerationIndicator(state.generationStatus),
          ],
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          // 界面模式切换（只换渲染层，不重新请求 AI）
          IconButton(
            icon: Icon(
              state.viewMode == AiChatViewMode.bubble
                  ? Icons.chat_bubble
                  : Icons.chat_bubble_outline,
            ),
            tooltip: '气泡模式',
            onPressed: () {
              ref
                  .read(chatProvider.notifier)
                  .setViewMode(AiChatViewMode.bubble);
            },
          ),
          IconButton(
            icon: Icon(
              state.viewMode == AiChatViewMode.stream
                  ? Icons.subject
                  : Icons.subject_outlined,
            ),
            tooltip: '流式模式',
            onPressed: () {
              ref
                  .read(chatProvider.notifier)
                  .setViewMode(AiChatViewMode.stream);
            },
          ),
          // 停止生成
          if (isStreaming)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: '停止生成',
              onPressed: _stopGeneration,
            ),
          // 新建会话
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '新建会话',
            onPressed: () {
              ref.read(chatProvider.notifier).createSession();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 工作目录选择条 ──
          _buildWorkspaceBar(theme, colorScheme, state),

          // ── 消息列表 ──
          Expanded(
            child: state.messages.isEmpty
                ? _buildEmptyState(theme, colorScheme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final msg = state.messages[index];
                      return state.viewMode == AiChatViewMode.stream
                          ? _buildStreamMessage(msg, theme, colorScheme)
                          : _buildMessageBubble(msg, theme, colorScheme);
                    },
                  ),
          ),

          // ── 错误提示 ──
          if (state.errorMessage != null && state.messages.isNotEmpty)
            _buildErrorBar(state.errorMessage!, colorScheme),

          // ── 输入区域 ──
          _buildInputArea(theme, colorScheme, state),
        ],
      ),
    );
  }

  // ── 生成状态指示器 ──

  Widget _buildGenerationIndicator(GenerationStatus status) {
    Color color;
    String tooltip;
    switch (status) {
      case GenerationStatus.streaming:
        color = Colors.green;
        tooltip = '正在生成...';
        break;
      case GenerationStatus.completed:
        color = Colors.green;
        tooltip = '生成完成';
        break;
      case GenerationStatus.error:
        color = Colors.red;
        tooltip = '生成出错';
        break;
      case GenerationStatus.idle:
        color = Colors.grey;
        tooltip = '空闲';
        break;
    }
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  // ── 错误提示栏 ──

  Widget _buildErrorBar(String errorMessage, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red.shade50,
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 重试按钮
          TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
            onPressed: _retryLastMessage,
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ── 空状态 ──

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_outlined, size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('AI 编程助手', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '输入问题开始对话\nAI 可真实读写选定的项目目录、执行命令',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('用 Flutter 写一个按钮'),
                onPressed: () {
                  _textController.text = '用 Flutter 写一个 Material 3 风格的按钮组件';
                  _sendMessage();
                },
              ),
              ActionChip(
                label: const Text('解释这段代码'),
                onPressed: () {
                  _textController.text = '解释 Riverpod 的 StateNotifier 工作原理';
                  _sendMessage();
                },
              ),
              ActionChip(
                label: const Text('帮我 Debug'),
                onPressed: () {
                  _textController.text = '我的 Flutter App 编译报错：\n\n```\nError: A value of type \'Null\' can\'t be assigned to a parameter of type \'Widget\' in a const constructor.\n```\n\n怎么修复？';
                  _sendMessage();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 消息气泡 ──

  Widget _buildMessageBubble(ChatMessage msg, ThemeData theme, ColorScheme colorScheme) {
    final isUser = msg.role == ChatRole.user;
    final isStreaming = msg.isStreaming;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 头像
          if (!isUser)
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8, top: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text('AI', style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                )),
              ),
            ),

          // 消息列（包含重试按钮）
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 消息内容
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isUser
                          ? const Radius.circular(4)
                          : const Radius.circular(16),
                      bottomLeft: !isUser
                          ? const Radius.circular(4)
                          : const Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMessageContent(msg, theme),

                      // 附件展示（图片缩略图 / 文件卡片）
                      if (msg.attachments.isNotEmpty)
                        _buildMessageAttachments(msg, theme, colorScheme),

                      // 流式动画指示
                      if (isStreaming)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),

                      // 工具调用状态（Codex 命令执行）
                      if (!isUser) _buildToolCalls(msg, theme, colorScheme),

                      // 时间戳 + 重试按钮
                      if (!isStreaming && msg.content.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              if (!isUser)
                                TextButton(
                                  onPressed: _retryLastMessage,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: Icon(Icons.refresh, size: 12,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.4)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 用户头像
          if (isUser)
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(left: 8, top: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(Icons.person, size: 18, color: colorScheme.onPrimary),
              ),
            ),
        ],
      ),
    );
  }

  // ── 消息内容渲染（简易 Markdown） ──

  Widget _buildMessageContent(ChatMessage msg, ThemeData theme) {
    if (msg.content.isEmpty && msg.isStreaming) {
      return const SizedBox(
        width: 40,
        child: LinearProgressIndicator(),
      );
    }

    final content = msg.content;
    final segments = <InlineSpan>[];
    final codeBlockRegex = RegExp(r'```(\w*)\n([\s\S]*?)```');
    int lastEnd = 0;

    for (final match in codeBlockRegex.allMatches(content)) {
      // 代码块前的文本
      if (match.start > lastEnd) {
        segments.add(TextSpan(
          text: content.substring(lastEnd, match.start),
          style: theme.textTheme.bodyMedium,
        ));
      }

      // 代码块
      final lang = match.group(1) ?? '';
      final code = match.group(2) ?? '';
      segments.add(WidgetSpan(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.65,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (lang.isNotEmpty)
                    Text(
                      lang,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                  const Spacer(),
                  _CodeBlockCopyButton(code: code),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ));

      lastEnd = match.end;
    }

    // 剩余文本
    if (lastEnd < content.length) {
      segments.add(TextSpan(
        text: content.substring(lastEnd),
        style: theme.textTheme.bodyMedium,
      ));
    }

    if (segments.isEmpty) {
      return SelectionArea(
        child: Text(content, style: theme.textTheme.bodyMedium),
      );
    }

    return SelectionArea(
      child: RichText(
        text: TextSpan(children: segments),
      ),
    );
  }

  // ── 输入区域 ──

  Widget _buildInputArea(ThemeData theme, ColorScheme colorScheme, ChatState state) {
    final isLoading = state.loadingState == ChatLoadingState.streaming;
    final pending = _attachmentManager.attachments;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 待发送附件（输入框上方）
            if (pending.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  children: [
                    for (final a in pending) _buildPendingAttachmentCard(a, theme, colorScheme),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ＋ 附件菜单
                IconButton(
                  onPressed: isLoading ? null : _openAttachmentMenu,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '添加附件',
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    enabled: !isLoading,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: '输入消息…',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      constraints: const BoxConstraints(maxHeight: 120),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                // 停止 / 发送 按钮
                SizedBox(
                  height: 44,
                  child: isLoading
                      ? FilledButton(
                          onPressed: _stopGeneration,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(12),
                            shape: const CircleBorder(),
                            backgroundColor: Colors.red,
                          ),
                          child: const Icon(Icons.stop, color: Colors.white),
                        )
                      : FilledButton(
                          onPressed: _sendMessage,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(12),
                            shape: const CircleBorder(),
                          ),
                          child: const Icon(Icons.send),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 待发送附件卡片（输入框上方横滑）
  Widget _buildPendingAttachmentCard(
    Attachment a,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _attachmentThumb(a, 34, theme, colorScheme),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  a.status == AttachmentStatus.error
                      ? (a.error ?? '附件无效')
                      : AttachmentManager.formatSize(a.size),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: a.status == AttachmentStatus.error
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _attachmentManager.remove(a.id),
            child: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }

  /// 附件缩略图（图片→缩略图，文件→类型图标）
  Widget _attachmentThumb(
    Attachment a,
    double size,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (a.type == AttachmentType.image && a.thumbnail != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GestureDetector(
          onTap: () => _previewImage(a.thumbnail!),
          child: Image.file(
            File(a.thumbnail!),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.broken_image_outlined,
              size: size,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final icon = switch (a.type) {
      AttachmentType.image => Icons.image_outlined,
      AttachmentType.projectFile => Icons.folder_open,
      AttachmentType.file => Icons.insert_drive_file_outlined,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: size * 0.6, color: colorScheme.onSecondaryContainer),
    );
  }

  /// ＋ 附件菜单（拍照 / 相册 / 文件 / 项目文件）
  Future<void> _openAttachmentMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('相册'),
              subtitle: const Text('可选择多张图片'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('文件'),
              subtitle: const Text('从系统文件中选择'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('项目文件'),
              subtitle: const Text('从当前工作目录选择'),
              onTap: () => Navigator.pop(ctx, 'project'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'camera':
        await _attachmentManager.pickImageFromCamera();
      case 'gallery':
        await _attachmentManager.pickImagesFromGallery();
      case 'file':
        await _attachmentManager.pickFile();
      case 'project':
        await _pickProjectFiles();
    }
    if (mounted) setState(() {});
  }

  /// 从当前工作目录选择项目文件（防 ../ 路径穿越）
  Future<void> _pickProjectFiles() async {
    final root = await _currentWorkspaceRoot();
    if (!mounted) return;
    if (root == null) {
      _showSnack('无法定位工作目录');
      return;
    }
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _ProjectFilePickerDialog(root: root),
    );
    if (picked == null || picked.isEmpty) return; // 用户取消
    await _attachmentManager.addProjectFiles(picked, root: root);
    if (mounted) setState(() {});
  }

  /// 当前工作目录 host 根：优先用户选中的项目，否则 App 文档目录。
  Future<String?> _currentWorkspaceRoot() async {
    final dir = ref.read(chatProvider).workspaceDir;
    if (dir != null && dir.isNotEmpty) return dir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    } catch (_) {
      return null;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 全屏预览图片
  Future<void> _previewImage(String path) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(32),
              child: Text('无法加载图片', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  // ── 工作目录选择 ─────────────────────────────────────────

  Widget _buildWorkspaceBar(
    ThemeData theme,
    ColorScheme colorScheme,
    ChatState state,
  ) {
    final dir = state.workspaceDir;
    return Material(
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: _showWorkspacePicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.folder_outlined,
                  size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dir ?? '工作目录：默认（App 文档目录）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dir == null
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down,
                  size: 18, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹出工作目录选择（默认目录 / 已创建项目）
  Future<void> _showWorkspacePicker() async {
    final projects = ref.read(projectProvider).projects;
    final notifier = ref.read(chatProvider.notifier);
    final currentWorkspaceDir = ref.read(chatProvider).workspaceDir;

    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '选择 AI 工作目录',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.smartphone_outlined),
              title: const Text('默认（App 文档目录）'),
              subtitle: const Text('不绑定具体项目'),
              trailing: currentWorkspaceDir == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(ctx),
            ),
            if (projects.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '我的项目',
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: projects.length,
                  itemBuilder: (ctx, i) {
                    final p = projects[i];
                    final isSelected = currentWorkspaceDir == p.path;
                    return ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        p.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(ctx, p.path),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // null = 默认目录；String = 选中的项目路径
    notifier.setWorkspaceDir(selected is String ? selected : null);
  }

  // ── 工具调用状态（Codex 命令执行）──────────────────────────

  /// 气泡内附件展示：图片缩略图 / 文件卡片，点击图片可全屏预览。
  Widget _buildMessageAttachments(
    ChatMessage msg,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in msg.attachments) _buildSentAttachmentCard(a, theme, colorScheme),
        ],
      ),
    );
  }

  /// 已发送附件卡片
  Widget _buildSentAttachmentCard(
    Attachment a,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isImage = a.type == AttachmentType.image && a.thumbnail != null;
    final Widget child;
    if (isImage) {
      child = GestureDetector(
        onTap: () => _previewImage(a.thumbnail!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(a.thumbnail!),
            width: 120,
            height: 90,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 120,
              height: 90,
              color: colorScheme.surfaceContainerHighest,
              child: Icon(Icons.broken_image_outlined,
                  color: colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    } else {
      child = Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              a.type == AttachmentType.projectFile
                  ? Icons.folder_open
                  : Icons.insert_drive_file_outlined,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    AttachmentManager.formatSize(a.size),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return child;
  }

  Widget _buildToolCalls(
    ChatMessage msg,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final calls = _toolCallsOf(msg);
    if (calls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          for (final call in calls)
            _buildToolCallTile(call, theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildToolCallTile(
    CodexToolCall call,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isRunning = call.status == 'in_progress';
    final isError = call.status == 'error';
    final IconData icon;
    final Color color;
    if (isRunning) {
      icon = Icons.terminal;
      color = Colors.orange;
    } else if (isError) {
      icon = Icons.close;
      color = Colors.red;
    } else {
      icon = Icons.check_circle_outline;
      color = Colors.green;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  call.command,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isRunning)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (call.exitCode != null && !isRunning)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '退出码 ${call.exitCode}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: isError ? Colors.red : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (call.output.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                call.output.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
  // ── 流式模式（终端/日志风格，Codex CLI 转写） ─────────────────

  /// 流式模式下单条消息渲染：用户消息 = 终端输入；AI 消息 = 工具调用
  /// （Ran / Read / Working）+ 增量输出。不用聊天气泡作主容器。
  Widget _buildStreamMessage(
    ChatMessage msg,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isUser = msg.role == ChatRole.user;

    // 用户消息：终端输入风格
    if (isUser) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '❯ ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: SelectionArea(
                    child: Text(
                      msg.content,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
            // 附件：Attached ├── name └── name
            if (msg.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attached',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    for (var i = 0; i < msg.attachments.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          '${i == msg.attachments.length - 1 ? '└──' : '├──'} ${msg.attachments[i].name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    // AI 消息：工具调用（Ran / Read / Working）+ 增量输出
    final calls = _toolCallsOf(msg);
    final error = msg.metadata?['error'] as String?;
    final working =
        calls.any((c) => c.status == 'in_progress') || msg.isStreaming;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 结构化工具调用
          for (final call in calls) _buildStreamToolCall(call),
          // Working 行（含流式动画）
          if (working)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Working',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),
            ),
          // 错误
          if (error != null && error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '✗ $error',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.redAccent,
                ),
              ),
            ),
          // AI 增量输出
          if (msg.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectionArea(
                child: SelectableText(
                  msg.content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          // 流式且尚无内容 → 占位指示
          if (msg.isStreaming && msg.content.isEmpty && !working)
            const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  /// 从消息 metadata 解析工具调用列表（气泡/流式共用）。
  List<CodexToolCall> _toolCallsOf(ChatMessage msg) {
    final raw = msg.metadata?['codex_tool_calls'];
    if (raw is! List || raw.isEmpty) return const [];
    return raw
        .map((e) => CodexToolCall.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 单条工具调用的终端风格行：`Ran $ git status` / `Read file.dart`。
  Widget _buildStreamToolCall(CodexToolCall call) {
    final cls = _classifyTool(call.command);
    final isRunning = call.status == 'in_progress';
    final isError = call.status == 'error';
    final Color labelColor =
        isError ? Colors.redAccent : (isRunning ? Colors.orangeAccent : Colors.amber);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$cls ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: labelColor,
              ),
            ),
            TextSpan(
              text: '\$${call.command}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 启发式命令分类：Ran（执行）/ Read（读文件）/ Explored（浏览目录）。
  String _classifyTool(String command) {
    final c = command.trim();
    if (RegExp(
      r'^(cat|sed|head|tail|grep|rg|awk|wc|less|more|python|python3|read|jq)\b',
    ).hasMatch(c)) {
      return 'Read';
    }
    if (RegExp(r'^(ls|find|tree|dir|glob|explore|pwd)\b').hasMatch(c)) {
      return 'Explored';
    }
    return 'Ran';
  }
}


/// 点击将完整代码复制到剪贴板，短暂显示 check 图标。
class _CodeBlockCopyButton extends StatefulWidget {
  const _CodeBlockCopyButton({required this.code});

  final String code;

  @override
  State<_CodeBlockCopyButton> createState() => _CodeBlockCopyButtonState();
}

class _CodeBlockCopyButtonState extends State<_CodeBlockCopyButton> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('代码已复制'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _copy,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      iconSize: 16,
      tooltip: _copied ? '已复制' : '复制代码',
      icon: Icon(
        _copied ? Icons.check : Icons.copy,
        size: 16,
        color: _copied ? Colors.greenAccent : Colors.white70,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 项目文件选择器：只浏览 root 允许范围内的目录，防 ../ 路径穿越。
// ══════════════════════════════════════════════════════════════
class _ProjectFilePickerDialog extends StatefulWidget {
  const _ProjectFilePickerDialog({required this.root});

  final String root;

  @override
  State<_ProjectFilePickerDialog> createState() =>
      _ProjectFilePickerDialogState();
}

class _ProjectFilePickerDialogState extends State<_ProjectFilePickerDialog> {
  late String _currentDir;
  final Set<String> _selected = {};

  bool _loading = true;
  String? _error;
  List<Directory> _dirs = [];
  List<FileSystemEntity> _files = [];

  @override
  void initState() {
    super.initState();
    _currentDir = p.normalize(widget.root);
    _loadDir(_currentDir);
  }

  /// 是否仍在根目录内（不能越过 root，防穿越）
  bool _canGoUp() {
    final parent = p.dirname(_currentDir);
    return p.isWithin(p.normalize(widget.root), parent);
  }

  Future<void> _loadDir(String dir) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = Directory(dir);
      if (!await d.exists()) {
        setState(() {
          _loading = false;
          _error = '目录不存在或已删除';
        });
        return;
      }
      final entities = await d.list(followLinks: false).toList();
      final dirs = <Directory>[];
      final files = <FileSystemEntity>[];
      for (final e in entities) {
        try {
          if (e is Directory) {
            dirs.add(e);
          } else if (e is File) {
            files.add(e);
          }
        } catch (_) {
          // 权限拒绝：跳过该项，不崩溃
        }
      }
      dirs.sort((a, b) => a.path.compareTo(b.path));
      files.sort((a, b) => a.path.compareTo(b.path));
      if (!mounted) return;
      setState(() {
        _currentDir = dir;
        _dirs = dirs;
        _files = files;
        _loading = false;
      });
    } catch (_) {
      // 权限拒绝 / IO 错误：不崩溃
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法读取该目录（权限不足或已删除）';
      });
    }
  }

  void _enterDir(String path) {
    if (!p.isWithin(p.normalize(widget.root), p.normalize(path))) return;
    _loadDir(path);
  }

  void _goUp() {
    if (!_canGoUp()) return;
    _loadDir(p.dirname(_currentDir));
  }

  void _toggleFile(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rootLabel = p.basename(p.normalize(widget.root));

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '选择项目文件 · $rootLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: '取消',
                  ),
                ],
              ),
            ),
            // 路径栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentDir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  IconButton(
                    onPressed: _canGoUp() ? _goUp : null,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    tooltip: '上一级',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 目录 / 文件列表
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colorScheme.error)),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => _loadDir(widget.root),
                              child: const Text('回到根目录'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        if (_dirs.isEmpty && _files.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                '此目录没有可选择的文件',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                        for (final d in _dirs)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder, color: Colors.amber),
                            title: Text(p.basename(d.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            onTap: () => _enterDir(d.path),
                          ),
                        for (final f in _files)
                          ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.insert_drive_file_outlined,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            title: Text(p.basename(f.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: _selected.contains(f.path)
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            onTap: () => _toggleFile(f.path),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            // 底部：已选数量 + 确认
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selected.isEmpty ? '未选择文件' : '已选 ${_selected.length} 个',
                    style: theme.textTheme.bodySmall,
                  ),
                  FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selected.toList()),
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
