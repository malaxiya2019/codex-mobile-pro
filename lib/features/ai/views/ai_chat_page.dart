import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/chat_engine.dart';
import '../../../core/ai/ai_message.dart';
import '../providers/chat_provider.dart';

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
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
    if (text.isEmpty) return;
    _textController.clear();

    await ref.read(chatProvider.notifier).sendMessage(text);
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
                      return _buildMessageBubble(msg, theme, colorScheme);
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
            '输入问题开始对话\n支持代码生成、解释、调试',
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
              if (lang.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    lang,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ),
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
      return Text(content, style: theme.textTheme.bodyMedium);
    }

    return RichText(
      text: TextSpan(children: segments),
    );
  }

  // ── 输入区域 ──

  Widget _buildInputArea(ThemeData theme, ColorScheme colorScheme, ChatState state) {
    final isLoading = state.loadingState == ChatLoadingState.streaming;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                enabled: !isLoading,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: '输入问题...',
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
      ),
    );
  }
}
