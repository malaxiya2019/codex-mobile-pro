/*
 * pty.c — JNI PTY 实现
 *
 * 使用 forkpty() 创建真实伪终端，支持：
 *   - 创建子进程并连接 PTY
 *   - 读写 PTY master 端
 *   - 调整窗口大小
 *   - 发送信号
 *   - 等待退出
 *
 * 本文件只负责 PTY 生命周期，不包含任何业务逻辑。
 */

#include "pty.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <errno.h>
#include <android/log.h>
#include <sys/types.h>

#define TAG "PtyNative"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/*
 * forkpty() 在 Android Bionic libc 中可以通过 <pty.h> 使用。
 * Bionic 的 forkpty() 内部实现为：
 *   1. openpty() — 打开 PTY master/slave 对
 *   2. fork()
 *      - 子进程：setsid() → 打开 slave 作为 stdin/stdout/stderr → 关闭 master
 *      - 父进程：关闭 slave，返回 master_fd
 */
#include <pty.h>

// ──────────────────────────────────────────────
// 辅助函数：释放 JNI 字符串数组
// ──────────────────────────────────────────────
static void release_utf_strings(JNIEnv *env, jstring *strings, int count) {
    for (int i = 0; i < count; i++) {
        if (strings[i] != NULL) {
            (*env)->ReleaseStringUTFChars(env, strings[i], NULL);
            (*env)->DeleteLocalRef(env, strings[i]);
        }
    }
    free(strings);
}

// ──────────────────────────────────────────────
// 辅助函数：构建环境变量数组 (char **)
// ──────────────────────────────────────────────
static char **build_env_array(JNIEnv *env, jobjectArray env_array, int env_len) {
    char **envp = (char **)malloc(sizeof(char *) * (env_len + 1));
    if (envp == NULL) return NULL;

    for (int i = 0; i < env_len; i++) {
        jstring jstr = (jstring)(*env)->GetObjectArrayElement(env, env_array, i);
        if (jstr == NULL) {
            envp[i] = NULL;
            continue;
        }
        const char *str = (*env)->GetStringUTFChars(env, jstr, NULL);
        envp[i] = strdup(str);
        (*env)->ReleaseStringUTFChars(env, jstr, str);
        (*env)->DeleteLocalRef(env, jstr);
    }
    envp[env_len] = NULL;
    return envp;
}

// ──────────────────────────────────────────────
// JNI: createProcess
// ──────────────────────────────────────────────
JNIEXPORT jintArray JNICALL
Java_com_codexmobile_app_terminal_PtySession_createProcess(
    JNIEnv *env,
    jobject thiz,
    jstring shell_path,
    jobjectArray env_array,
    jstring work_dir,
    jint rows,
    jint cols) {

    (void)thiz;

    // 默认值
    if (rows <= 0) rows = 60;
    if (cols <= 0) cols = 120;

    // ── 获取 shell 路径 ──
    const char *shell_path_cstr = (*env)->GetStringUTFChars(env, shell_path, NULL);
    if (shell_path_cstr == NULL) {
        jintArray error_result = (*env)->NewIntArray(env, 3);
        jint error_data[3] = {0, 0, -99};
        (*env)->SetIntArrayRegion(env, error_result, 0, 3, error_data);
        return error_result;
    }

    // ── 获取工作目录 ──
    const char *work_dir_cstr = NULL;
    char *work_dir_dup = NULL;
    if (work_dir != NULL) {
        work_dir_cstr = (*env)->GetStringUTFChars(env, work_dir, NULL);
        if (work_dir_cstr != NULL) {
            work_dir_dup = strdup(work_dir_cstr);
            (*env)->ReleaseStringUTFChars(env, work_dir, work_dir_cstr);
        }
    }

    // ── 获取环境变量 ──
    jsize env_len = 0;
    char **envp = NULL;
    if (env_array != NULL) {
        env_len = (*env)->GetArrayLength(env, env_array);
        envp = build_env_array(env, env_array, env_len);
    }

    // ── 构建 argv ──
    // argv[0] = shell_path
    // argv[1] = "-i" (交互模式)
    // argv[2] = NULL
    char *argv[3];
    argv[0] = strdup(shell_path_cstr);
    argv[1] = strdup("-i");
    argv[2] = NULL;

    // ── 设置 terminal I/O 属性 ──
    struct termios tt;
    memset(&tt, 0, sizeof(tt));
    tt.c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT | IUTF8;
    tt.c_oflag = OPOST | ONLCR;
    tt.c_cflag = CS8 | CREAD | HUPCL;
    tt.c_lflag = ISIG | ICANON | ECHO | ECHOE | ECHOK | ECHONL | IEXTEN;
    tt.c_cc[VINTR]    = 0x03;  // Ctrl+C
    tt.c_cc[VQUIT]    = 0x1c;  // Ctrl+\
    tt.c_cc[VERASE]   = 0x7f;  // DEL
    tt.c_cc[VKILL]    = 0x15;  // Ctrl+U
    tt.c_cc[VEOF]     = 0x04;  // Ctrl+D
    tt.c_cc[VSTOP]    = 0x13;  // Ctrl+S
    tt.c_cc[VSUSP]    = 0x1a;  // Ctrl+Z
    tt.c_cc[VSTART]   = 0x11;  // Ctrl+Q
    tt.c_cc[VMIN]     = 1;
    tt.c_cc[VTIME]    = 0;

    // ── 窗口大小 ──
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    // ── forkpty ──
    int master_fd;
    pid_t pid = forkpty(&master_fd, NULL, &tt, &ws);

    if (pid < 0) {
        LOGE("forkpty failed: %s", strerror(errno));
        // 清理
        free(argv[0]);
        free(argv[1]);
        free(work_dir_dup);
        if (envp) {
            for (int i = 0; i < env_len; i++) free(envp[i]);
            free(envp);
        }
        (*env)->ReleaseStringUTFChars(env, shell_path, shell_path_cstr);

        jintArray error_result = (*env)->NewIntArray(env, 3);
        jint error_data[3] = {0, 0, -1};
        (*env)->SetIntArrayRegion(env, error_result, 0, 3, error_data);
        return error_result;
    }

    if (pid == 0) {
        // ── 子进程 ──
        // 切换到工作目录
        if (work_dir_dup != NULL) {
            if (chdir(work_dir_dup) != 0) {
                LOGE("chdir(%s) failed: %s", work_dir_dup, strerror(errno));
                // 忽略错误，继续启动
            }
        }

        // 执行 shell
        execve(shell_path_cstr, argv, envp);
        // execve 失败时才到达这里
        LOGE("execve(%s) failed: %s", shell_path_cstr, strerror(errno));
        _exit(127);
    }

    // ── 父进程 ──
    LOGD("forkpty success: pid=%d, master_fd=%d", pid, master_fd);

    // 释放资源
    free(argv[0]);
    free(argv[1]);
    free(work_dir_dup);
    if (envp) {
        for (int i = 0; i < env_len; i++) free(envp[i]);
        free(envp);
    }
    (*env)->ReleaseStringUTFChars(env, shell_path, shell_path_cstr);

    // 返回结果
    jintArray result = (*env)->NewIntArray(env, 3);
    if (result == NULL) return NULL;
    jint data[3] = {(jint)pid, (jint)master_fd, 0};
    (*env)->SetIntArrayRegion(env, result, 0, 3, data);
    return result;
}

// ──────────────────────────────────────────────
// JNI: writeToPty
// ──────────────────────────────────────────────
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_writeToPty(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jbyteArray data,
    jint offset,
    jint length) {

    (void)thiz;

    if (fd < 0 || data == NULL || length <= 0) return -1;

    jbyte *bytes = (*env)->GetByteArrayElements(env, data, NULL);
    if (bytes == NULL) return -1;

    jbyte *buf = bytes + offset;
    ssize_t written = write((int)fd, buf, (size_t)length);

    (*env)->ReleaseByteArrayElements(env, data, bytes, JNI_ABORT);

    if (written < 0) {
        LOGE("write to pty fd=%d failed: %s", fd, strerror(errno));
        return -1;
    }
    return (jint)written;
}

// ──────────────────────────────────────────────
// JNI: readFromPty
// ──────────────────────────────────────────────
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_readFromPty(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jbyteArray buffer,
    jint offset,
    jint length) {

    (void)thiz;

    if (fd < 0 || buffer == NULL || length <= 0) return -1;

    jbyte *bytes = (*env)->GetByteArrayElements(env, buffer, NULL);
    if (bytes == NULL) return -1;

    jbyte *buf = bytes + offset;
    ssize_t nread = read((int)fd, buf, (size_t)length);

    if (nread < 0) {
        if (errno == EINTR) {
            // 被信号中断，重试
            nread = read((int)fd, buf, (size_t)length);
        }
        if (nread < 0) {
            LOGE("read from pty fd=%d failed: %s", fd, strerror(errno));
            (*env)->ReleaseByteArrayElements(env, buffer, bytes, JNI_ABORT);
            return -1;
        }
    }

    (*env)->ReleaseByteArrayElements(env, buffer, bytes, 0);
    return (jint)nread;
}

// ──────────────────────────────────────────────
// JNI: resizePty
// ──────────────────────────────────────────────
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_resizePty(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jint rows,
    jint cols) {

    (void)env;
    (void)thiz;

    if (fd < 0 || rows <= 0 || cols <= 0) return -1;

    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    if (ioctl((int)fd, TIOCSWINSZ, &ws) < 0) {
        LOGE("ioctl TIOCSWINSZ failed: %s", strerror(errno));
        return -1;
    }

    LOGD("resized pty fd=%d to %dx%d", fd, rows, cols);
    return 0;
}

// ──────────────────────────────────────────────
// JNI: waitForExit
// ──────────────────────────────────────────────
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_waitForExit(
    JNIEnv *env,
    jobject thiz,
    jint pid) {

    (void)env;
    (void)thiz;

    if (pid <= 0) return -1;

    int status;
    pid_t result = waitpid((pid_t)pid, &status, 0);
    if (result < 0) {
        LOGE("waitpid(%d) failed: %s", pid, strerror(errno));
        return -1;
    }

    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return -WTERMSIG(status);
    }
    return -1;
}

// ──────────────────────────────────────────────
// JNI: signalProcess
// ──────────────────────────────────────────────
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_signalProcess(
    JNIEnv *env,
    jobject thiz,
    jint pid,
    jint signal) {

    (void)env;
    (void)thiz;

    if (pid <= 0) return -1;

    if (kill((pid_t)pid, signal) < 0) {
        LOGE("kill(%d, %d) failed: %s", pid, signal, strerror(errno));
        return -1;
    }
    return 0;
}

// ──────────────────────────────────────────────
// JNI: closeFd
// ──────────────────────────────────────────────
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_closeFd(
    JNIEnv *env,
    jobject thiz,
    jint fd) {

    (void)env;
    (void)thiz;

    if (fd < 0) return -1;

    if (close((int)fd) < 0) {
        LOGE("close(%d) failed: %s", fd, strerror(errno));
        return -1;
    }
    return 0;
}
