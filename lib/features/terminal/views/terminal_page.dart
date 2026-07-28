import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../providers/terminal_provider.dart';
import "package:codex_mobile_pro/features/terminal/services/terminal_service.dart";
import '../widgets/terminal_output.dart';

/// 终端页面（多标签 + 命令历史 + ANSI 渲染）
class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage> {
  final _commandController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitCommand() {
    final cmd = _commandController.text;
    if (cmd.trim().isNotEmpty) {
      ref.read(terminalProvider.notifier).writeCommand(cmd);
      _commandController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(terminalProvider);
    final locale = ref.watch(localeProvider);
    final s = Strings.get(locale);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.terminalTitle),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: s.terminalNew,
            onPressed: () =>
                ref.read(terminalProvider.notifier).createSession(),
          ),
          if (state.sessions.length > 1)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: s.terminalClose,
              onPressed: () {
                if (state.activeSessionId != null) {
                  ref
                      .read(terminalProvider.notifier)
                      .closeSession(state.activeSessionId!);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: s.terminalClear,
            onPressed: () => ref.read(terminalProvider.notifier).disposeAll(),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Tab 栏 ──
          if (state.sessions.length > 1)
            Container(
              height: 40,
              color: colorScheme.surfaceContainerHighest,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: state.sessions.length,
                itemBuilder: (context, index) {
                  final session = state.sessions[index];
                  final isActive = session.id == state.activeSessionId;
                  return _TerminalTab(
                    name: session.name,
                    isActive: isActive,
                    status: session.status,
                    onTap: () => ref
                        .read(terminalProvider.notifier)
                        .switchSession(session.id),
                    onClose: () => ref
                        .read(terminalProvider.notifier)
                        .closeSession(session.id),
                  );
                },
              ),
            ),

          // ── 终端输出（ANSI 渲染） ──
          Expanded(
            child: Container(
              color: Colors.black87,
              child: state.activeSession != null
                  ? GestureDetector(
                      onTap: () {},
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        child: TerminalOutput(
                          text: state.activeSession!.outputText,
                        ),
                      ),
                    )
                  : const Center(
                      child: Text(
                        '点击 + 新建终端',
                        style: TextStyle(
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
            ),
          ),

          // ── 状态栏 ──
          if (state.activeSession != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  _StatusDot(
                    color: state.activeSession!.status ==
                            TerminalSessionStatus.running
                        ? Colors.green
                        : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.activeSession!.cwd,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    state.activeSession!.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

          // ── 命令输入（↑↓键历史导航） ──
          if (state.activeSession != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    onPressed: () =>
                        ref.read(terminalProvider.notifier).sendSigint(),
                    tooltip: '中断 (Ctrl+C)',
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {
                        SingleActivator(LogicalKeyboardKey.arrowUp): () {
                          final cmd = ref
                              .read(terminalProvider.notifier)
                              .historyUp();
                          if (cmd != null) {
                            _commandController.text = cmd;
                            _commandController.selection =
                                TextSelection.fromPosition(
                              TextPosition(offset: cmd.length),
                            );
                          }
                        },
                        SingleActivator(LogicalKeyboardKey.arrowDown): () {
                          final cmd = ref
                              .read(terminalProvider.notifier)
                              .historyDown();
                          _commandController.text = cmd ?? '';
                          if (cmd != null) {
                            _commandController.selection =
                                TextSelection.fromPosition(
                              TextPosition(offset: cmd.length),
                            );
                          }
                        },
                      },
                      child: Focus(
                        autofocus: true,
                        child: TextField(
                          controller: _commandController,
                          decoration: const InputDecoration(
                            hintText: '输入命令...',
                            border: InputBorder.none,
                            hintStyle: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 8),
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          onSubmitted: (cmd) {
                            if (cmd.trim().isNotEmpty) {
                              ref
                                  .read(terminalProvider.notifier)
                                  .writeCommand(cmd);
                              _commandController.clear();
                              _scrollToBottom();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, size: 18),
                    onPressed: _submitCommand,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 终端 Tab
class _TerminalTab extends StatelessWidget {
  final String name;
  final bool isActive;
  final TerminalSessionStatus status;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TerminalTab({
    required this.name,
    required this.isActive,
    required this.status,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.surface : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: status == TerminalSessionStatus.running
                    ? Colors.green
                    : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : null,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// 状态点
class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
