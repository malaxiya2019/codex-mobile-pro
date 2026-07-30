import 'package:flutter/material.dart';

/// ====================================================================
/// 终端扩展按键栏（Extra Keys）
///
/// 两行布局，参考 Termux Extra Keys，保持 Material 3 风格。
///
/// 按键配置采用数据驱动，便于后续扩展 F1~F12、Insert、Delete 等。
///
/// 布局：
///   第一行：ESC   /    -    HOME   ↑   END   PGUP
///   第二行：TAB   CTRL   ALT   ←    ↓   →    PGDN
///
/// Ctrl 模式：一次性，下一按键自动组合为 Ctrl+Key，发送后退出。
/// Alt 模式：一次性，下一按键发送 ESC + Key（Meta），发送后退出。
/// ====================================================================

/// 按键类型
enum ExtraKeyType {
  /// 普通按键 — 直接发送指定数据
  normal,

  /// Ctrl 模式切换
  ctrl,

  /// Alt 模式切换
  alt,

  /// Ctrl 组合键（仅在 Ctrl 模式下可见）
  ctrlCombo,
}

/// 扩展按键配置
class ExtraKeyConfig {
  /// 按钮标签
  final String label;

  /// 按键类型
  final ExtraKeyType type;

  /// 按键数据（发送到 PTY 的内容）
  final String data;

  /// 仅在 Ctrl 模式下显示
  final bool ctrlOnly;

  /// 仅在 Alt 模式下显示
  final bool altOnly;

  const ExtraKeyConfig({
    required this.label,
    this.type = ExtraKeyType.normal,
    this.data = '',
    this.ctrlOnly = false,
    this.altOnly = false,
  });
}

/// 两行布局的按键定义
///
/// 使用数据驱动方式，便于后续扩展。
const List<List<ExtraKeyConfig>> kExtraKeyRows = [
  // ── 第一行 ──
  [
    ExtraKeyConfig(label: 'ESC', data: '\x1b'),
    ExtraKeyConfig(label: '/', data: '/'),
    ExtraKeyConfig(label: '-', data: '-'),
    ExtraKeyConfig(label: 'HOME', data: '\x1b[H'),
    ExtraKeyConfig(label: '↑', data: '\x1b[A'),
    ExtraKeyConfig(label: 'END', data: '\x1b[F'),
    ExtraKeyConfig(label: 'PGUP', data: '\x1b[5~'),
  ],
  // ── 第二行 ──
  [
    ExtraKeyConfig(label: 'TAB', data: '\t'),
    ExtraKeyConfig(label: 'CTRL', type: ExtraKeyType.ctrl),
    ExtraKeyConfig(label: 'ALT', type: ExtraKeyType.alt),
    ExtraKeyConfig(label: '←', data: '\x1b[D'),
    ExtraKeyConfig(label: '↓', data: '\x1b[B'),
    ExtraKeyConfig(label: '→', data: '\x1b[C'),
    ExtraKeyConfig(label: 'PGDN', data: '\x1b[6~'),
  ],
];

/// Ctrl 模式下的常用组合键
const List<ExtraKeyConfig> kCtrlCombos = [
  ExtraKeyConfig(label: 'C', data: '\x03', type: ExtraKeyType.ctrlCombo),
  ExtraKeyConfig(label: 'D', data: '\x04', type: ExtraKeyType.ctrlCombo),
  ExtraKeyConfig(label: 'L', data: '\x0c', type: ExtraKeyType.ctrlCombo),
  ExtraKeyConfig(label: 'Z', data: '\x1a', type: ExtraKeyType.ctrlCombo),
  ExtraKeyConfig(label: 'A', data: '\x01', type: ExtraKeyType.ctrlCombo),
  ExtraKeyConfig(label: 'W', data: '\x17', type: ExtraKeyType.ctrlCombo),
  ExtraKeyConfig(label: 'U', data: '\x15', type: ExtraKeyType.ctrlCombo),
];

/// Alt 模式下的常用组合键
const List<ExtraKeyConfig> kAltCombos = [
  ExtraKeyConfig(label: 'B', data: '\x1bb', type: ExtraKeyType.ctrlCombo),
  ExtraKeyConfig(label: 'F', data: '\x1bf', type: ExtraKeyType.ctrlCombo),
  ExtraKeyConfig(label: 'D', data: '\x1bd', type: ExtraKeyType.ctrlCombo),
];

/// 终端扩展按键栏
class TerminalExtraKeys extends StatefulWidget {
  /// 写入回调 — 向 PTY 发送原始字节
  final void Function(String data) onWrite;

  const TerminalExtraKeys({
    super.key,
    required this.onWrite,
  });

  @override
  State<TerminalExtraKeys> createState() => _TerminalExtraKeysState();
}

class _TerminalExtraKeysState extends State<TerminalExtraKeys> {
  bool _ctrlMode = false;
  bool _altMode = false;

  /// 处理按键点击
  void _handleKeyTap(ExtraKeyConfig config) {
    // Ctrl/Alt 模式切换
    if (config.type == ExtraKeyType.ctrl) {
      setState(() {
        _ctrlMode = !_ctrlMode;
        if (_ctrlMode) _altMode = false;
      });
      return;
    }
    if (config.type == ExtraKeyType.alt) {
      setState(() {
        _altMode = !_altMode;
        if (_altMode) _ctrlMode = false;
      });
      return;
    }

    // Ctrl 组合键 — 直接发送
    if (config.type == ExtraKeyType.ctrlCombo) {
      widget.onWrite(config.data);
      setState(() => _ctrlMode = false);
      return;
    }

    // 普通按键 — 如果处于 Ctrl 或 Alt 模式，应用修饰符
    if (_ctrlMode) {
      // Ctrl + 按键
      if (config.data.length == 1) {
        final ch = config.data.codeUnitAt(0);
        if (ch >= 0x61 && ch <= 0x7A) {
          // 小写字母 → Ctrl+letter
          widget.onWrite(String.fromCharCode(ch - 0x60));
        } else if (ch >= 0x41 && ch <= 0x5A) {
          // 大写字母 → Ctrl+letter
          widget.onWrite(String.fromCharCode(ch - 0x40));
        } else {
          // 非字母按键 — 发送 Ctrl+key 的简化形式
          // 对于特殊键（HOME/END/方向键等），Ctrl 模式不适用，发送原始数据
          widget.onWrite(config.data);
        }
      } else {
        // 多字节序列（方向键等）— Ctrl 模式下不转换，发送原始数据
        widget.onWrite(config.data);
      }
      setState(() => _ctrlMode = false);
      return;
    }

    if (_altMode) {
      // Alt + 按键 = ESC + 原始数据
      widget.onWrite('\x1b${config.data}');
      setState(() => _altMode = false);
      return;
    }

    // 普通模式 — 直接发送
    widget.onWrite(config.data);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ctrl/Alt 组合键面板（展开时显示）
          if (_ctrlMode) _buildCtrlPanel(colorScheme),
          if (_altMode) _buildAltPanel(colorScheme),

          // 两行主按键
          _buildKeyRow(kExtraKeyRows[0], colorScheme),
          const SizedBox(height: 2),
          _buildKeyRow(kExtraKeyRows[1], colorScheme),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  /// 构建 Ctrl 组合键面板
  Widget _buildCtrlPanel(ColorScheme colorScheme) {
    return Container(
      height: 36,
      margin: const EdgeInsets.only(top: 2),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          ...kCtrlCombos.map((config) => _buildCtrlAltChip(config, colorScheme)),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// 构建 Alt 组合键面板
  Widget _buildAltPanel(ColorScheme colorScheme) {
    return Container(
      height: 36,
      margin: const EdgeInsets.only(top: 2),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          ...kAltCombos.map((config) => _buildCtrlAltChip(config, colorScheme)),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// 构建 Ctrl/Alt 组合键 Chip
  Widget _buildCtrlAltChip(ExtraKeyConfig config, ColorScheme colorScheme) {
    final isCtrl = _ctrlMode;
    final accent = isCtrl ? colorScheme.primary : colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _handleKeyTap(config),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCtrl ? '^' : 'M-',
                  style: TextStyle(
                    fontSize: 11,
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  config.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建一行按键
  Widget _buildKeyRow(List<ExtraKeyConfig> configs, ColorScheme colorScheme) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        physics: const ClampingScrollPhysics(),
        children: [
          ...configs.map((config) => _buildKeyButton(config, colorScheme)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// 构建单个按键
  Widget _buildKeyButton(ExtraKeyConfig config, ColorScheme colorScheme) {
    final isCtrlActive = config.type == ExtraKeyType.ctrl && _ctrlMode;
    final isAltActive = config.type == ExtraKeyType.alt && _altMode;
    final isActive = isCtrlActive || isAltActive;
    final accentColor = isCtrlActive
        ? colorScheme.primary
        : (isAltActive ? colorScheme.secondary : null);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: isActive
            ? (accentColor ?? colorScheme.primary).withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _handleKeyTap(config),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? (accentColor ?? colorScheme.primary)
                    : colorScheme.outlineVariant,
                width: isActive ? 1.5 : 0.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              config.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive
                    ? (accentColor ?? colorScheme.primary)
                    : colorScheme.onSurface,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
