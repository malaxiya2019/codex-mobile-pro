import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ai_message.dart';
import 'sse_parser.dart';

/// AI 客户端错误类型
enum AiClientErrorType {
  /// 网络连接失败
  network,

  /// API 返回错误（如 Key 无效）
  api,

  /// 请求超时
  timeout,

  /// 服务端错误（5xx）
  server,

  /// 频率限制（429）
  rateLimit,

  /// 代理未运行
  proxyDown,

  /// 未知错误
  unknown,
}

/// AI 客户端异常
class AiClientException implements Exception {
  final AiClientErrorType type;
  final String message;
  final int? statusCode;
  final String? responseBody;

  const AiClientException({
    required this.type,
    required this.message,
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() => '[${type.name}] $message (HTTP $statusCode)';
}

/// AI 客户端配置
class AiClientConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final Duration timeout;
  final int maxRetries;
  final Duration initialRetryDelay;

  const AiClientConfig({
    this.baseUrl = 'http://127.0.0.1:8788/v1',
    this.apiKey = 'dummy',
    this.model = 'deepseek-chat',
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(seconds: 1),
  });
}

/// OpenAI 兼容 API 客户端
class AiClient {
  final AiClientConfig config;
  final http.Client _httpClient;

  AiClient({AiClientConfig? config, http.Client? httpClient})
      : config = config ?? const AiClientConfig(),
        _httpClient = httpClient ?? http.Client();

  /// 非流式聊天完成
  Future<ChatCompletionResponse> chat({
    required List<ChatMessage> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async {
    final request = ChatCompletionRequest(
      model: config.model,
      messages: messages,
      stream: false,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    final uri = Uri.parse('${config.baseUrl}/chat/completions');
    try {
      final response = await _httpClient
          .post(
            uri,
            headers: _buildHeaders(),
            body: jsonEncode(request.toJson()),
          )
          .timeout(config.timeout);

      if (response.statusCode == 200) {
        return ChatCompletionResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      throw _classifyError(response.statusCode, response.body);
    } on TimeoutException {
      throw AiClientException(
        type: AiClientErrorType.timeout,
        message: '请求超时（${config.timeout.inSeconds}秒）',
      );
    } catch (e) {
      if (e is AiClientException) rethrow;
      if (e is http.ClientException) {
        throw AiClientException(
          type: AiClientErrorType.network,
          message: '网络连接失败: ${e.message}',
        );
      }
      rethrow;
    }
  }

  /// 流式聊天完成
  ///
  /// 返回 SSE 事件流，调用方逐事件处理。
  Stream<SseEvent> chatStream({
    required List<ChatMessage> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) {
    final request = ChatCompletionRequest(
      model: config.model,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    final uri = Uri.parse('${config.baseUrl}/chat/completions');

    final controller = StreamController<SseEvent>();

    _httpClient
        .send(
          http.Request('POST', uri)
            ..headers.addAll(_buildHeaders())
            ..body = jsonEncode(request.toJson()),
        )
        .then((response) {
          if (response.statusCode != 200) {
            response.stream.transform(utf8.decoder).listen(
              (body) {
                controller.addError(_classifyError(response.statusCode, body));
                controller.close();
              },
            );
            return;
          }

          response.stream
              .transform(SseParser().byteTransformer)
              .listen(
                (event) => controller.add(event),
                onError: (e) => controller.addError(e),
                onDone: () => controller.close(),
              );
        })
        .catchError((e) {
          if (e is http.ClientException) {
            controller.addError(AiClientException(
              type: AiClientErrorType.network,
              message: '网络连接失败: ${e.message}',
            ));
          } else if (e is TimeoutException) {
            controller.addError(const AiClientException(
              type: AiClientErrorType.timeout,
              message: '流式请求超时',
            ));
          } else {
            controller.addError(e);
          }
          controller.close();
        });

    return controller.stream;
  }

  /// 健康检查
  ///
  /// 使用 OpenAI 兼容标准的 `GET /v1/models` 作为存在性探测。
  /// 历史 bug：探测的是非标准的 `/health`，而本地代理（mimo2codex）没有
  /// 该路由返回 404 → 健康检查永远失败 → DeepSeekProvider 永不 ready →
  /// streamChat 直接返回空流 → ChatEngine 显示「⚠️ 未收到有效回复」。
  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('${config.baseUrl}/models');
      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 构建 HTTP 头
  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
      'Accept': 'text/event-stream',
    };
  }

  /// 根据 HTTP 状态码分类错误
  AiClientException _classifyError(int statusCode, String body) {
    switch (statusCode) {
      case 401:
      case 403:
        return const AiClientException(
          type: AiClientErrorType.api,
          message: 'API Key 无效，请检查配置',
          statusCode: 401,
        );
      case 429:
        return const AiClientException(
          type: AiClientErrorType.rateLimit,
          message: '请求过于频繁，请稍后重试',
          statusCode: 429,
        );
      case 502:
      case 503:
        return const AiClientException(
          type: AiClientErrorType.proxyDown,
          message: 'mimo2codex 代理不可用',
          statusCode: 503,
        );
      default:
        if (statusCode >= 500) {
          return AiClientException(
            type: AiClientErrorType.server,
            message: '服务端错误 (HTTP $statusCode)',
            statusCode: statusCode,
            responseBody: body,
          );
        }
        return AiClientException(
          type: AiClientErrorType.api,
          message: 'API 返回错误 (HTTP $statusCode)',
          statusCode: statusCode,
          responseBody: body,
        );
    }
  }

  /// 释放资源
  void dispose() {
    _httpClient.close();
  }
}
