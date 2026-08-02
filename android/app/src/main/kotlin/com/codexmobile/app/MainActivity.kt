package com.codexmobile.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.codexmobile.app.terminal.PtyPlugin

/// Codex Mobile Pro 主 Activity
///
/// 注册 Native 插件（PTY / 日志导出），处理 Flutter ↔ Native 通信。
class MainActivity : FlutterActivity() {

    private val ptyPlugin by lazy { PtyPlugin(this) }
    private val logExportPlugin by lazy { LogExportPlugin(this) }
    private val updateInstallerPlugin by lazy { UpdateInstallerPlugin(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册 PTY 终端插件（forkpty / execve）
        ptyPlugin.registerWith(flutterEngine)

        // 注册日志导出插件（MediaStore → Download）
        logExportPlugin.registerWith(flutterEngine)

        // 注册更新安装插件（FileProvider → 系统包安装器）
        updateInstallerPlugin.registerWith(flutterEngine)
    }

    override fun onDestroy() {
        // 清理 PTY 会话
        ptyPlugin.disposeAll()
        super.onDestroy()
    }
}
