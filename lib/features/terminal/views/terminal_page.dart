import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../providers/terminal_provider.dart';
import '../providers/terminal_settings_provider.dart';
import '../services/terminal_service.dart';
import '../widgets/extra_keys_toolbar.dart';
import '../widgets/terminal_output.dart';

/// 终端页面（多标签 + 命令历史 + ANSI 渲染 + 功能键 + 外观设置）
///
/// 沉浸式布局：自动适配系统导航栏，输入框上移不被遮挡。
class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage>
    with WidgetsBindingObserver {
  final _commandController = TextEditingController();
  final _scrollController = ScrollController();
  bool _autoScroll = true;
  bool _settingsVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // 加载设置
    Future.microtask(() {
      ref.read(terminalSettingsProvider.notifier).load();
    });

    // 监听滚动事件 — 检测用户是否手动滚动
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commandController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 横竖屏切换时调整 PTY 大小
    _resizeActiveSession();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // 如果用户向上滚动，停止自动滚动
    final isAtBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50;
    if (_autoScroll != isAtBottom) {
      _autoScroll = isAtBottom;
    }
  }

  void _resizeActiveSession() {
    final state = ref.read(terminalProvider);
    final session = state.activeSession;
    if (session == null) return;

    final mediaQuery = MediaQuery.of(context);
    final availableHeight = mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        kToolbarHeight -
        120; // 减去输入栏和工具栏高度
    final availableWidth = mediaQuery.size.width - 24; // 减去 padding

    final rows = (availableHeight / 20).floor().clamp(10, 200);
    final cols = (availableWidth / 9).floor().clamp(20, 200);
    session.resize(rows, cols);
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
    _autoScroll = true;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 向 PTY 写入原始数据（由 TerminalExtraKeys 调用）
  void _writeToPty(String data) {
    ref.read(terminalProvider.notifier).writeRaw(data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(terminalProvider);
    final settings = ref.watch(terminalSettingsProvider);
    final locale = ref.watch(localeProvider);
    final s = Strings.get(locale);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.terminalTitle),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainer,
        actions: [
          // 设置按钮
          IconButton(
            icon: Icon(_settingsVisible ? Icons.settings : Icons.settings_outlined),
            tooltip: '外观设置',
            onPressed: () {
              setState(() {
                _settingsVisible = !_settingsVisible;
              });
            },
          ),
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
          // ── 外观设置面板 ──
          if (_settingsVisible)
            _SettingsPanel(
              settings: settings,
              onFontSizeChanged: (v) {
                ref.read(terminalSettingsProvider.notifier).setFontSize(v);
              },
              onThemeModeChanged: (v) {
                ref.read(terminalSettingsProvider.notifier).setThemeMode(v);
              },
              onCursorBlinkChanged: (v) {
                ref.read(terminalSettingsProvider.notifier).setCursorBlink(v);
              },
            ),

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

          // ── 终端输出（ANSI 渲染 + 可滚动历史） ──
          Expanded(
            child: Container(
              color: settings.backgroundColor,
              child: state.activeSession != null
                  ? GestureDetector(
                      onTap: () {
                        // 点击终端区域，收起设置面板
                        if (_settingsVisible) {
                          setState(() => _settingsVisible = false);
                        }
                      },
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          12,
                          12,
                          12,
                          isLandscape ? 4 : 4,
                        ),
                        child: TerminalOutput(
                          text: state.activeSession!.outputText,
                          fontSize: settings.fontSize,
                          fontFamily: settings.fontFamily,
                          defaultForeground: settings.foregroundColor,
                          defaultBackground: settings.backgroundColor,
                          cursorBlink: settings.cursorBlink,
                          cursorColor: settings.cursorColor,
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

          // ── 终端扩展按键栏（Extra Keys） ──
          if (state.activeSession != null)
            TerminalExtraKeys(
              onWrite: _writeToPty,
            ),



          // ── 命令输入区（适配系统导航栏） ──
          if (state.activeSession != null)
            Container(
              padding: EdgeInsets.fromLTRB(4, 2, 4,
                  bottomPadding > 0 ? bottomPadding - 4 : 6),
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

class _SettingsPanel extends StatelessWidget {
  final TerminalSettings settings;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<bool> onCursorBlinkChanged;

  const _SettingsPanel({
    required this.settings,
    required this.onFontSizeChanged,
    required this.onThemeModeChanged,
    required this.onCursorBlinkChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 字体大小
          Row(
            children: [
              const Text('字体大小', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 8,
                  max: 32,
                  divisions: 24,
                  label: '${settings.fontSize.round()}',
                  onChanged: onFontSizeChanged,
                ),
              ),
              Text(
                '${settings.fontSize.round()}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 主题 + 光标
          Row(
            children: [
              // 主题选择
              _SettingChip(
                icon: Icons.dark_mode,
                label: '深色',
                selected: settings.themeMode == ThemeMode.dark,
                onTap: () => onThemeModeChanged(ThemeMode.dark),
              ),
              const SizedBox(width: 8),
              _SettingChip(
                icon: Icons.light_mode,
                label: '浅色',
                selected: settings.themeMode == ThemeMode.light,
                onTap: () => onThemeModeChanged(ThemeMode.light),
              ),
              const SizedBox(width: 8),
              _SettingChip(
                icon: Icons.auto_mode,
                label: '系统',
                selected: settings.themeMode == ThemeMode.system,
                onTap: () => onThemeModeChanged(ThemeMode.system),
              ),
              const Spacer(),
              // 光标闪烁
              _SettingChip(
                icon: Icons.flash_on,
                label: '光标',
                selected: settings.cursorBlink,
                onTap: () => onCursorBlinkChanged(!settings.cursorBlink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 设置项 Chip
class _SettingChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SettingChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
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
