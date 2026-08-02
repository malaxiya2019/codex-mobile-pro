package com.codexmobile.app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 日志导出插件 — Flutter ↔ Native 通信桥
 *
 * 通过 MediaStore API 将日志写入公共 Download 目录：
 * - targetSdk 36（Android 15）下无需任何运行时权限
 * - 使用 RELATIVE_PATH 由系统管理文件归属，符合作用域存储规范
 *
 * MethodChannel: com.codexmobile.app/log/export
 */
class LogExportPlugin(private val context: Context) {

    companion object {
        private const val TAG = "LogExportPlugin"
        const val CHANNEL = "com.codexmobile.app/log/export"
    }

    fun registerWith(engine: FlutterEngine) {
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "writeToDownload" -> {
                    val fileName = call.argument<String>("fileName") ?: "app.log"
                    val content = call.argument<String>("content") ?: ""
                    try {
                        val written = writeToDownload(fileName, content)
                        if (written != null) {
                            result.success(written)
                        } else {
                            result.error(
                                "INSERT_FAILED",
                                "MediaStore 插入失败（无写入权限或 Download 不可用）",
                                null
                            )
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "writeToDownload 失败", e)
                        result.error("WRITE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 通过 MediaStore 将内容写入公共 Download 目录。
     * 返回系统生成的展示文件名；失败返回 null。
     */
    private fun writeToDownload(fileName: String, content: String): String? {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
        }

        val resolver = context.contentResolver
        val uri = resolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            values
        ) ?: return null

        try {
            resolver.openOutputStream(uri)?.use { output ->
                output.write(content.toByteArray(Charsets.UTF_8))
            } ?: return null
        } catch (e: Exception) {
            // 写入失败时清理占位记录，避免留下空文件
            resolver.delete(uri, null, null)
            throw e
        }
        return fileName
    }
}
