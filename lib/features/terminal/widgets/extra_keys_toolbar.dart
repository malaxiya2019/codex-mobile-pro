import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 功能键工具栏 — 终端底部的可横向滚动 Extra Keys
///
/// 支持：
/// - Ctrl 组合键（点击 Ctrl 后进入组合模式，再点字母键发送 Ctrl+字母）
/// - Alt Meta 键
/// - Esc、Tab
/// - 方向键、Home、End、PageUp、PageDown
class ExtraKeysToolbar extends StatefulWidget {
  /// 写入回调 — 向 PTY 发送原始字节
  final void Function(String data) onWrite;

  /// 发送 Ctrl+C 快捷方式
  final VoidCallback? onSendSigint;

  /// 发送 Ctrl+D 快捷方式
  final VoidCallback? onSendEof;

  const ExtraKeysToolbar({
    super.key,
    required this.onWrite,
    this.onSendSigint,
    this.onSendEof,
  });

  @override
  State<ExtraKeysToolbar> createState() => _ExtraKeysToolbarState();
}

class _ExtraKeysToolbarState extends State<ExtraKeysToolbar> {
  bool _ctrlMode = false;
  bool _altMode = false;

  Future<bool> _onWillPop() async {
    // 如果处于 Ctrl 或 Alt 模式，先退出模式
    if (_ctrlMode || _altMode) {
      setState(() {
        _ctrlMode = false;
        _altMode = false;
      });
      return false; // 不返回
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_ctrlMode && !_altMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _ctrlMode = false;
            _altMode = false;
          });
        }
      },
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: GestureDetector(
          onVerticalDragStart: (_) {
            // 阻止垂直滑动冲突
          },
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            physics: const ClampingScrollPhysics(),
            children: [
              // Ctrl 模式切换
              _KeyButton(
                label: 'Ctrl',
                isActive: _ctrlMode,
                activeColor: colorScheme.primary,
                onTap: () {
                  setState(() {
                    _ctrlMode = !_ctrlMode;
                    if (_ctrlMode) _altMode = false;
                  });
                },
              ),
              // Alt 模式切换
              _KeyButton(
                label: 'Alt',
                isActive: _altMode,
                activeColor: colorScheme.secondary,
                onTap: () {
                  setState(() {
                    _altMode = !_altMode;
                    if (_altMode) _ctrlMode = false;
                  });
                },
              ),
              _divider(),
              // Esc
              _KeyButton(
                label: 'Esc',
                onTap: () => _send('\x1b'),
              ),
              // Tab
              _KeyButton(
                label: 'Tab',
                onTap: () => _send('\t'),
              ),
              // Ctrl 组合键（Ctrl 模式下显示）
              if (_ctrlMode) ...[
                _divider(),
                _KeyButton(label: 'C', onTap: () => _sendCtrl('c')),
                _KeyButton(label: 'D', onTap: () => _sendCtrl('d')),
                _KeyButton(label: 'L', onTap: () => _sendCtrl('l')),
                _KeyButton(label: 'Z', onTap: () => _sendCtrl('z')),
                _KeyButton(label: 'A', onTap: () => _sendCtrl('a')),
                _KeyButton(label: 'W', onTap: () => _sendCtrl('w')),
                _KeyButton(label: 'U', onTap: () => _sendCtrl('u')),
                _KeyButton(label: 'R', onTap: () => _sendCtrl('r')),
              ],
              // Alt 组合键（Alt 模式下显示）
              if (_altMode) ...[
                _divider(),
                _KeyButton(label: 'B', onTap: () => _sendAlt('b')),
                _KeyButton(label: 'F', onTap: () => _sendAlt('f')),
                _KeyButton(label: 'D', onTap: () => _sendAlt('d')),
              ],
              _divider(),
              // 方向键
              _KeyButton(
                label: '↑',
                onTap: () => _send('\x1b[A'),
              ),
              _KeyButton(
                label: '↓',
                onTap: () => _send('\x1b[B'),
              ),
              _KeyButton(
                label: '→',
                onTap: () => _send('\x1b[C'),
              ),
              _KeyButton(
                label: '←',
                onTap: () => _send('\x1b[D'),
              ),
              _divider(),
              // Home / End
              _KeyButton(
                label: 'Home',
                onTap: () => _send('\x1b[H'),
              ),
              _KeyButton(
                label: 'End',
                onTap: () => _send('\x1b[F'),
              ),
              // PgUp / PgDn
              _KeyButton(
                label: 'PgUp',
                onTap: () => _send('\x1b[5~'),
              ),
              _KeyButton(
                label: 'PgDn',
                onTap: () => _send('\x1b[6~'),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        width: 1,
        color: Colors.grey.withValues(alpha: 0.3),
      ),
    );
  }

  void _send(String data) {
    widget.onWrite(data);
    // Ctrl 和 Alt 模式在发送后不自动退出，让用户可以连续发 Ctrl+C、Ctrl+D 等
  }

  void _sendCtrl(String ch) {
    // Ctrl+字母 = ch.codeUnitAt(0) - 0x60 (0x01-0x1A)
    final code = ch.toUpperCase().codeUnitAt(0) - 0x40;
    widget.onWrite(String.fromCharCode(code));
    // 发送后退出 Ctrl 模式
    setState(() {
      _ctrlMode = false;
    });
  }

  void _sendAlt(String ch) {
    // Alt+字母 = ESC + 字母
    widget.onWrite('\x1b$ch');
    setState(() {
      _altMode = false;
    });
  }
}

/// 单个功能键按钮
class _KeyButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onTap;

  const _KeyButton({
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: isActive
            ? (activeColor ?? colorScheme.primary).withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive
                    ? (activeColor ?? colorScheme.primary)
                    : colorScheme.outlineVariant,
                width: isActive ? 1.5 : 0.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive
                    ? (activeColor ?? colorScheme.primary)
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
