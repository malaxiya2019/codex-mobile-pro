#ifndef PTY_NATIVE_H
#define PTY_NATIVE_H

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * JNI 函数声明 — 对应 com.codexmobile.app.terminal.PtySession
 *
 * 命名规则：Java_<包名>_<类名>_<方法名>
 * 包名中的 "." 替换为 "_"
 */

// 创建 PTY 子进程
// 返回 int[3]: { pid, master_fd, error_code }
//   pid > 0 表示成功
//   master_fd 为 PTY master 端文件描述符
//   error_code: 0=成功, -1=forkpty失败, -2=chdir失败, -3=execve失败
JNIEXPORT jintArray JNICALL
Java_com_codexmobile_app_terminal_PtySession_createProcess(
    JNIEnv *env,
    jobject thiz,
    jstring shell_path,
    jobjectArray env_array,
    jstring work_dir,
    jint rows,
    jint cols);

// 向 PTY 写入数据
// 返回值: 实际写入的字节数，-1 表示错误
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_writeToPty(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jbyteArray data,
    jint offset,
    jint length);

// 从 PTY 读取数据
// 返回值: 实际读取的字节数，-1 表示错误，0 表示 EOF
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_readFromPty(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jbyteArray buffer,
    jint offset,
    jint length);

// 调整 PTY 窗口大小
// 返回值: 0=成功，-1=失败
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_resizePty(
    JNIEnv *env,
    jobject thiz,
    jint fd,
    jint rows,
    jint cols);

// 等待子进程退出
// 返回值: 退出码，-1 表示 waitpid 失败
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_waitForExit(
    JNIEnv *env,
    jobject thiz,
    jint pid);

// 发送信号给子进程
// 返回值: 0=成功，-1=失败
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_signalProcess(
    JNIEnv *env,
    jobject thiz,
    jint pid,
    jint signal);

// 关闭 PTY master fd
// 返回值: 0=成功，-1=失败
JNIEXPORT jint JNICALL
Java_com_codexmobile_app_terminal_PtySession_closeFd(
    JNIEnv *env,
    jobject thiz,
    jint fd);

#ifdef __cplusplus
}
#endif

#endif /* PTY_NATIVE_H */
