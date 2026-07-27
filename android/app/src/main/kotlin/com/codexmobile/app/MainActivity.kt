package com.codexmobile.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Codex Mobile Pro 主 Activity
///
/// 注册 MethodChannel，处理 Flutter ↔ Native 通信。
class MainActivity : FlutterActivity() {

    private val termuxBridge by lazy { TermuxBridge(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册 Termux 通信通道
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TermuxBridge.CHANNEL
        ).setMethodCallHandler { call, result ->
            termuxBridge.onMethodCall(call, result)
        }
    }
}
