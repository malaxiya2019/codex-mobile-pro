package com.codexmobile.app.terminal

import android.util.Log
import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * PTY 会话 — JNI 封装
 *
 * 通过 [PtyNative] 与 C 层的 forkpty/execve 交互。
 * 每个 PtySession 对应一个独立的 PTY 子进程。
 *
 * 调用顺序：
 *   1. PtySession.create(shellPath, env, workDir)
 *   2. read(buffer) / write(data) — 循环读写
 *   3. resize(rows, cols) — 按需调整
 *   4. destroy() — 清理资源
 */
class PtySession private constructor(
    val pid: Int,
    val ptyFd: Int
) : Closeable {

    private val destroyed = AtomicBoolean(false)
    private val readerBuffer = ByteArray(READ_BUF_SIZE)
    private val writeLock = Any()

    companion object {
        private const val TAG = "PtySession"

        /** PTY read buffer size */
        private const val READ_BUF_SIZE = 4096

        /** 信号常量 */
        const val SIGINT = 2   // Ctrl+C
        const val SIGKILL = 9  // 强制终止
        const val SIGTERM = 15 // 正常终止
        const val SIGHUP = 1   // 挂起

        /**
         * 创建 PTY 会话
         *
         * @param shellPath shell 可执行文件路径（如 /data/data/.../bin/busybox）
         * @param env       环境变量数组（"KEY=VALUE" 格式）
         * @param workDir   工作目录
         * @param rows      终端行数（默认 60）
         * @param cols      终端列数（默认 120）
         * @return PtySession 实例
         * @throws PtyException 创建失败时抛出
         */
        fun create(
            shellPath: String,
            env: Array<String> = emptyArray(),
            workDir: String? = null,
            rows: Int = 60,
            cols: Int = 120
        ): PtySession {
            val result = PtyNative.createProcess(shellPath, env, workDir ?: "", rows, cols)
            val pid = result[0]
            val fd = result[1]
            val errorCode = result[2]

            if (pid <= 0 || fd <= 0) {
                val msg = when (errorCode) {
                    -1 -> "forkpty failed"
                    -2 -> "chdir failed"
                    -3 -> "execve failed"
                    -99 -> "invalid arguments"
                    else -> "unknown error (code=$errorCode)"
                }
                throw PtyException("PTY create failed: $msg (pid=$pid, fd=$fd)")
            }

            Log.d(TAG, "PTY session created: pid=$pid, fd=$fd")
            return PtySession(pid, fd)
        }

        /**
         * 获取 shell 的启动参数
         * 用于 PtySession.create() 的 shellPath
         */
        fun shellArgs(shellPath: String): Array<String> {
            return arrayOf(shellPath, "-i")
        }
    }

    /**
     * 从 PTY 读取数据（阻塞）
     *
     * @return ByteArray 读取到的数据，空数组表示 EOF
     * @throws PtyException 读取失败时抛出
     */
    fun read(): ByteArray {
        checkNotDestroyed()
        val nread = PtyNative.readFromPty(ptyFd, readerBuffer, 0, READ_BUF_SIZE)
        if (nread < 0) {
            throw PtyException("PTY read failed")
        }
        if (nread == 0) {
            return ByteArray(0) // EOF
        }
        val result = ByteArray(nread)
        System.arraycopy(readerBuffer, 0, result, 0, nread)
        return result
    }

    /**
     * 向 PTY 写入数据
     *
     * @param data 要写入的字节数据
     * @throws PtyException 写入失败时抛出
     */
    fun write(data: ByteArray) {
        checkNotDestroyed()
        synchronized(writeLock) {
            val written = PtyNative.writeToPty(ptyFd, data, 0, data.size)
            if (written < 0) {
                throw PtyException("PTY write failed")
            }
            if (written < data.size) {
                Log.w(TAG, "PTY partial write: $written/${data.size}")
            }
        }
    }

    /**
     * 写入字符串（UTF-8 编码）
     */
    fun writeString(text: String) {
        write(text.toByteArray(Charsets.UTF_8))
    }

    /**
     * 发送 Ctrl+C 信号
     */
    fun sendSigint() {
        signal(SIGINT)
    }

    /**
     * 发送 Ctrl+D 信号
     */
    fun sendSigquit() {
        // 实际 Ctrl+D 是向 stdin 写入 0x04
        write(byteArrayOf(0x04))
    }

    /**
     * 调整终端窗口大小
     *
     * @param rows 行数
     * @param cols 列数
     * @throws PtyException 调整失败时抛出
     */
    fun resize(rows: Int, cols: Int) {
        checkNotDestroyed()
        val result = PtyNative.resizePty(ptyFd, rows, cols)
        if (result < 0) {
            throw PtyException("PTY resize failed")
        }
    }

    /**
     * 发送信号给子进程
     */
    fun signal(sig: Int) {
        if (destroyed.get()) return
        PtyNative.signalProcess(pid, sig)
    }

    /**
     * 检查进程是否存活
     */
    val isAlive: Boolean
        get() {
            if (destroyed.get()) return false
            // 发送信号 0 检测进程是否存在
            return PtyNative.signalProcess(pid, 0) == 0
        }

    /**
     * 销毁 PTY 会话
     *
     * 发送 SIGTERM → 关闭 fd
     */
    override fun close() {
        if (destroyed.getAndSet(true)) return
        Log.d(TAG, "Destroying PTY session: pid=$pid, fd=$ptyFd")

        // 先发 SIGTERM，再发 SIGKILL 确保进程终止
        PtyNative.signalProcess(pid, SIGTERM)
        try {
            Thread.sleep(100)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        PtyNative.signalProcess(pid, SIGKILL)

        // 关闭 PTY master fd
        PtyNative.closeFd(ptyFd)
    }

    /**
     * 等待进程退出
     *
     * @return 退出码（正数），信号终止时返回 -signal
     */
    fun waitForExit(): Int {
        return PtyNative.waitForExit(pid)
    }

    private fun checkNotDestroyed() {
        if (destroyed.get()) {
            throw PtyException("PTY session already destroyed")
        }
    }

    /** PTY 异常 */
    class PtyException(message: String, cause: Throwable? = null) : Exception(message, cause)
}
