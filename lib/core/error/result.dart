/// Result 模式 — 显式处理成功/失败
///
/// Service 层统一返回 Result 类型，调用方必须处理两种情况。
sealed class Result<T> {
  const Result();
}

/// 成功结果
class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

/// 失败结果
class Failure<T> extends Result<T> {
  final AppException error;
  const Failure(this.error);
}
