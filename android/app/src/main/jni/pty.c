/*
 * pty.c — JNI PTY 实现
 *
 * 使用 POSIX 标准 PTY 接口创建伪终端：
 *   posix_openpt() → grantpt() → unlockpt() → ptsname() → fork()
 *
 * 不依赖 <pty.h>（不同 NDK 版本 forkpty() 可用性不一致）。
 * 支持：
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
#include <fcntl.h>
#include <errno.h>
#include <android/log.h>
#include <sys/types.h>

#define TAG "PtyNative"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

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
// 创建 PTY 子进程（替代 forkpty，不依赖 <pty.h>）
// ──────────────────────────────────────────────
static pid_t create_pty_process(int *master_fd,
                                const struct termios *termp,
                                const struct winsize *winp,
                                const char *shell_path,
                                char **argv,
                                char **envp,
                                const char *work_dir) {
    // 1. 打开 PTY master
    int mfd = posix_openpt(O_RDWR | O_NOCTTY);
    if (mfd < 0) {
        LOGE("posix_openpt failed: %s", strerror(errno));
        return -1;
    }

    // 2. 授权 slave 访问
    if (grantpt(mfd) < 0) {
        LOGE("grantpt failed: %s", strerror(errno));
        close(mfd);
        return -1;
    }

    // 3. 解锁 slave
    if (unlockpt(mfd) < 0) {
        LOGE("unlockpt failed: %s", strerror(errno));
        close(mfd);
        return -1;
    }

    // 4. 获取 slave 路径
    const char *slave_name = ptsname(mfd);
    if (slave_name == NULL) {
        LOGE("ptsname failed: %s", strerror(errno));
        close(mfd);
        return -1;
    }

    // 5. 设置 termios（仅在 master 上设置，slave 会继承）
    if (termp != NULL) {
        tcsetattr(mfd, TCSANOW, termp);
    }

    // 6. 设置窗口大小
    if (winp != NULL) {
        ioctl(mfd, TIOCSWINSZ, winp);
    }

    // 7. fork
    pid_t pid = fork();
    if (pid < 0) {
        LOGE("fork failed: %s", strerror(errno));
        close(mfd);
        return -1;
    }

    if (pid == 0) {
        // ── 子进程 ──
        close(mfd);  // 子进程关闭 master

        // 打开 slave
        int sfd = open(slave_name, O_RDWR);
        if (sfd < 0) {
            LOGE("open slave '%s' failed: %s", slave_name, strerror(errno));
            _exit(127);
        }

        // 创建新会话并设置 controlling terminal
        setsid();
        ioctl(sfd, TIOCSCTTY, 0);

        // 复制到 stdin/stdout/stderr
        dup2(sfd, STDIN_FILENO);
        dup2(sfd, STDOUT_FILENO);
        dup2(sfd, STDERR_FILENO);

        // 安全地关闭多余的 fd
        if (sfd > STDERR_FILENO) {
            close(sfd);
        }

        // 切换工作目录
        if (work_dir != NULL) {
            if (chdir(work_dir) != 0) {
                LOGE("chdir(%s) failed: %s", work_dir, strerror(errno));
                // 忽略错误，继续启动 shell
            }
        }

        // 执行 shell
        execve(shell_path, argv, envp);
        LOGE("execve(%s) failed: %s", shell_path, strerror(errno));
        _exit(127);
    }

    // ── 父进程 ──
    *master_fd = mfd;
    LOGD("pty created: pid=%d, master_fd=%d, slave=%s", pid, mfd, slave_name);
    return pid;
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

    // ── 创建 PTY 子进程 ──
    int master_fd;
    pid_t pid = create_pty_process(
        &master_fd, &tt, &ws,
        shell_path_cstr, argv, envp,
        work_dir_dup);

    if (pid < 0) {
        LOGE("create_pty_process failed: %s", strerror(errno));
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

    // ── 父进程继续 ──
    LOGD("createProcess success: pid=%d, master_fd=%d", pid, master_fd);

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
