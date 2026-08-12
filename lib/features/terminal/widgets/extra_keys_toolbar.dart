import 'package:flutter/material.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Termux 风格终端配色（固定深色，不随应用主题变化）
///
/// 终端页面整体为「黑色终端 + 深灰控制栏」，与系统亮/暗主题解耦。
/// ────────────────────────────────────────────────────────────────────────────
const Color kTerminalBlack = Color(0xFF000000); // 终端输出纯黑背景
const Color kTerminalDark = Color(0xFF171717); // AppBar / 命令输入行
const Color kTerminalPanel = Color(0xFF1E1E1E); // 底部控制区 / 设置面板
const Color kTerminalKey = Color(0xFF2D2D2D); // Extra Key 按钮底色
const Color kTerminalBorder = Color(0xFF3A3A3A); // 分隔线 / 按钮描边
const Color kTerminalText = Color(0xFFE6E6E6); // 默认前景（浅灰，Termux 风格）

/// ══════════════════════════════════════════════════════════════════════════
/// 终端扩展按键栏（Extra Keys）
///
/// 两行布局，参考 Termux Extra Keys：
///   第一行：ESC   /    -    HOME   ↑   END   PGUP
///   第二行：TAB   CTRL   ALT   ←    ↓   →   PGDN
///
/// - 深色背景，紧凑矩形圆角按钮，横向平均分配（Row + Expanded）
/// - 横向空间不足时标签自动缩放（FittedBox），小屏不溢出
/// - CTRL / ALT 为一次性修饰键：按下后下一按键自动组合，发送后退出
/// - 所有按键向当前终端写入原始控制字符 / ANSI 键序列，
///   不当作普通文本输入（不进入命令输入框）
/// ══════════════════════════════════════════════════════════════════════════

/// 按键类型
enum ExtraKeyType {
  /// 普通按键 — 直接发送指定数据
  normal,

  /// Ctrl 模式切换
  ctrl,

  /// Alt 模式切换
  alt,

  /// Ctrl 组合键（仅在 Ctrl/Alt 模式下展示）
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

/// 两行布局的按键定义（数据驱动，便于后续扩展 F1~F12 等）
///
/// 方向键 / HOME / END / PGUP / PGDN 使用标准 ANSI escape sequence：
///   ↑ \x1b[A   ↓ \x1b[B   ← \x1b[D   → \x1b[C
///   HOME \x1b[H   END \x1b[F   PGUP \x1b[5~   PGDN \x1b[6~
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
    return Container(
      color: kTerminalPanel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ctrl/Alt 组合键面板（修饰模式激活时显示）
          if (_ctrlMode) _buildComboPanel(kCtrlCombos, 'CTRL', Colors.amberAccent),
          if (_altMode) _buildComboPanel(kAltCombos, 'ALT', Colors.lightGreenAccent),

          // 两行主按键（横向平均分配）
          _buildKeyRow(kExtraKeyRows[0]),
          const SizedBox(height: 4),
          _buildKeyRow(kExtraKeyRows[1]),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// 构建 Ctrl / Alt 组合键面板（横向滚动）
  Widget _buildComboPanel(
    List<ExtraKeyConfig> configs,
    String prefix,
    Color accent,
  ) {
    return Container(
      height: 34,
      margin: const EdgeInsets.only(top: 4),
      color: kTerminalDark,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          ...configs.map(
            (config) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: _buildComboChip(config, prefix, accent),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// 构建 Ctrl / Alt 组合键 Chip
  Widget _buildComboChip(
    ExtraKeyConfig config,
    String prefix,
    Color accent,
  ) {
    return Material(
      color: kTerminalKey,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _handleKeyTap(config),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            '$prefix ${config.label}',
            style: TextStyle(
              fontSize: 12,
              color: accent,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建一行按键 — Row + Expanded 横向平均分配
  Widget _buildKeyRow(List<ExtraKeyConfig> configs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          for (final config in configs)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: _buildKeyButton(config),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建单个按键 — 紧凑矩形圆角按钮
  Widget _buildKeyButton(ExtraKeyConfig config) {
    final isCtrlActive = config.type == ExtraKeyType.ctrl && _ctrlMode;
    final isAltActive = config.type == ExtraKeyType.alt && _altMode;
    final isActive = isCtrlActive || isAltActive;
    final accent = isCtrlActive
        ? Colors.amberAccent
        : (isAltActive ? Colors.lightGreenAccent : null);

    return Material(
      color: isActive
          ? (accent ?? Colors.amberAccent).withValues(alpha: 0.22)
          : kTerminalKey,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _handleKeyTap(config),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive ? (accent ?? Colors.amberAccent) : kTerminalBorder,
              width: isActive ? 1.2 : 1,
            ),
          ),
          // FittedBox：横向空间不足时标签自动缩小，避免小屏溢出
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              config.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive
                    ? (accent ?? Colors.amberAccent)
                    : kTerminalText,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
