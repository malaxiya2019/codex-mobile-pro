package com.codexmobile.app

import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Termux 通信桥
 *
 * 通过 ProcessBuilder 在 Termux 环境中执行命令，
 * 支持读取 stdout、stderr、退出码。
 */
class TermuxBridge {

    companion object {
        private const val TAG = "TermuxBridge"
        const val CHANNEL = "com.codexmobile.app/termux"

        // Termux 环境路径
        private const val TERMUX_BASH = "/data/data/com.termux/files/usr/bin/bash"
        private const val TERMUX_HOME = "/data/data/com.termux/files/home"

        // 超时时间（毫秒）
        private const val TIMEOUT_MS = 30_000L
    }

    /**
     * 执行单条命令，返回执行结果
     */
    fun executeCommand(command: String): Result {
        Log.d(TAG, "执行命令: $command")
        val startTime = System.currentTimeMillis()

        return try {
            val process = ProcessBuilder(
                TERMUX_BASH, "-c", command
            )
                .directory(java.io.File(TERMUX_HOME))
                .redirectErrorStream(false)
                .start()

            // 超时控制
            val finished = process.waitFor(TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
            if (!finished) {
                process.destroyForcibly()
                return Result(
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

            Log.d(TAG, "命令完成: exitCode=$exitCode, duration=${duration}ms")
            Result(
                exitCode = exitCode,
                stdout = stdout,
                stderr = stderr,
                durationMs = duration
            )
        } catch (e: Exception) {
            Log.e(TAG, "命令执行失败", e)
            Result(
                exitCode = -1,
                stdout = "",
                stderr = "执行异常: ${e.message ?: "未知错误"}",
                durationMs = System.currentTimeMillis() - startTime
            )
        }
    }

    /**
     * 检查 Termux 环境是否可用
     */
    fun checkEnvironment(): Map<String, Any> {
        val checks = mutableMapOf<String, Any>()
        val bashFile = java.io.File(TERMUX_BASH)

        checks["bash_exists"] = bashFile.exists()
        checks["termux_home_exists"] = java.io.File(TERMUX_HOME).exists()

        if (bashFile.exists()) {
            val result = executeCommand("echo 'ok'")
            checks["bash_executable"] = result.exitCode == 0 && result.stdout.trim() == "ok"
        } else {
            checks["bash_executable"] = false
        }

        return checks
    }

    /**
     * 处理 MethodChannel 调用
     */
    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
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

    private fun readStream(inputStream: java.io.InputStream): String {
        return try {
            BufferedReader(InputStreamReader(inputStream)).readText()
        } catch (e: Exception) {
            Log.e(TAG, "读取流失败", e)
            ""
        }
    }

    data class Result(
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
        val durationMs: Long
    )
}
