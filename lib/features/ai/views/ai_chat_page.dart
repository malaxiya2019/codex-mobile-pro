import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  void initState() {
    super.initState();
    // 进入页面时自动检查服务状态
    Future.microtask(() => ref.read(chatProvider.notifier).checkService());
  }

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AI 对话'),
            const SizedBox(width: 8),
            _buildServiceIndicator(state.serviceStatus),
          ],
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          if (state.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空对话'),
                    content: const Text('确定要清空当前对话吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          ref.read(chatProvider.notifier).clearChat();
                        },
                        child: const Text('确认清空'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // ── 服务状态提示 ──
          if (state.serviceStatus != AiServiceStatus.ready &&
              state.messages.isEmpty)
            _buildServicePrompt(state.serviceStatus, theme),

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
                      if (msg.role == ChatRole.system) return const SizedBox.shrink();
                      return _buildMessageBubble(msg, theme, colorScheme);
                    },
                  ),
          ),

          // ── 错误提示 ──
          if (state.errorMessage != null && state.messages.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),

          // ── 输入区域 ──
          _buildInputArea(theme, colorScheme, state),
        ],
      ),
    );
  }

  // ── 服务状态指示器 ──

  Widget _buildServiceIndicator(AiServiceStatus status) {
    Color color;
    String tooltip;
    switch (status) {
      case AiServiceStatus.ready:
        color = Colors.green;
        tooltip = 'AI 服务就绪';
        break;
      case AiServiceStatus.connecting:
        color = Colors.orange;
        tooltip = '正在连接...';
        break;
      case AiServiceStatus.proxyDown:
        color = Colors.red;
        tooltip = '代理未运行';
        break;
      case AiServiceStatus.invalidKey:
        color = Colors.red;
        tooltip = 'API Key 无效';
        break;
      case AiServiceStatus.error:
        color = Colors.orange;
        tooltip = '服务异常';
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

  // ── 服务状态提示栏 ──

  Widget _buildServicePrompt(AiServiceStatus status, ThemeData theme) {
    String message;
    switch (status) {
      case AiServiceStatus.proxyDown:
        message = '⚠️ mimo2codex 代理未运行，请先启动代理后再对话';
        break;
      case AiServiceStatus.invalidKey:
        message = '⚠️ DeepSeek API Key 无效，请检查 ~/.mimo2codex/.env 配置';
        break;
      case AiServiceStatus.error:
        message = '⚠️ AI 服务异常，请检查网络连接';
        break;
      default:
        message = '⏳ 正在检查 AI 服务状态...';
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(message, style: theme.textTheme.bodySmall),
    );
  }

  // ── 空状态 ──

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('AI 编程助手', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '输入问题开始对话\n支持代码生成、解释、调试',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
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

          // 消息内容
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                  bottomLeft: !isUser ? const Radius.circular(4) : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 消息文本（简易 Markdown 渲染）
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

                  // 时间戳
                  if (!isStreaming && msg.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                ],
              ),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: const BoxConstraints(maxHeight: 120),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: isLoading ? null : _sendMessage,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                  shape: const CircleBorder(),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
