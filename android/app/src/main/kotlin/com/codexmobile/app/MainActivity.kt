package com.codexmobile.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.codexmobile.app.terminal.PtyPlugin

/// Codex Mobile Pro 主 Activity
///
/// 注册 Native 插件（PTY），处理 Flutter ↔ Native 通信。
class MainActivity : FlutterActivity() {

    private val ptyPlugin by lazy { PtyPlugin(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册 PTY 终端插件（forkpty / execve）
        ptyPlugin.registerWith(flutterEngine)
    }

    override fun onDestroy() {
        // 清理 PTY 会话
        ptyPlugin.disposeAll()
        super.onDestroy()
    }
}
