package com.codexmobile.app.terminal

import android.util.Log

/**
 * PTY Native 接口 — JNI 方法声明
 *
 * 对应 jni/pty.c 中的 C 函数。
 * 所有方法都是静态的，通过 System.loadLibrary("pty_native") 加载。
 */
internal object PtyNative {

    private const val TAG = "PtyNative"
    private var loaded = false

    /**
     * 加载原生库
     */
    fun ensureLoaded() {
        if (loaded) return
        try {
            System.loadLibrary("pty_native")
            loaded = true
            Log.d(TAG, "libpty_native.so loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Failed to load libpty_native.so", e)
            throw PtySession.PtyException(
                "Native PTY library not available: ${e.message}"
            )
        }
    }

    // ── JNI 方法 ──

    /**
     * 创建 PTY 子进程
     *
     * @param shellPath shell 可执行文件路径
     * @param envArray  环境变量数组（"KEY=VALUE" 格式）
     * @param workDir   工作目录
     * @param rows      终端行数
     * @param cols      终端列数
     * @return int[3]: { pid, master_fd, error_code }
     */
    internal external fun createProcess(
        shellPath: String,
        envArray: Array<String>,
        workDir: String,
        rows: Int,
        cols: Int
    ): IntArray

    /**
     * 向 PTY 写入数据
     *
     * @param fd     PTY master 文件描述符
     * @param data   要写入的数据
     * @param offset 偏移量
     * @param length 长度
     * @return 实际写入字节数，-1 表示错误
     */
    internal external fun writeToPty(
        fd: Int,
        data: ByteArray,
        offset: Int,
        length: Int
    ): Int

    /**
     * 从 PTY 读取数据
     *
     * @param fd     PTY master 文件描述符
     * @param buffer 缓冲区
     * @param offset 偏移量
     * @param length 长度
     * @return 实际读取字节数，-1 表示错误，0 表示 EOF
     */
    internal external fun readFromPty(
        fd: Int,
        buffer: ByteArray,
        offset: Int,
        length: Int
    ): Int

    /**
     * 调整 PTY 窗口大小
     *
     * @param fd   PTY master 文件描述符
     * @param rows 行数
     * @param cols 列数
     * @return 0=成功，-1=失败
     */
    internal external fun resizePty(
        fd: Int,
        rows: Int,
        cols: Int
    ): Int

    /**
     * 等待子进程退出
     *
     * @param pid 子进程 PID
     * @return 退出码，-1 表示失败
     */
    internal external fun waitForExit(pid: Int): Int

    /**
     * 发送信号给子进程
     *
     * @param pid    子进程 PID
     * @param signal 信号编号
     * @return 0=成功，-1=失败
     */
    internal external fun signalProcess(pid: Int, signal: Int): Int

    /**
     * 关闭文件描述符
     *
     * @param fd 文件描述符
     * @return 0=成功，-1=失败
     */
    internal external fun closeFd(fd: Int): Int
}
