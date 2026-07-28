import 'dart:async';
import 'ai_client.dart';
import 'ai_message.dart';
import 'sse_parser.dart';

/// AI 服务状态
enum AiServiceStatus {
  /// 代理未启动
  proxyDown,

  /// 正在连接
  connecting,

  /// 已就绪
  ready,

  /// API Key 无效
  invalidKey,

  /// 错误状态
  error,
}

/// AI 服务配置
class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final Duration requestTimeout;
  final Duration connectTimeout;
  final int maxRetries;
  final Duration initialRetryDelay;
  final double retryBackoffMultiplier;

  const AiConfig({
    this.baseUrl = 'http://127.0.0.1:8788/v1',
    this.apiKey = 'dummy',
    this.model = 'deepseek-chat',
    this.requestTimeout = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 5),
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(seconds: 1),
    this.retryBackoffMultiplier = 2.0,
  });
}

/// 流式响应回调
typedef OnStreamChunk = void Function(String chunk);
typedef OnStreamDone = void Function(String fullContent);
typedef OnStreamError = void Function(AiClientException error);

/// AI 服务核心
///
/// 封装 [AiClient]，提供：
/// - 代理健康检查
/// - 自动重试（指数退避）
/// - 统一的错误分类
/// - 流式聊天支持
class AiService {
  final AiConfig _config;
  AiClient? _client;
  int _consecutiveFailures = 0;

  AiService({AiConfig? config}) : _config = config ?? const AiConfig();

  /// 获取或创建客户端
  AiClient _getClient() {
    _client ??= AiClient(
      config: AiClientConfig(
        baseUrl: _config.baseUrl,
        apiKey: _config.apiKey,
        model: _config.model,
        timeout: _config.requestTimeout,
        maxRetries: _config.maxRetries,
        initialRetryDelay: _config.initialRetryDelay,
      ),
    );
    return _client!;
  }

  /// 检查代理状态
  Future<AiServiceStatus> checkStatus() async {
    try {
      final healthy = await _getClient().healthCheck();
      if (healthy) {
        _consecutiveFailures = 0;
        return AiServiceStatus.ready;
      }
      return AiServiceStatus.proxyDown;
    } catch (_) {
      return AiServiceStatus.proxyDown;
    }
  }

  /// 非流式聊天（带重试）
  Future<ChatMessage> chat({
    required List<ChatMessage> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async {
    return _withRetry(
      () async {
        final response = await _getClient().chat(
          messages: messages,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        final choice = response.choices.isNotEmpty ? response.choices.first : null;
        if (choice == null) {
          throw const AiClientException(
            type: AiClientErrorType.api,
            message: 'API 返回空响应',
          );
        }
        return choice.message;
      },
    );
  }

  /// 流式聊天（带重试）
  ///
  /// 通过回调逐 chunk 返回内容。自动处理重连。
  Future<ChatMessage> chatStream({
    required List<ChatMessage> messages,
    required OnStreamChunk onChunk,
    OnStreamDone? onDone,
    OnStreamError? onError,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async {
    final buffer = StringBuffer();
    int retryCount = 0;
    Duration retryDelay = _config.initialRetryDelay;

    while (retryCount <= _config.maxRetries) {
      try {
        final completer = Completer<ChatMessage>();
        final stream = _getClient().chatStream(
          messages: messages,
          temperature: temperature,
          maxTokens: maxTokens,
        );

        int eventCount = 0;
        stream.listen(
          (event) {
            switch (event.type) {
              case SseEventType.data:
                final chunk = event.content;
                if (chunk.isNotEmpty) {
                  buffer.write(chunk);
                  onChunk(chunk);
                  eventCount++;
                }
                break;
              case SseEventType.done:
                // 流结束
                break;
              case SseEventType.error:
                onError?.call(AiClientException(
                  type: AiClientErrorType.api,
                  message: event.errorMessage ?? 'SSE 解析错误',
                ));
                break;
            }
          },
          onError: (e) {
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              final content = buffer.toString();
              if (content.isEmpty && eventCount == 0) {
                completer.completeError(const AiClientException(
                  type: AiClientErrorType.api,
                  message: '流式响应为空',
                ));
              } else {
                completer.complete(ChatMessage(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  role: ChatRole.assistant,
                  content: content,
                  timestamp: DateTime.now(),
                ));
              }
            }
          },
        );

        final result = await completer.future;
        _consecutiveFailures = 0;
        onDone?.call(result.content);
        return result;
      } catch (e) {
        retryCount++;
        _consecutiveFailures++;

        if (retryCount > _config.maxRetries) {
          if (e is AiClientException) rethrow;
          throw AiClientException(
            type: AiClientErrorType.network,
            message: '流式聊天失败（已重试 $_consecutiveFailures 次）: $e',
          );
        }

        // 指数退避
        await Future.delayed(retryDelay);
        retryDelay = Duration(
          milliseconds: (retryDelay.inMilliseconds * _config.retryBackoffMultiplier).toInt(),
        );
      }
    }

    throw const AiClientException(
      type: AiClientErrorType.network,
      message: '流式聊天失败（超过最大重试次数）',
    );
  }

  /// 带重试的通用方法
  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    int retryCount = 0;
    Duration retryDelay = _config.initialRetryDelay;

    while (true) {
      try {
        final result = await fn();
        _consecutiveFailures = 0;
        return result;
      } catch (e) {
        retryCount++;
        _consecutiveFailures++;

        // 非可重试错误直接抛出
        if (e is AiClientException) {
          switch (e.type) {
            case AiClientErrorType.api:
              rethrow;
            case AiClientErrorType.rateLimit:
              // 429 需要更长的等待
              if (retryCount > _config.maxRetries) rethrow;
              await Future.delayed(retryDelay * 2);
              continue;
            default:
              break;
          }
        }

        if (retryCount > _config.maxRetries) {
          if (e is AiClientException) rethrow;
          throw AiClientException(
            type: AiClientErrorType.network,
            message: '操作失败（已重试 $retryCount 次）: $e',
          );
        }

        await Future.delayed(retryDelay);
        retryDelay = Duration(
          milliseconds: (retryDelay.inMilliseconds * _config.retryBackoffMultiplier).toInt(),
        );
      }
    }
  }

  /// 释放资源
  void dispose() {
    _client?.dispose();
    _client = null;
  }
}
