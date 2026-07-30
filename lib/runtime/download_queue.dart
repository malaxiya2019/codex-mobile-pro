/// ====================================================================
/// 下载队列调度器（P4）
///
/// 参照 Firecrawl 的 concurrency-queue-reconciler + NuQ 双后端队列：
/// - 优先级排序（critical → background）
/// - 并发控制（网络质量感知）
/// - Backlog 持久化（应用重启后恢复未完成下载）
/// - 依赖检查
/// ====================================================================

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/logger/log_service.dart';
import 'artifact_manager.dart';
import 'deploy_error.dart';
import 'runtime_manifest.dart';

// ====================================================================
// 类型定义
// ====================================================================

/// 安装任务优先级
enum InstallPriority {
  critical,  // 内核级（Termux 环境本身）
  high,      // 核心运行时（Node.js / Ubuntu rootfs）
  normal,    // 工具（Git / Python）
  low,       // 可选组件
  background, // 后台预取
}

/// 优先级数值映射（越大越优先）
int priorityValue(InstallPriority p) => switch (p) {
  InstallPriority.critical => 100,
  InstallPriority.high => 80,
  InstallPriority.normal => 60,
  InstallPriority.low => 40,
  InstallPriority.background => 20,
};

/// 下载任务状态
enum DownloadJobStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

/// 下载任务
class DownloadJob {
  final String id;
  final String label;
  final InstallPriority priority;
  final DateTime createdAt;

  /// 要下载的 artifact
  final RuntimeArtifact artifact;

  /// 目标目录
  final String targetDir;

  /// 区域偏好
  final String region;

  /// DNS 是否正常
  final bool dnsWorking;

  /// 前置依赖（工具名列表）
  final List<String> dependencies;

  DownloadJobStatus status;
  DeployError? lastError;
  int retryCount;
  int maxRetries;

  DownloadJob({
    required this.id,
    required this.label,
    this.priority = InstallPriority.normal,
    DateTime? createdAt,
    required this.artifact,
    required this.targetDir,
    this.region = '',
    this.dnsWorking = true,
    this.dependencies = const [],
    this.status = DownloadJobStatus.pending,
    this.lastError,
    this.retryCount = 0,
    this.maxRetries = 3,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 是否应该重试
  bool get shouldRetry =>
      status == DownloadJobStatus.failed &&
      retryCount < maxRetries &&
      lastError?.isRetryable == true;

  /// 剩余尝试次数
  int get remainingAttempts => maxRetries - retryCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'priority': priority.name,
        'createdAt': createdAt.toIso8601String(),
        'artifactName': artifact.name,
        'artifactUrl': artifact.url,
        'artifactType': artifact.type.name,
        'targetDir': targetDir,
        'region': region,
        'status': status.name,
        'retryCount': retryCount,
        'maxRetries': maxRetries,
      };

  factory DownloadJob.fromJson(Map<String, dynamic> json) => DownloadJob(
        id: json['id'] as String,
        label: json['label'] as String,
        priority: InstallPriority.values.byName(json['priority'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        artifact: RuntimeArtifact(
          name: json['artifactName'] as String,
          type: ArtifactType.values.byName(json['artifactType'] as String? ?? 'deb'),
          url: json['artifactUrl'] as String,
          size: json['size'] as int? ?? 0,
          sha256: json['sha256'] as String? ?? '',
        ),
        targetDir: json['targetDir'] as String,
        region: json['region'] as String? ?? '',
        status: DownloadJobStatus.values.byName(json['status'] as String),
        retryCount: json['retryCount'] as int? ?? 0,
        maxRetries: json['maxRetries'] as int? ?? 3,
      );
}

/// 下载进度事件
class DownloadProgressEvent {
  final String jobId;
  final String label;
  final double progress; // 0.0 ~ 1.0
  final String message;
  final DownloadJobStatus status;

  const DownloadProgressEvent({
    required this.jobId,
    required this.label,
    required this.progress,
    required this.message,
    required this.status,
  });
}

// ====================================================================
// 下载队列调度器
// ====================================================================

/// 下载队列调度器（参照 Firecrawl NuQ 简化版）
class DownloadQueueScheduler {
  static DownloadQueueScheduler? _instance;

  /// 全局单例
  static DownloadQueueScheduler get instance =>
      _instance ??= DownloadQueueScheduler._();

  DownloadQueueScheduler._();

  /// 待处理队列
  final Queue<DownloadJob> _queue = Queue();

  /// 依赖等待队列
  final List<DownloadJob> _dependencyQueue = [];

  /// 正在运行的任务
  final Map<String, DownloadJob> _activeJobs = {};

  /// 已完成的任务
  final List<DownloadJob> _completedJobs = [];

  /// 最大并发数
  int _maxConcurrent = 3;

  /// 当前是否在处理
  bool _isProcessing = false;

  /// 进度监听器
  final List<void Function(DownloadProgressEvent)> _listeners = [];

  /// Backlog 文件路径
  String? _backlogDir;

  // ==================================================================
  // 公共 API
  // ==================================================================

  /// 初始化（设置 backlog 持久化目录）
  Future<void> initialize({String? backlogDir}) async {
    _backlogDir = backlogDir;
    if (_backlogDir != null) {
      await Directory(_backlogDir!).create(recursive: true);
    }
    LogService.info('DownloadQueue', '调度器初始化完成 (maxConcurrent=$_maxConcurrent)');
  }

  /// 添加进度监听
  void addListener(void Function(DownloadProgressEvent) listener) {
    _listeners.add(listener);
  }

  /// 移除进度监听
  void removeListener(void Function(DownloadProgressEvent) listener) {
    _listeners.remove(listener);
  }

  /// 通知所有监听器
  void _notify(DownloadProgressEvent event) {
    for (final listener in _listeners) {
      listener(event);
    }
  }

  /// 入队一个下载任务
  void enqueue(DownloadJob job) {
    // 检查是否已存在相同任务
    if (_isDuplicate(job)) {
      LogService.info('DownloadQueue', '跳过重复任务: ${job.label}');
      return;
    }

    // 检查依赖
    if (!_dependenciesSatisfied(job)) {
      LogService.info('DownloadQueue', '${job.label} 等待依赖...');
      _dependencyQueue.add(job);
      return;
    }

    _queue.add(job);
    LogService.info('DownloadQueue', '入队: ${job.label} (pri=${job.priority.name})');

    if (!_isProcessing) {
      _processNext();
    }
  }

  /// 批量入队
  void enqueueAll(List<DownloadJob> jobs) {
    for (final job in jobs) {
      enqueue(job);
    }
  }

  /// 获取当前队列状态
  DownloadQueueStatus get status => DownloadQueueStatus(
        pendingCount: _queue.length,
        activeCount: _activeJobs.length,
        dependencyCount: _dependencyQueue.length,
        completedCount: _completedJobs.length,
        maxConcurrent: _maxConcurrent,
      );

  /// 恢复 Backlog——应用重启后扫描未完成下载
  Future<int> recoverBacklog() async {
    if (_backlogDir == null) return 0;

    try {
      final dir = Directory(_backlogDir!);
      if (!await dir.exists()) return 0;

      int recovered = 0;
      await for (final file in dir.list()) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final job = DownloadJob.fromJson(json);

            if (job.status == DownloadJobStatus.pending ||
                job.status == DownloadJobStatus.running) {
              job.status = DownloadJobStatus.pending;
              job.retryCount = 0;
              enqueue(job);
              recovered++;
              LogService.info('DownloadQueue', '恢复 Backlog: ${job.label}');
            }
          } catch (e) {
            LogService.warning('DownloadQueue', 'Backlog 文件解析失败: $e');
          }
        }
      }
      return recovered;
    } catch (e) {
      LogService.warning('DownloadQueue', 'Backlog 恢复失败: $e');
      return 0;
    }
  }

  /// 取消所有等待中的任务
  void cancelPending() {
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      job.status = DownloadJobStatus.cancelled;
    }
    LogService.info('DownloadQueue', '已取消 ${_queue.length} 个等待中的任务');
  }

  // ==================================================================
  // 内部逻辑
  // ==================================================================

  /// 检查重复任务
  bool _isDuplicate(DownloadJob job) {
    // 检查队列中
    for (final q in _queue) {
      if (q.id == job.id) return true;
    }
    // 检查正在运行的
    if (_activeJobs.containsKey(job.id)) return true;
    // 检查已完成的
    for (final c in _completedJobs) {
      if (c.id == job.id && c.status == DownloadJobStatus.completed) {
        return true;
      }
    }
    return false;
  }

  /// 检查依赖是否满足
  bool _dependenciesSatisfied(DownloadJob job) {
    if (job.dependencies.isEmpty) return true;
    for (final depId in job.dependencies) {
      final satisfied = _completedJobs.any(
        (j) => j.id == depId && j.status == DownloadJobStatus.completed,
      );
      if (!satisfied) return false;
    }
    return true;
  }

  /// 处理下一个任务
  Future<void> _processNext() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_queue.isNotEmpty || _dependencyQueue.isNotEmpty) {
      // 重新检查依赖队列
      _recheckDependencyQueue();

      // 如果队列为空或达到并发上限，等待
      while (_queue.isEmpty && _dependencyQueue.isEmpty) {
        _isProcessing = false;
        return;
      }

      if (_activeJobs.length >= _maxConcurrent) {
        // 并发已满，稍后重试
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      // 取出最高优先级任务
      final job = _dequeueHighestPriority();
      if (job == null) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      _activeJobs[job.id] = job;
      _executeJob(job);
    }

    _isProcessing = false;
    LogService.info('DownloadQueue', '所有任务已完成');
  }

  /// 取出最高优先级的任务
  DownloadJob? _dequeueHighestPriority() {
    if (_queue.isEmpty) return null;

    // 找到最高优先级的任务
    DownloadJob? best;
    for (final job in _queue) {
      if (best == null ||
          priorityValue(job.priority) > priorityValue(best.priority) ||
          (priorityValue(job.priority) == priorityValue(best.priority) &&
              job.createdAt.isBefore(best.createdAt))) {
        best = job;
      }
    }

    if (best != null) {
      _queue.remove(best);
    }
    return best;
  }

  /// 重新检查依赖队列
  void _recheckDependencyQueue() {
    final stillWaiting = <DownloadJob>[];
    for (final job in _dependencyQueue) {
      if (_dependenciesSatisfied(job)) {
        _queue.add(job);
        LogService.info('DownloadQueue', '依赖满足，加入队列: ${job.label}');
      } else {
        stillWaiting.add(job);
      }
    }
    _dependencyQueue
      ..clear()
      ..addAll(stillWaiting);
  }

  /// 执行单个任务
  Future<void> _executeJob(DownloadJob job) async {
    job.status = DownloadJobStatus.running;
    LogService.info('DownloadQueue', '开始: ${job.label}');
    _notify(DownloadProgressEvent(
      jobId: job.id,
      label: job.label,
      progress: 0,
      message: '下载 ${job.label}...',
      status: DownloadJobStatus.running,
    ));

    try {
      await ArtifactManager.downloadAndExtract(
        artifact: job.artifact,
        targetDir: job.targetDir,
        region: job.region,
        dnsWorking: job.dnsWorking,
        onProgress: (downloaded, total, message) {
          final progress = total > 0 ? downloaded / total : 0.0;
          _notify(DownloadProgressEvent(
            jobId: job.id,
            label: job.label,
            progress: progress,
            message: message,
            status: DownloadJobStatus.running,
          ));
        },
      );

      job.status = DownloadJobStatus.completed;
      _completedJobs.add(job);
      LogService.info('DownloadQueue', '完成: ${job.label}');

      _notify(DownloadProgressEvent(
        jobId: job.id,
        label: job.label,
        progress: 1.0,
        message: '${job.label} 完成',
        status: DownloadJobStatus.completed,
      ));

      // 删除 Backlog 文件
      await _removeBacklog(job.id);
    } catch (e) {
      job.lastError = e is DeployError ? e : DeployError(
        code: DeployErrorCode.unknown,
        message: e.toString(),
      );
      job.retryCount++;

      if (job.shouldRetry) {
        job.status = DownloadJobStatus.pending;
        _queue.addFirst(job);
        LogService.info('DownloadQueue',
            '${job.label} 失败, 等待重试 (${job.remainingAttempts} 次剩余)');

        _notify(DownloadProgressEvent(
          jobId: job.id,
          label: job.label,
          progress: 0,
          message: '${job.label} 失败，等待重试...',
          status: DownloadJobStatus.pending,
        ));
      } else {
        job.status = DownloadJobStatus.failed;
        LogService.warning('DownloadQueue',
            '失败: ${job.label} — ${job.lastError?.message}');

        _notify(DownloadProgressEvent(
          jobId: job.id,
          label: job.label,
          progress: 0,
          message: '${job.label} 失败: ${job.lastError?.message}',
          status: DownloadJobStatus.failed,
        ));

        // 持久化失败状态
        await _persistBacklog(job);
      }
    } finally {
      _activeJobs.remove(job.id);
    }

    // 继续下一个任务
    _processNext();
  }

  // ==================================================================
  // Backlog 持久化
  // ==================================================================

  /// 持久化未完成任务
  Future<void> _persistBacklog(DownloadJob job) async {
    if (_backlogDir == null) return;
    if (job.status == DownloadJobStatus.completed) return;

    try {
      final file = File(path.join(_backlogDir!, '${job.id}.json'));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(job.toJson()),
      );
      LogService.info('DownloadQueue', 'Backlog 已保存: ${job.id}');
    } catch (e) {
      LogService.warning('DownloadQueue', 'Backlog 持久化失败: $e');
    }
  }

  /// 删除 Backlog 文件
  Future<void> _removeBacklog(String jobId) async {
    if (_backlogDir == null) return;
    try {
      final file = File(path.join(_backlogDir!, '$jobId.json'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

// ====================================================================
// 队列状态（供 UI 展示）
// ====================================================================

/// 下载队列状态
class DownloadQueueStatus {
  final int pendingCount;
  final int activeCount;
  final int dependencyCount;
  final int completedCount;
  final int maxConcurrent;

  const DownloadQueueStatus({
    required this.pendingCount,
    required this.activeCount,
    required this.dependencyCount,
    required this.completedCount,
    required this.maxConcurrent,
  });

  int get totalJobs =>
      pendingCount + activeCount + dependencyCount + completedCount;
}
