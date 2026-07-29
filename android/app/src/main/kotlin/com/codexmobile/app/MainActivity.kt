package com.codexmobile.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.codexmobile.app.terminal.PtyPlugin

/// Codex Mobile Pro 主 Activity
///
/// 注册 MethodChannel，处理 Flutter ↔ Native 通信。
class MainActivity : FlutterActivity() {

    private val termuxBridge by lazy { TermuxBridge(this) }
    private val ptyPlugin by lazy { PtyPlugin(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册 Termux 通信通道（现有，保持不变）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TermuxBridge.CHANNEL
        ).setMethodCallHandler { call, result ->
            termuxBridge.onMethodCall(call, result)
        }

        // 注册 PTY 终端插件（新增）
        ptyPlugin.registerWith(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 初始化 TermuxBridge 的 BroadcastReceiver 支持
        termuxBridge.ensureReceiverRegistered()
    }

    override fun onDestroy() {
        // 清理 PTY 会话
        ptyPlugin.disposeAll()
        super.onDestroy()
    }
}
