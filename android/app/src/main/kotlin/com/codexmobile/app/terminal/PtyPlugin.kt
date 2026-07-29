package com.codexmobile.app.terminal

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.*

/**
 * PTY 终端插件 — Flutter ↔ Native PTY 通信桥
 *
 * 职责：
 *   1. 管理 PTY 会话生命周期
 *   2. 通过 MethodChannel 接收 Flutter 命令
 *   3. 通过 EventChannel 向 Flutter 推送输出
 *
 * 支持两种模式：
 *   - 简单模式（Phase 1）：Flutter 传入 shellPath / args / environment，直接创建 PTY
 *   - BusyBox 模式（保留）：从 assets 解压 BusyBox 作为 Shell（向后兼容）
 *
 * MethodChannel:  com.codexmobile.app/terminal/native
 * EventChannel:   com.codexmobile.app/terminal/native/output
 */
class PtyPlugin(private val context: Context) {

    companion object {
        private const val TAG = "PtyPlugin"

        const val CHANNEL = "com.codexmobile.app/terminal/native"
        const val OUTPUT_CHANNEL = "com.codexmobile.app/terminal/native/output"

        private const val BUSYBOX_ASSET = "busybox-arm64"
        private const val BUSYBOX_NAME = "busybox"
        private const val BIN_DIR = "bin"

        private val sessions = ConcurrentHashMap<String, PtySession>()
        private val outputSinks = ConcurrentHashMap<String, EventChannel.EventSink>()
        private val readJobs = ConcurrentHashMap<String, Job>()

        private var binDir: File? = null
        private var busyboxReady = false
        private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    }

    fun registerWith(engine: FlutterEngine) {
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            onMethodCall(call, result)
        }

        EventChannel(
            engine.dartExecutor.binaryMessenger,
            OUTPUT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                val sessionId = arguments as? String
                if (sessionId != null) {
                    outputSinks[sessionId] = sink
                    Log.d(TAG, "Output sink registered for session: $sessionId")
                }
            }

            override fun onCancel(arguments: Any?) {
                val sessionId = arguments as? String
                if (sessionId != null) {
                    outputSinks.remove(sessionId)
                    Log.d(TAG, "Output sink cancelled for session: $sessionId")
                }
            }
        })

        Log.d(TAG, "PtyPlugin registered: $CHANNEL / $OUTPUT_CHANNEL")
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "checkBusybox" -> handleCheckBusybox(result)
                "setupBusybox" -> handleSetupBusybox(result)
                "createSession" -> handleCreateSession(call, result)
                "write" -> handleWrite(call, result)
                "resize" -> handleResize(call, result)
                "closeSession" -> handleCloseSession(call, result)
                "getShellPath" -> handleGetShellPath(result)
                "isAlive" -> handleIsAlive(call, result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Method $call.method failed", e)
            result.error("PTY_ERROR", e.message, null)
        }
    }

    // ── BusyBox 相关（保留向后兼容） ──

    private fun handleCheckBusybox(result: MethodChannel.Result) {
        val ready = busyboxReady && binDir != null && File(binDir, BUSYBOX_NAME).exists()
        result.success(mapOf(
            "ready" to ready,
            "binDir" to (binDir?.absolutePath ?: ""),
            "busyboxPath" to if (ready) File(binDir, BUSYBOX_NAME).absolutePath else ""
        ))
    }

    private fun handleSetupBusybox(result: MethodChannel.Result) {
        try {
            setupBusybox()
            result.success(mapOf(
                "success" to true,
                "binDir" to (binDir?.absolutePath ?: ""),
                "busyboxPath" to File(binDir, BUSYBOX_NAME).absolutePath
            ))
        } catch (e: Exception) {
            Log.e(TAG, "BusyBox setup failed", e)
            result.error("SETUP_FAILED", "BusyBox setup failed: ${e.message}", null)
        }
    }

    private fun setupBusybox() {
        if (busyboxReady) return

        val filesDir = context.filesDir
        binDir = File(filesDir, BIN_DIR).also { it.mkdirs() }

        val busyboxFile = File(binDir, BUSYBOX_NAME)

        if (busyboxFile.exists() && busyboxFile.canExecute()) {
            Log.d(TAG, "BusyBox already exists at ${busyboxFile.absolutePath}")
        } else {
            Log.d(TAG, "Extracting BusyBox from assets...")
            try {
                context.assets.open(BUSYBOX_ASSET).use { input ->
                    FileOutputStream(busyboxFile).use { output ->
                        input.copyTo(output)
                    }
                }
            } catch (e: Exception) {
                throw PtySession.PtyException(
                    "Failed to extract BusyBox from assets: ${e.message}"
                )
            }
            busyboxFile.setExecutable(true, false)
            busyboxFile.setReadable(true, false)
            Log.d(TAG, "BusyBox extracted: ${busyboxFile.length()} bytes")
        }

        installBusyboxApplets(busyboxFile)
        busyboxReady = true
        Log.d(TAG, "BusyBox setup complete at ${binDir!!.absolutePath}")
    }

    private fun installBusyboxApplets(busyboxFile: File) {
        val dir = binDir ?: return
        var installOk = false
        try {
            val process = Runtime.getRuntime().exec(
                arrayOf(busyboxFile.absolutePath, "--install", dir.absolutePath)
            )
            process.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)
            if (File(dir, "ash").exists()) {
                installOk = true
                Log.d(TAG, "BusyBox --install completed (ash found)")
            }
        } catch (e: Exception) {
            Log.w(TAG, "BusyBox --install failed: ${e.message}")
        }

        if (!installOk) {
            Log.w(TAG, "Falling back to manual ash creation")
            val ashFile = File(dir, "ash")
            try {
                java.nio.file.Files.createSymbolicLink(
                    ashFile.toPath(),
                    busyboxFile.toPath()
                )
                Log.d(TAG, "Created ash symlink")
            } catch (e1: Exception) {
                try {
                    java.nio.file.Files.createLink(
                        ashFile.toPath(),
                        busyboxFile.toPath()
                    )
                    Log.d(TAG, "Created ash hardlink")
                } catch (e2: Exception) {
                    try {
                        busyboxFile.copyTo(ashFile, overwrite = true)
                        ashFile.setExecutable(true, false)
                        Log.d(TAG, "Copied busybox to ash")
                    } catch (e3: Exception) {
                        Log.w(TAG, "Failed to create ash: ${e3.message}")
                    }
                }
            }
        }
    }

    private fun getShellPath(): String {
        if (binDir == null) {
            throw PtySession.PtyException("BusyBox not set up")
        }
        val ashPath = File(binDir, "ash").absolutePath
        if (File(ashPath).exists()) {
            return ashPath
        }
        Log.w(TAG, "ash symlink not found, using busybox ash directly")
        return File(binDir, BUSYBOX_NAME).absolutePath
    }

    private fun getBusyboxEnvironment(workDir: String): Array<String> {
        val dir = binDir ?: return emptyArray()
        return arrayOf(
            "HOME=$workDir",
            "PATH=${dir.absolutePath}:/system/bin:/system/xbin",
            "TERM=xterm-256color",
            "SHELL=${dir.absolutePath}/ash",
            "USER=shell",
            "LOGNAME=shell"
        )
    }

    private fun mapToEnvArray(env: Map<String, String>?): Array<String> {
        if (env == null || env.isEmpty()) return emptyArray()
        return env.entries.map { (k, v) -> "$k=$v" }.toTypedArray()
    }

    // ── 会话管理 ──

    private fun handleCreateSession(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = UUID.randomUUID().toString()
        val rows = (call.argument<Int>("rows") ?: 60).coerceAtLeast(10)
        val cols = (call.argument<Int>("cols") ?: 120).coerceAtLeast(20)
        val workDir = call.argument<String>("workDir") ?: context.filesDir.absolutePath

        val flutterShellPath = call.argument<String>("shellPath")
        val flutterArgs = call.argument<List<String>>("args") ?: emptyList()
        val flutterEnv = call.argument<Map<String, String>>("environment")

        PtyNative.ensureLoaded()

        val shellPath: String
        val env: Array<String>

        if (flutterShellPath != null && flutterShellPath.isNotEmpty()) {
            // Phase 1: 使用 Flutter 传入的 Shell（如 /system/bin/sh）
            shellPath = flutterShellPath
            env = mapToEnvArray(flutterEnv)
            Log.d(TAG, "Creating PTY session (Phase1): id=$sessionId, shell=$shellPath, args=$flutterArgs")
        } else {
            // 向后兼容: 使用 BusyBox
            if (!busyboxReady) {
                setupBusybox()
            }
            shellPath = getShellPath()
            env = getBusyboxEnvironment(workDir)
            Log.d(TAG, "Creating PTY session (BusyBox): id=$sessionId, shell=$shellPath")
        }

        val session = PtySession.create(
            shellPath = shellPath,
            env = env,
            workDir = workDir,
            rows = rows,
            cols = cols
        )

        sessions[sessionId] = session

        val readJob = scope.launch {
            try {
                val buf = ByteArray(4096)
                while (isActive && session.isAlive) {
                    val nread = try {
                        PtyNative.readFromPty(session.ptyFd, buf, 0, buf.size)
                    } catch (e: Exception) {
                        if (e.message?.contains("destroyed") == true) break
                        -1
                    }
                    if (nread < 0) break
                    if (nread == 0) {
                        delay(10)
                        continue
                    }
                    val chunk = ByteArray(nread)
                    System.arraycopy(buf, 0, chunk, 0, nread)
                    val text = String(chunk, Charsets.UTF_8)

                    withContext(Dispatchers.Main) {
                        outputSinks[sessionId]?.success(mapOf(
                            "sessionId" to sessionId,
                            "data" to text,
                            "isStderr" to false
                        ))
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Read loop ended for session $sessionId: ${e.message}")
            } finally {
                withContext(Dispatchers.Main) {
                    outputSinks[sessionId]?.success(mapOf(
                        "sessionId" to sessionId,
                        "data" to "",
                        "isStderr" to false,
                        "closed" to true
                    ))
                }
            }
        }
        readJobs[sessionId] = readJob

        result.success(mapOf(
            "sessionId" to sessionId,
            "pid" to session.pid,
            "shellPath" to shellPath,
            "binDir" to binDir?.absolutePath
        ))
    }

    private fun handleWrite(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<String>("sessionId") ?: ""
        val text = call.argument<String>("data") ?: ""
        val session = sessions[sessionId]
            ?: throw PtySession.PtyException("Session not found: $sessionId")
        session.writeString(text)
        result.success(true)
    }

    private fun handleResize(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<String>("sessionId") ?: ""
        val rows = (call.argument<Int>("rows") ?: 60).coerceAtLeast(5)
        val cols = (call.argument<Int>("cols") ?: 120).coerceAtLeast(10)
        val session = sessions[sessionId]
            ?: throw PtySession.PtyException("Session not found: $sessionId")
        session.resize(rows, cols)
        result.success(true)
    }

    private fun handleCloseSession(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<String>("sessionId") ?: ""
        readJobs[sessionId]?.cancel()
        readJobs.remove(sessionId)
        sessions[sessionId]?.close()
        sessions.remove(sessionId)
        outputSinks.remove(sessionId)
        Log.d(TAG, "Session closed: $sessionId")
        result.success(true)
    }

    private fun handleGetShellPath(result: MethodChannel.Result) {
        try {
            val path = if (busyboxReady) getShellPath() else ""
            result.success(mapOf("shellPath" to path, "ready" to busyboxReady))
        } catch (e: Exception) {
            result.success(mapOf("shellPath" to "", "ready" to false))
        }
    }

    private fun handleIsAlive(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<String>("sessionId") ?: ""
        val session = sessions[sessionId]
        result.success(session?.isAlive == true)
    }

    fun disposeAll() {
        Log.d(TAG, "Disposing all PTY sessions (${sessions.size})")
        for ((id, session) in sessions.entries) {
            readJobs[id]?.cancel()
            session.close()
        }
        sessions.clear()
        readJobs.clear()
        outputSinks.clear()
    }
}
