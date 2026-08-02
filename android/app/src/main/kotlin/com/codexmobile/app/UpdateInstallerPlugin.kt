package com.codexmobile.app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 更新安装插件 — Flutter ↔ Native 通信桥
 *
 * 安装已下载的 APK：
 * - 用 FileProvider 生成 content:// URI（避免 FileUriExposedException）
 * - ACTION_VIEW + application/vnd.android.package-archive 拉起系统包安装器
 * - Android 8+ 需要 REQUEST_INSTALL_PACKAGES 权限；
 *   Android 13+ 首次安装未知来源应用时系统会引导用户授权
 *
 * MethodChannel: com.codexmobile.app/update
 */
class UpdateInstallerPlugin(private val context: Context) {

    companion object {
        private const val TAG = "UpdateInstallerPlugin"
        const val CHANNEL = "com.codexmobile.app/update"
        const val AUTHORITY = "com.codexmobile.app.fileprovider"
    }

    fun registerWith(engine: FlutterEngine) {
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("NO_PATH", "缺少 APK 路径", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(File(path))
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "installApk 失败", e)
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 通过系统包安装器安装 APK。
     * 成功仅表示已拉起安装器，实际安装结果由系统 UI 决定。
     */
    private fun installApk(apk: File) {
        if (!apk.exists()) {
            throw IllegalStateException("APK 不存在: ${apk.absolutePath}")
        }

        val uri: Uri = FileProvider.getUriForFile(context, AUTHORITY, apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            throw IllegalStateException("系统没有可用的包安装器", e)
        }
    }
}
