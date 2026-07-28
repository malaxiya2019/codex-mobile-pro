import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/terminal_service.dart';

/// 终端状态
class TerminalState {
  final List<TerminalSession> sessions;
  final String? activeSessionId;

  const TerminalState({this.sessions = const [], this.activeSessionId});

  /// 当前活动会话
  TerminalSession? get activeSession {
    if (activeSessionId == null) return null;
    try {
      return sessions.firstWhere((s) => s.id == activeSessionId);
    } catch (_) {
      return null;
    }
  }

  TerminalState copyWith({
    List<TerminalSession>? sessions,
    String? activeSessionId,
    bool clearActive = false,
  }) {
    return TerminalState(
      sessions: sessions ?? this.sessions,
      activeSessionId: clearActive
          ? null
          : (activeSessionId ?? this.activeSessionId),
    );
  }
}

/// 终端 Provider
final terminalProvider = StateNotifierProvider<TerminalNotifier, TerminalState>(
  (ref) {
    return TerminalNotifier();
  },
);

class TerminalNotifier extends StateNotifier<TerminalState> {
  final TerminalService _service;

  TerminalNotifier()
    : _service = TerminalService(),
      super(const TerminalState());

  /// 创建新终端
  String createSession({String? name, String? cwd}) {
    final session = _service.createSession(name: name, cwd: cwd);
    state = state.copyWith(
      sessions: _service.sessions,
      activeSessionId: session.id,
    );
    return session.id;
  }

  /// 关闭终端
  Future<void> closeSession(String id) async {
    await _service.closeSession(id);
    final remaining = _service.sessions;
    state = state.copyWith(
      sessions: remaining,
      activeSessionId: remaining.isNotEmpty ? remaining.last.id : null,
    );
  }

  /// 切换活动终端
  void switchSession(String id) {
    if (_service.getSession(id) != null) {
      state = state.copyWith(activeSessionId: id);
    }
  }

  /// 写入命令到当前终端
  void writeCommand(String command) {
    state.activeSession?.write(command);
    // 触发 UI 刷新
    state = state.copyWith();
  }

  /// 发送 Ctrl+C
  void sendSigint() {
    state.activeSession?.sendSigint();
    state = state.copyWith();
  }

  /// 清理所有终端
  Future<void> disposeAll() async {
    await _service.disposeAll();
    state = state.copyWith(sessions: const [], clearActive: true);
  }

  /// 强制刷新（外部事件触发）
  void refresh() {
    state = state.copyWith(sessions: _service.sessions);
  }
}
