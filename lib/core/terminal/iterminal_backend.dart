/// 终端后端接口
///
/// 定义终端后端的统一抽象接口。
/// 支持两种实现：
///   1. ProcessTerminalBackend — 使用 Dart Process.start()（现有）
///   2. NativePtyBackend — 使用 Native PTY（新增）
abstract class ITerminalBackend {
  /// 后端名称（用于日志和调试）
  String get name;

  /// 后端描述
  String get description;

  /// 创建新终端会话
  Future<SessionHandle> createSession({
    required String shellPath,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  });

  /// 销毁所有会话
  Future<void> disposeAll();
}

/// 会话句柄
///
/// 封装终端会话的读写操作，统一接口。
abstract class SessionHandle {
  /// 会话唯一标识
  String get id;

  /// 会话是否存活
  bool get isAlive;

  /// 进程 PID（如果可用）
  int? get pid;

  /// 写入数据到终端
  void write(String text);

  /// 发送 Ctrl+C
  void sendSigint();

  /// 发送 Ctrl+D
  void sendEof();

  /// 调整终端大小
  void resize(int rows, int cols);

  /// 关闭会话
  Future<void> close();

  /// 输出流（ANIS 文本行）
  Stream<String> get outputStream;

  /// 错误流
  Stream<String> get errorStream;
}
