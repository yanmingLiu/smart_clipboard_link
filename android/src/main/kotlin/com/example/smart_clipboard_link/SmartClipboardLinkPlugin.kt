package com.example.smart_clipboard_link

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class SmartClipboardLinkPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private var context: Context? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "smart_clipboard_link")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    val clipboard = context?.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    when (call.method) {
      "checkClipboardStatus" -> {
        if (clipboard == null || !clipboard.hasPrimaryClip()) {
          result.success(mapOf("shouldRead" to false, "reason" to "empty"))
          return
        }
        val description = clipboard.primaryClipDescription
        val hasText = description?.hasMimeType(android.content.ClipDescription.MIMETYPE_TEXT_PLAIN) == true ||
                      description?.hasMimeType(android.content.ClipDescription.MIMETYPE_TEXT_HTML) == true
        if (!hasText) {
          result.success(mapOf("shouldRead" to false, "reason" to "empty"))
          return
        }
        // Android 无系统 changeCount，统一标记允许读取，由上层哈希/文本判断
        result.success(mapOf("shouldRead" to true, "changeCount" to 0))
      }
      "readClipboardContent" -> {
        val clip = clipboard?.primaryClip
        val text = if (clip != null && clip.itemCount > 0) {
          clip.getItemAt(0).coerceToText(context).toString()
        } else {
          ""
        }
        result.success(mapOf("content" to text, "changeCount" to 0))
      }
      "recordChangeCount" -> {
        result.success(true)
      }
      "clearClipboard" -> {
        if (clipboard != null) {
          try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
              clipboard.clearPrimaryClip()
            } else {
              clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
          } catch (_: Exception) {}
        }
        result.success(true)
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    context = null
  }
}
