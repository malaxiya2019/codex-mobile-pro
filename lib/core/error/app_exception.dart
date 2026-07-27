/// 应用异常基类
///
/// 统一项目中的异常类型，便于错误处理和用户提示。
sealed class AppException implements Exception {
  final String code;
  final String message;
  final Object? originalError;

  const AppException({
    required this.code,
    required this.message,
    this.originalError,
  });

  @override
  String toString() => '[$code] $message';
}

/// 网络异常
class NetworkException extends AppException {
  const NetworkException({super.message = '网络连接失败', super.originalError})
    : super(code: 'E_NET');
}

/// API 异常
class ApiException extends AppException {
  const ApiException({super.message = 'API 请求异常', super.originalError})
    : super(code: 'E_API');
}

/// 命令执行异常
class ExecException extends AppException {
  final int? exitCode;
  final String? stderr;

  const ExecException({
    super.message = '命令执行失败',
    this.exitCode,
    this.stderr,
    super.originalError,
  }) : super(code: 'E_EXEC');
}

/// 文件操作异常
class FileException extends AppException {
  const FileException({super.message = '文件操作失败', super.originalError})
    : super(code: 'E_FILE');
}

/// 配置异常
class ConfigException extends AppException {
  const ConfigException({super.message = '配置异常', super.originalError})
    : super(code: 'E_CFG');
}

/// 权限异常
class PermissionException extends AppException {
  const PermissionException({super.message = '权限不足', super.originalError})
    : super(code: 'E_PERM');
}
