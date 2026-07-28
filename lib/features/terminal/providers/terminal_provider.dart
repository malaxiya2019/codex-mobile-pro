import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/terminal_service.dart';

/// 终端状态
class TerminalState {
  final List<TerminalSession> sessions;
  final String? activeSessionId;

  /// 命令历史 — 每个会话独立
  final Map<String, List<String>> commandHistory;

  /// 当前导航索引（-1 表示新输入）
  final Map<String, int> historyIndex;

  const TerminalState({
    this.sessions = const [],
    this.activeSessionId,
    this.commandHistory = const {},
    this.historyIndex = const {},
  });

  TerminalSession? get activeSession {
    if (activeSessionId == null) return null;
    try {
      return sessions.firstWhere((s) => s.id == activeSessionId);
    } catch (_) {
      return null;
    }
  }

  List<String> get currentHistory {
    if (activeSessionId == null) return [];
    return commandHistory[activeSessionId] ?? [];
  }

  String? get currentHistoryCommand {
    if (activeSessionId == null) return null;
    final idx = historyIndex[activeSessionId] ?? -1;
    final history = commandHistory[activeSessionId] ?? [];
    if (idx < 0 || idx >= history.length) return null;
    return history[idx];
  }

  TerminalState copyWith({
    List<TerminalSession>? sessions,
    String? activeSessionId,
    bool clearActive = false,
    Map<String, List<String>>? commandHistory,
    Map<String, int>? historyIndex,
  }) {
    return TerminalState(
      sessions: sessions ?? this.sessions,
      activeSessionId: clearActive
          ? null
          : (activeSessionId ?? this.activeSessionId),
      commandHistory: commandHistory ?? this.commandHistory,
      historyIndex: historyIndex ?? this.historyIndex,
    );
  }
}

final terminalProvider = StateNotifierProvider<TerminalNotifier, TerminalState>(
  (ref) => TerminalNotifier(),
);

class TerminalNotifier extends StateNotifier<TerminalState> {
  final TerminalService _service;

  TerminalNotifier()
    : _service = TerminalService(),
      super(const TerminalState());

  String createSession({String? name, String? cwd}) {
    final session = _service.createSession(name: name, cwd: cwd);
    final history = Map<String, List<String>>.from(state.commandHistory);
    final histIdx = Map<String, int>.from(state.historyIndex);
    history[session.id] = [];
    histIdx[session.id] = -1;

    state = state.copyWith(
      sessions: _service.sessions,
      activeSessionId: session.id,
      commandHistory: history,
      historyIndex: histIdx,
    );
    return session.id;
  }

  Future<void> closeSession(String id) async {
    await _service.closeSession(id);
    final remaining = _service.sessions;
    final history = Map<String, List<String>>.from(state.commandHistory);
    final histIdx = Map<String, int>.from(state.historyIndex);
    history.remove(id);
    histIdx.remove(id);

    state = state.copyWith(
      sessions: remaining,
      activeSessionId: remaining.isNotEmpty ? remaining.last.id : null,
      commandHistory: history,
      historyIndex: histIdx,
    );
  }

  void switchSession(String id) {
    if (_service.getSession(id) != null) {
      state = state.copyWith(activeSessionId: id);
    }
  }

  void writeCommand(String command) {
    if (command.trim().isEmpty) return;
    state.activeSession?.write(command);

    final sessionId = state.activeSessionId;
    if (sessionId != null) {
      final history = Map<String, List<String>>.from(state.commandHistory);
      final histIdx = Map<String, int>.from(state.historyIndex);

      final cmdHistory = List<String>.from(history[sessionId] ?? []);
      if (cmdHistory.isEmpty || cmdHistory.last != command) {
        cmdHistory.add(command);
      }
      history[sessionId] = cmdHistory;
      histIdx[sessionId] = -1;

      state = state.copyWith(commandHistory: history, historyIndex: histIdx);
    } else {
      state = state.copyWith();
    }
  }

  String? historyUp() {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return null;
    final history = state.commandHistory[sessionId] ?? [];
    if (history.isEmpty) return null;

    final histIdx = Map<String, int>.from(state.historyIndex);
    int currentIdx = histIdx[sessionId] ?? -1;
    int newIdx = (currentIdx <= 0) ? history.length - 1 : currentIdx - 1;
    histIdx[sessionId] = newIdx;
    state = state.copyWith(historyIndex: histIdx);
    return history[newIdx];
  }

  String? historyDown() {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return null;

    final histIdx = Map<String, int>.from(state.historyIndex);
    int currentIdx = histIdx[sessionId] ?? -1;

    if (currentIdx < 0) return null;

    final history = state.commandHistory[sessionId] ?? [];
    if (currentIdx >= history.length - 1) {
      histIdx[sessionId] = -1;
      state = state.copyWith(historyIndex: histIdx);
      return null;
    }

    histIdx[sessionId] = currentIdx + 1;
    state = state.copyWith(historyIndex: histIdx);
    final idx = histIdx[sessionId]!;
    return (idx >= 0 && idx < history.length) ? history[idx] : null;
  }

  void resetHistoryNavigation() {
    final sessionId = state.activeSessionId;
    if (sessionId == null) return;
    final histIdx = Map<String, int>.from(state.historyIndex);
    histIdx[sessionId] = -1;
    state = state.copyWith(historyIndex: histIdx);
  }

  void sendSigint() {
    state.activeSession?.sendSigint();
    state = state.copyWith();
  }

  Future<void> disposeAll() async {
    await _service.disposeAll();
    state = state.copyWith(
      sessions: const [],
      clearActive: true,
      commandHistory: const {},
      historyIndex: const {},
    );
  }

  void refresh() {
    state = state.copyWith(sessions: _service.sessions);
  }
}
