package com.codexmobile.app

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Bundle
import android.app.PendingIntent
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Termux 通信桥
 *
 * 混合策略：
 * 1. 系统 Shell（/system/bin/sh）— 用于交互式终端和降级
 * 2. Termux RUN_COMMAND Intent — 用于一键命令执行（Node/Git/Python 检测等）
 *
 * 通过 PendingIntent + BroadcastReceiver 接收 Termux 执行结果。
 */
class TermuxBridge(private val context: Context? = null) {

    companion object {
        private const val TAG = "TermuxBridge"
        const val CHANNEL = "com.codexmobile.app/termux"
        const val RESULT_ACTION_PREFIX = "com.codexmobile.app.TERMUX_RESULT_"

        // Termux 包名和路径
        private const val TERMUX_PKG = "com.termux"
        private const val TERMUX_BASH = "/data/data/com.termux/files/usr/bin/bash"

        // 系统 shell
        private const val SYSTEM_SH = "/system/bin/sh"

        // RUN_COMMAND Intent extras
        private const val TERMUX_RUN_COMMAND_ACTION = "com.termux.RUN_COMMAND"
        private const val TERMUX_RUN_COMMAND_SERVICE =
            "com.termux.app.RunCommandService"
        private const val EXTRA_COMMAND_PATH =
            "com.termux.RUN_COMMAND_PATH"
        private const val EXTRA_ARGUMENTS =
            "com.termux.RUN_COMMAND_ARGUMENTS"
        private const val EXTRA_BACKGROUND =
            "com.termux.RUN_COMMAND_BACKGROUND"
        private const val EXTRA_PENDING_INTENT =
            "com.termux.RUN_COMMAND_PENDING_INTENT"

        // Result bundle keys (from TermuxPluginUtils)
        private const val RESULT_BUNDLE_KEY = "result"
        private const val RESULT_STDOUT_KEY = "stdout"
        private const val RESULT_STDERR_KEY = "stderr"
        private const val RESULT_EXIT_CODE_KEY = "exitCode"
        private const val RESULT_ERR_KEY = "err"

        private const val TIMEOUT_MS = 30_000L
    }

    // 工作目录缓存
    private var _workDir: java.io.File? = null

    // 存储等待结果的 latches（key: requestId）
    private val pendingRequests = ConcurrentHashMap<String, PendingRequest>()

    // 已注册的 BroadcastReceiver（防止重复注册）
    private var receiverRegistered = false
    private val resultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            val requestId = intent.getStringExtra("request_id") ?: return
            Log.d(TAG, "收到 Termux 结果: requestId=$requestId")

            val pending = pendingRequests.remove(requestId)
            if (pending == null) {
                Log.w(TAG, "找不到请求: $requestId（可能已超时）")
                return
            }

            val bundle = intent.getBundleExtra(RESULT_BUNDLE_KEY)
            if (bundle != null) {
                val stdout = bundle.getString(RESULT_STDOUT_KEY) ?: ""
                val stderr = bundle.getString(RESULT_STDERR_KEY) ?: ""
                val exitCode = bundle.getInt(RESULT_EXIT_CODE_KEY, -1)
                pending.result = TermuxResult(
                    exitCode = exitCode,
                    stdout = stdout,
                    stderr = stderr
                )
            } else {
                // 直接检查 intent extras（某些 Termux 版本可能不同）
                val stdout = intent.getStringExtra(RESULT_STDOUT_KEY) ?: ""
                val stderr = intent.getStringExtra(RESULT_STDERR_KEY) ?: ""
                val exitCode = intent.getIntExtra(RESULT_EXIT_CODE_KEY, -1)
                pending.result = TermuxResult(
                    exitCode = exitCode,
                    stdout = stdout,
                    stderr = stderr
                )
            }
            pending.latch.countDown()
        }
    }

    data class TermuxResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String
    )

    data class PendingRequest(
        val latch: CountDownLatch,
        var result: TermuxResult? = null
    )

    // ──────────────────────────────────────────────
    // 初始化
    // ──────────────────────────────────────────────

    /** 注册 BroadcastReceiver（线程安全） */
    fun ensureReceiverRegistered() {
        if (receiverRegistered || context == null) return
        try {
            val filter = IntentFilter().apply {
                addAction(RESULT_ACTION_PREFIX + "*")
                // 为了确保能接收到，使用前缀匹配
            }
            // 实际上 BroadcastReceiver 只能通过精确 action 匹配
            // 我们将在发送时动态注册/取消注册
            Log.d(TAG, "BroadcastReceiver 注册准备就绪")
        } catch (e: Exception) {
            Log.e(TAG, "注册 BroadcastReceiver 失败", e)
        }
    }

    /**
     * 发送 Termux RUN_COMMAND Intent 并等待结果
     */
    private fun executeInTermuxInternal(command: String): TermuxResult? {
        if (context == null) return null

        val requestId = UUID.randomUUID().toString()
        val action = RESULT_ACTION_PREFIX + requestId
        val latch = CountDownLatch(1)
        val pending = PendingRequest(latch = latch)
        pendingRequests[requestId] = pending

        try {
            // 1. 注册动态 BroadcastReceiver
            val filter = IntentFilter(action)
            context.registerReceiver(resultReceiver, filter,
                Context.RECEIVER_EXPORTED)

            // 2. 创建 PendingIntent
            val resultIntent = Intent(action).apply {
                putExtra("request_id", requestId)
                // 设置 ComponentName 确保只发送到我们自己
                setPackage(context.packageName)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestId.hashCode(),
                resultIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
            )

            // 3. 创建 RUN_COMMAND Intent
            val runIntent = Intent(TERMUX_RUN_COMMAND_ACTION).apply {
                component = ComponentName(
                    TERMUX_PKG,
                    TERMUX_RUN_COMMAND_SERVICE
                )
                putExtra(EXTRA_COMMAND_PATH, TERMUX_BASH)
                putExtra(EXTRA_ARGUMENTS, arrayOf("-c", command))
                putExtra(EXTRA_BACKGROUND, true)
                putExtra(EXTRA_PENDING_INTENT, pendingIntent)
            }

            // 4. 启动 Termux RunCommandService
            Log.d(TAG, "发送 RUN_COMMAND: requestId=$requestId, command=$command")
            context.startService(runIntent)

            // 5. 等待结果（超时 TIMEOUT_MS）
            val received = latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)
            if (!received) {
                Log.w(TAG, "Termux 命令超时: $command")
                pendingRequests.remove(requestId)
                return null
            }

            return pending.result
        } catch (e: Exception) {
            Log.e(TAG, "RUN_COMMAND 失败: ${e.message}")
            pendingRequests.remove(requestId)
            return null
        } finally {
            try {
                context.unregisterReceiver(resultReceiver)
            } catch (_: Exception) {
                // 可能已取消注册
            }
        }
    }

    // ──────────────────────────────────────────────
    // 对外 API
    // ──────────────────────────────────────────────

    /**
     * 在 Termux 环境中执行命令
     * 如果 Termux 不可用则降级到系统 shell
     */
    fun executeCommand(command: String): ExecResult {
        Log.d(TAG, "执行命令: $command")
        val startTime = System.currentTimeMillis()

        // 策略 1: 尝试 Termux RUN_COMMAND
        if (isPackageInstalled(TERMUX_PKG)) {
            try {
                val termuxResult = executeInTermuxInternal(command)
                if (termuxResult != null) {
                    val duration = System.currentTimeMillis() - startTime
                    Log.d(TAG, "  [Termux] exitCode=${termuxResult.exitCode}, ${duration}ms")
                    return ExecResult(
                        exitCode = termuxResult.exitCode,
                        stdout = termuxResult.stdout,
                        stderr = termuxResult.stderr,
                        durationMs = duration,
                        source = "termux"
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "  Termux 执行失败，降级到系统 shell: ${e.message}")
            }
        } else {
            Log.d(TAG, "  Termux 未安装，使用系统 shell")
        }

        // 策略 2: 系统 shell 降级
        Log.d(TAG, "  [System Shell] 执行命令")
        return tryExec(SYSTEM_SH, command, startTime) ?: ExecResult(
            exitCode = -1,
            stdout = "",
            stderr = "无法执行命令：Termux 和系统 shell 都不可用",
            durationMs = System.currentTimeMillis() - startTime,
            source = "error"
        )
    }

    /**
     * 检查环境
     */
    fun checkEnvironment(): Map<String, Any> {
        val checks = linkedMapOf<String, Any>()

        // 1. Termux 是否安装
        val termuxInstalled = isPackageInstalled(TERMUX_PKG)
        checks["termux_installed"] = termuxInstalled

        // 2. RUN_COMMAND Intent 是否可用
        val intentAvailable = canSendTermuxIntent()
        checks["termux_intent_available"] = intentAvailable

        // 3. 测试 Termux 命令执行
        if (intentAvailable) {
            try {
                val result = executeInTermuxInternal("echo 'termux_ok'")
                val works = result != null &&
                        result.exitCode == 0 &&
                        result.stdout.trim() == "termux_ok"
                checks["termux_works"] = works
                checks["termux_last_stderr"] =
                    if (result != null) result.stderr.take(200) else "null"
            } catch (e: Exception) {
                checks["termux_works"] = false
                checks["termux_last_stderr"] = e.message?.take(200) ?: "unknown"
            }
        } else {
            checks["termux_works"] = false
            checks["termux_last_stderr"] = "RUN_COMMAND Intent 不可用"
        }

        // 4. 系统 shell
        val shResult = tryExec(SYSTEM_SH, "echo 'sh_ok'", System.currentTimeMillis())
        checks["sh_works"] = shResult != null &&
                shResult.exitCode == 0 &&
                shResult.stdout.trim() == "sh_ok"
        checks["sh_last_stderr"] = shResult?.stderr?.take(200) ?: "N/A"

        // 5. 整体状态
        val isAvailable = termuxInstalled &&
                (checks["termux_works"] == true ||
                        checks["termux_intent_available"] == true)
        checks["is_available"] = isAvailable
        checks["fallback_available"] = (checks["sh_works"] == true)

        return checks
    }

    /**
     * 处理 MethodChannel 调用
     */
    fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "execute" -> {
                val command = call.argument<String>("command") ?: ""
                if (command.isBlank()) {
                    result.error("INVALID_ARGUMENT", "命令不能为空", null)
                    return
                }
                val execResult = executeCommand(command)
                result.success(mapOf(
                    "exitCode" to execResult.exitCode,
                    "stdout" to execResult.stdout,
                    "stderr" to execResult.stderr,
                    "durationMs" to execResult.durationMs,
                    "source" to execResult.source
                ))
            }
            "checkEnvironment" -> {
                result.success(checkEnvironment())
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // ──────────────────────────────────────────────
    // 内部方法
    // ──────────────────────────────────────────────

    private fun getWorkDir(): java.io.File {
        if (_workDir == null) {
            _workDir = try {
                context?.cacheDir?.also {
                    Log.d(TAG, "工作目录（cacheDir）: ${it.absolutePath}")
                }
            } catch (_: Exception) { null }
            if (_workDir == null) {
                _workDir = try {
                    context?.filesDir?.also {
                        Log.d(TAG, "工作目录（filesDir）: ${it.absolutePath}")
                    }
                } catch (_: Exception) { null }
            }
            if (_workDir == null) {
                _workDir = java.io.File("/data/local/tmp").also {
                    it.mkdirs()
                    Log.d(TAG, "工作目录（/data/local/tmp）: ${it.absolutePath}")
                }
            }
        }
        return _workDir!!
    }

    /**
     * 使用系统 shell 执行命令（降级方案）
     */
    private fun tryExec(shell: String, command: String, startTime: Long): ExecResult? {
        return try {
            val process = ProcessBuilder(shell, "-c", command)
                .directory(getWorkDir())
                .redirectErrorStream(false)
                .start()

            val finished = process.waitFor(TIMEOUT_MS, TimeUnit.MILLISECONDS)
            if (!finished) {
                process.destroyForcibly()
                return ExecResult(
                    exitCode = -1,
                    stdout = "",
                    stderr = "命令执行超时（${TIMEOUT_MS}ms）",
                    durationMs = System.currentTimeMillis() - startTime,
                    source = "timeout"
                )
            }

            val stdout = readStream(process.inputStream)
            val stderr = readStream(process.errorStream)
            val exitCode = process.exitValue()
            val duration = System.currentTimeMillis() - startTime

            Log.d(TAG, "[$shell] exitCode=$exitCode, duration=${duration}ms")
            ExecResult(
                exitCode = exitCode,
                stdout = stdout,
                stderr = stderr,
                durationMs = duration,
                source = "system_sh"
            )
        } catch (e: Exception) {
            Log.w(TAG, "[$shell] 执行失败: ${e.message}")
            null
        }
    }

    private fun isPackageInstalled(pkgName: String): Boolean {
        return try {
            context?.packageManager?.getPackageInfo(pkgName, 0) != null
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun canSendTermuxIntent(): Boolean {
        return try {
            val intent = Intent(TERMUX_RUN_COMMAND_ACTION).apply {
                component = ComponentName(
                    TERMUX_PKG,
                    TERMUX_RUN_COMMAND_SERVICE
                )
            }
            context?.packageManager?.resolveService(intent, 0) != null
        } catch (_: Exception) {
            false
        }
    }

    private fun readStream(inputStream: java.io.InputStream): String {
        return try {
            BufferedReader(InputStreamReader(inputStream)).readText()
        } catch (e: Exception) {
            Log.e(TAG, "读取流失败", e)
            ""
        }
    }

    data class ExecResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
        val durationMs: Long,
        val source: String = "system_sh"
    )
}
