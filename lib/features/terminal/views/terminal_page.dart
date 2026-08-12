import 'dart:async';

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

/// 终端页面（Termux 风格）
///
/// 结构：
/// ```
/// Scaffold
///  ├─ AppBar（深色；设置 / 新建终端 / 清空-关闭）
///  ├─ Terminal output（纯黑背景，ANSI 渲染，Expanded 占满剩余空间）
///  └─ Bottom terminal controls
///       ├─ command input row（运行/停止 + 输入框 + 发送）
///       └─ extra keys row（Termux 风格两行快捷键）
/// ```
///
/// 仅做 UI 与输入交互改造：TerminalService / Native PTY / ANSI parser /
/// 命令历史 / 命令执行 API 全部复用，不重写后端。
/// Shell prompt 由实际 Shell（PRoot → bash 或 /system/bin/sh）提供，
/// UI 层不伪造提示符。
class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage>
    with WidgetsBindingObserver {
  final _commandController = TextEditingController();
  final _commandFocusNode = FocusNode();
  final _scrollController = ScrollController();

  /// 输出轮询刷新间隔 — 仅 UI 层定时触发重建，读取实时输出缓冲。
  /// 让 apt-get 等长任务的流式输出持续上屏，不修改输出流本身。
  static const Duration _refreshInterval = Duration(milliseconds: 150);

  Timer? _refreshTimer;
  bool _autoScroll = true;
  bool _settingsVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // 加载外观设置
    Future.microtask(() {
      ref.read(terminalSettingsProvider.notifier).load();
    });

    // 打开页面时若无会话则自动创建一个，保持终端状态可用。
    // 会话生命周期由全局 TerminalProvider 持有，离开页面再进入不丢失。
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(terminalProvider).sessions.isEmpty) {
        ref.read(terminalProvider.notifier).createSession();
      }
    });

    // 监听滚动事件 — 检测用户是否手动滚动
    _scrollController.addListener(_onScroll);

    // 输出持续刷新（流式上屏）
    _startOutputRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _commandController.dispose();
    _commandFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 键盘弹出/收起、横竖屏切换时调整 PTY 大小
    _resizeActiveSession();
  }

  /// 输出持续刷新：存在活动会话时周期性调用 notifier.refresh()
  /// 触发重建，使实时输出上屏。无会话时静默跳过。
  void _startOutputRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!mounted) return;
      if (ref.read(terminalProvider).activeSession != null) {
        ref.read(terminalProvider.notifier).refresh();
      }
    });
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
        190; // 减去底部控制栏（输入行 + Extra Keys）高度
    final availableWidth = mediaQuery.size.width - 16;

    final rows = (availableHeight / 20).floor().clamp(10, 200);
    final cols = (availableWidth / 9).floor().clamp(20, 200);
    session.resize(rows, cols);
  }

  void _submitCommand() {
    _executeCommand(_commandController.text);
  }

  /// 输入框内容变化：检测到换行（多行粘贴）立即逐行执行并清空。
  void _onCommandChanged(String text) {
    if (!text.contains('\n')) return;
    _executeCommand(text);
  }

  /// 执行命令：支持多行文本（粘贴脚本），逐行过滤后写入终端
  void _executeCommand(String text) {
    final commands = splitCommandLines(text);
    if (commands.isEmpty) return;
    final provider = ref.read(terminalProvider.notifier);
    for (final cmd in commands) {
      provider.writeCommand(cmd);
    }
    _commandController.clear();
    _scrollToBottom();
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

  /// 点击终端区域：收起设置面板 + 重新获得输入焦点
  void _onTerminalTap() {
    if (_settingsVisible) {
      setState(() => _settingsVisible = false);
    }
    _commandFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(terminalProvider);
    final settings = ref.watch(terminalSettingsProvider);
    final locale = ref.watch(localeProvider);
    final s = Strings.get(locale);

    final activeSession = state.activeSession;
    final isRunning =
        activeSession?.status == TerminalSessionStatus.running;

    // 系统导航栏高度与键盘状态：键盘弹出时不额外垫高（键盘已覆盖导航栏），
    // 收起时才垫高底部控制栏，避免终端区域被导航栏遮挡或出现溢出。
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardVisible = viewInsets.bottom > 0;
    final bottomPad = keyboardVisible ? 0.0 : bottomPadding.toDouble();

    return Scaffold(
      backgroundColor: kTerminalBlack,
      appBar: AppBar(
        backgroundColor: kTerminalDark,
        foregroundColor: kTerminalText,
        title: Text(s.terminalTitle),
        centerTitle: false,
        actions: [
          // 1. 设置
          IconButton(
            icon: Icon(
              _settingsVisible ? Icons.settings : Icons.settings_outlined,
              color: kTerminalText,
            ),
            tooltip: '外观设置',
            onPressed: () {
              setState(() => _settingsVisible = !_settingsVisible);
            },
          ),
          // 2. 新建终端
          IconButton(
            icon: const Icon(Icons.add, color: kTerminalText),
            tooltip: s.terminalNew,
            onPressed: () =>
                ref.read(terminalProvider.notifier).createSession(),
          ),
          // 3. 清空 / 关闭终端
          PopupMenuButton<String>(
            icon: const Icon(Icons.close, color: kTerminalText),
            tooltip: s.terminalClose,
            enabled: activeSession != null,
            color: kTerminalPanel,
            onSelected: (value) {
              final notifier = ref.read(terminalProvider.notifier);
              if (value == 'clear') {
                notifier.clearActiveOutput();
              } else if (value == 'close' && activeSession != null) {
                notifier.closeSession(activeSession.id);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.layers_clear_outlined,
                    color: kTerminalText,
                    size: 20,
                  ),
                  title: Text(
                    '清空输出',
                    style: TextStyle(color: kTerminalText, fontSize: 14),
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'close',
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.close,
                    color: kTerminalText,
                    size: 20,
                  ),
                  title: Text(
                    '关闭终端',
                    style: TextStyle(color: kTerminalText, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 外观设置面板（可选，深色） ──
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

          // ── 多会话 Tab 栏 ──
          if (state.sessions.length > 1) _buildTabBar(state),

          // ── 终端输出（纯黑背景，ANSI 渲染，Expanded 占满剩余空间） ──
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTerminalTap,
              child: Container(
                color: kTerminalBlack,
                width: double.infinity,
                child: activeSession != null
                    ? SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                        child: TerminalOutput(
                          text: activeSession.outputText,
                          fontSize: settings.fontSize,
                          fontFamily: settings.fontFamily,
                          defaultForeground: settings.foregroundColor,
                          cursorBlink: settings.cursorBlink,
                          cursorColor: settings.cursorColor,
                        ),
                      )
                    : Center(
                        child: Text(
                          s.terminalNoSession,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // ── 底部终端控制区（输入行 + Extra Keys） ──
          if (activeSession != null)
            Container(
              color: kTerminalPanel,
              padding: EdgeInsets.only(bottom: bottomPad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCommandInputRow(activeSession, isRunning, settings, s),
                  TerminalExtraKeys(onWrite: _writeToPty),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 多会话 Tab 栏（深色）
  Widget _buildTabBar(TerminalState state) {
    return Container(
      height: 38,
      color: kTerminalDark,
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
            onTap: () =>
                ref.read(terminalProvider.notifier).switchSession(session.id),
            onClose: () =>
                ref.read(terminalProvider.notifier).closeSession(session.id),
          );
        },
      ),
    );
  }

  /// 命令输入行：运行/停止状态按钮 + 输入框 + 发送按钮
  Widget _buildCommandInputRow(
    TerminalSession session,
    bool isRunning,
    TerminalSettings settings,
    Strings s,
  ) {
    return Container(
      color: kTerminalDark,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Row(
        children: [
          // 运行/停止状态按钮：运行中显示「停止」（发送 Ctrl+C 中断），
          // 会话退出/错误时显示灰色「运行」占位（状态指示，不可点击）。
          IconButton(
            icon: Icon(
              isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              size: 20,
              color: isRunning ? Colors.redAccent : Colors.grey,
            ),
            tooltip: isRunning ? '中断 (Ctrl+C)' : '会话已退出',
            visualDensity: VisualDensity.compact,
            onPressed: isRunning
                ? () => ref.read(terminalProvider.notifier).sendSigint()
                : null,
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                // 上下箭头：命令历史（现有逻辑已接管，保持行为不变）
                const SingleActivator(LogicalKeyboardKey.arrowUp): () {
                  final cmd =
                      ref.read(terminalProvider.notifier).historyUp();
                  if (cmd != null) {
                    _commandController.text = cmd;
                    _commandController.selection = TextSelection.fromPosition(
                      TextPosition(offset: cmd.length),
                    );
                  }
                },
                const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                  final cmd =
                      ref.read(terminalProvider.notifier).historyDown();
                  _commandController.text = cmd ?? '';
                  if (cmd != null) {
                    _commandController.selection = TextSelection.fromPosition(
                      TextPosition(offset: cmd.length),
                    );
                  }
                },
              },
              child: TextField(
                controller: _commandController,
                focusNode: _commandFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: s.terminalInputHint,
                  hintStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: kTerminalText,
                ),
                cursorColor: settings.cursorColor,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onChanged: _onCommandChanged,
                // onSubmitted 回调携带当前文本，_submitCommand 内部从
                // controller 读取，忽略入参即可
                onSubmitted: (_) => _submitCommand(),
              ),
            ),
          ),
          // 发送按钮
          IconButton(
            icon: const Icon(Icons.send, size: 18, color: kTerminalText),
            tooltip: '发送',
            visualDensity: VisualDensity.compact,
            onPressed: _submitCommand,
          ),
        ],
      ),
    );
  }
}

/// 外观设置面板（深色，Termux 风格）
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: kTerminalDark,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 字体大小
          Row(
            children: [
              const Text(
                '字体大小',
                style: TextStyle(fontSize: 12, color: kTerminalText),
              ),
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
                style: const TextStyle(fontSize: 12, color: kTerminalText),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 主题 + 光标
          Row(
            children: [
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

/// 设置项 Chip（深色）
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
    final accent = selected ? Colors.amberAccent : kTerminalText;

    return Material(
      color: selected ? const Color(0xFF3A3A3A) : kTerminalKey,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: accent,
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

/// 终端 Tab（深色）
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? kTerminalPanel : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? Colors.greenAccent : Colors.transparent,
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
                color: kTerminalText,
                fontWeight: isActive ? FontWeight.w600 : null,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, size: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
