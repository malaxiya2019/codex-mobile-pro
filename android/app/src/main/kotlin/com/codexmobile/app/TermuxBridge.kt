package com.codexmobile.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.ResultReceiver
import android.os.Handler
import android.os.Bundle
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

/**
 * Termux 通信桥
 *
 * 多策略降级方案：
 * 1. 直接访问 Termux bash（Android 10+ 通常被沙箱阻止）
 * 2. Termux RunCommandService Intent（需要 Termux 运行中）
 * 3. Android 系统 shell 降级（始终可用，验证通信管道）
 */
class TermuxBridge(private val context: Context? = null) {

    companion object {
        private const val TAG = "TermuxBridge"
        const val CHANNEL = "com.codexmobile.app/termux"

        // Termux
        private const val TERMUX_PKG = "com.termux"
        private const val TERMUX_BASH = "/data/data/com.termux/files/usr/bin/bash"
        private const val TERMUX_HOME = "/data/data/com.termux/files/home"

        // 系统 shell
        private const val SYSTEM_SH = "/system/bin/sh"

        private const val TIMEOUT_MS = 30_000L

        // 工作目录：使用应用自己的目录（Android 10+ 无法访问 Termux 私有目录）
        private var _workDir: java.io.File? = null
    }

    // 获取有效的可写工作目录
    private fun getWorkDir(): java.io.File {
        if (_workDir == null) {
            _workDir = try {
                // 优先使用应用缓存目录（一定可写）
                context?.cacheDir?.also {
                    Log.d(TAG, "工作目录（cacheDir）: ${it.absolutePath}")
                }
            } catch (e: Exception) {
                null
            }
            if (_workDir == null) {
                _workDir = try {
                    context?.filesDir?.also {
                        Log.d(TAG, "工作目录（filesDir）: ${it.absolutePath}")
                    }
                } catch (e: Exception) {
                    null
                }
            }
            // 最后降级
            if (_workDir == null) {
                _workDir = java.io.File("/data/local/tmp").also {
                    it.mkdirs()
                    Log.d(TAG, "工作目录（/data/local/tmp）: ${it.absolutePath}")
                }
            }
        }
        return _workDir!!
    }

    // ──────────────────────────────────────────────
    // 对外 API
    // ──────────────────────────────────────────────

    /**
     * 执行单条命令（多策略降级）
     */
    fun executeCommand(command: String): ExecResult {
        Log.d(TAG, "执行命令: $command")
        val startTime = System.currentTimeMillis()

        // 策略 1: 尝试 Termux bash
        val bashFile = java.io.File(TERMUX_BASH)
        if (bashFile.canExecute()) {
            val result = tryExec(TERMUX_BASH, command, startTime)
            if (result != null) return result
        }

        // 策略 2: 尝试系统 shell
        val result = tryExec(SYSTEM_SH, command, startTime)
        if (result != null) return result

        // 全部失败
        return ExecResult(
            exitCode = -1,
            stdout = "",
            stderr = "无法执行命令：Termux bash 不可访问，系统 shell 也无法使用",
            durationMs = System.currentTimeMillis() - startTime
        )
    }

    /**
     * 检查环境（返回详细诊断信息）
     */
    fun checkEnvironment(): Map<String, Any> {
        val checks = linkedMapOf<String, Any>()

        // 1. 检查 Termux 是否安装
        val termuxInstalled = isPackageInstalled(TERMUX_PKG)
        checks["termux_installed"] = termuxInstalled

        // 2. 检查 bash 文件
        val bashFile = java.io.File(TERMUX_BASH)
        checks["bash_exists"] = bashFile.exists()
        checks["bash_can_read"] = bashFile.canRead()
        checks["bash_can_execute"] = bashFile.canExecute()

        // 3. 检查 home 目录
        val homeDir = java.io.File(TERMUX_HOME)
        checks["termux_home_exists"] = homeDir.exists()
        checks["termux_home_can_read"] = homeDir.canRead()

        // 4. 检查系统 shell
        val shFile = java.io.File(SYSTEM_SH)
        checks["system_sh_exists"] = shFile.exists()
        checks["system_sh_can_execute"] = shFile.canExecute()

        // 5. 尝试 Termux Intent 通信
        checks["termux_intent_available"] = canSendTermuxIntent()

        // 6. 测试 Termux bash（如果可执行）
        if (bashFile.canExecute()) {
            val result = executeCommand("echo 'termux_ok'")
            checks["bash_works"] = result.exitCode == 0 && result.stdout.trim() == "termux_ok"
            checks["bash_last_stderr"] = result.stderr.take(200)
        } else {
            checks["bash_works"] = false
        }

        // 7. 测试系统 shell
        val shResult = tryExec(SYSTEM_SH, "echo 'sh_ok'", System.currentTimeMillis())
        checks["sh_works"] = shResult != null && shResult.exitCode == 0 && shResult.stdout.trim() == "sh_ok"
        checks["sh_last_stderr"] = shResult?.stderr?.take(200) ?: "N/A"

        // 8. 整体状态
        val isAvailable = termuxInstalled && bashFile.canExecute() && (checks["bash_works"] == true)
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
                    "durationMs" to execResult.durationMs
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

    /**
     * 尝试使用指定 shell 执行命令
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
                    durationMs = System.currentTimeMillis() - startTime
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
                durationMs = duration
            )
        } catch (e: Exception) {
            Log.w(TAG, "[$shell] 执行失败: ${e.message}")
            null
        }
    }

    /**
     * 检查包是否已安装
     */
    private fun isPackageInstalled(pkgName: String): Boolean {
        return try {
            context?.packageManager?.getPackageInfo(pkgName, 0) != null
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * 检查能否发送 Termux Intent
     */
    private fun canSendTermuxIntent(): Boolean {
        return try {
            val intent = Intent("com.termux.RUN_COMMAND").apply {
                component = ComponentName("com.termux", "com.termux.app.RunCommandService")
                putExtra("com.termux.RUN_COMMAND_PATH", TERMUX_BASH)
                putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", "echo ok"))
                putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            }
            context?.packageManager?.resolveService(intent, 0) != null
        } catch (e: Exception) {
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
        val durationMs: Long
    )
}
