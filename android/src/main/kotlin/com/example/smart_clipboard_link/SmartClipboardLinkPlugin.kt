package com.example.smart_clipboard_link

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.view.textclassifier.TextClassifier
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.security.MessageDigest

class SmartClipboardLinkPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private var context: Context? = null

  companion object {
    private const val PREFS_NAME = "smart_clipboard_link_prefs"
    private const val KEY_LAST_TIMESTAMP = "kLastClipboardTimestamp_smart_link"
    private const val KEY_LAST_CONTENT_HASH = "kLastClipboardHash_smart_link"
    private const val KEY_HAS_RECORDED_BASELINE = "kHasRecordedBaseline_smart_link"

    // 单次承接文本最大字符保护长度（4096 字符足以容纳任意合法 URL/口令，同时杜绝 Binder 内存溢出）
    private const val MAX_CLIPBOARD_TEXT_LENGTH = 4096
  }

  private val prefs: SharedPreferences?
    get() = context?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "smart_clipboard_link")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    val clipboard = context?.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    when (call.method) {
      "checkClipboardStatus" -> {
        try {
          if (clipboard == null || !clipboard.hasPrimaryClip()) {
            result.success(mapOf("shouldRead" to false, "reason" to "empty"))
            return
          }

          val description = clipboard.primaryClipDescription
          val hasText = description?.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) == true ||
                        description?.hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML) == true
          if (!hasText) {
            result.success(mapOf("shouldRead" to false, "reason" to "empty"))
            return
          }

          // 1. Android 13+ (API 33+) 敏感数据合规避让（零权限，帮助隐私过审）
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val isSensitive = description?.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) ?: false
            if (isSensitive) {
              result.success(mapOf("shouldRead" to false, "reason" to "sensitive"))
              return
            }
          }

          val ignoreFirstLaunch = call.argument<Boolean>("ignoreFirstLaunch") ?: true
          val onlyWebURL = call.argument<Boolean>("onlyWebURL") ?: true
          val maxAgeMs = call.argument<Number>("maxAgeMs")?.toLong()

          val currentTs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            description?.timestamp ?: 0L
          } else {
            0L
          }
          val changeCountId = (currentTs and 0x7FFFFFFF).toInt()

          val sp = prefs
          val hasRecordedBaseline = sp?.getBoolean(KEY_HAS_RECORDED_BASELINE, false) == true

          // 2. P2 首次启动基线忽略策略：新装首次启动时将当前剪切板标记为基线
          if (!hasRecordedBaseline) {
            if (ignoreFirstLaunch) {
              sp?.edit()
                ?.putBoolean(KEY_HAS_RECORDED_BASELINE, true)
                ?.putLong(KEY_LAST_TIMESTAMP, currentTs)
                ?.apply()
              result.success(
                mapOf(
                  "shouldRead" to false,
                  "reason" to "firstLaunchIgnored",
                  "changeCount" to changeCountId
                )
              )
              return
            } else {
              sp?.edit()?.putBoolean(KEY_HAS_RECORDED_BASELINE, true)?.apply()
            }
          }

          // 3. 剪切板 TTL 超时过期丢弃策略
          if (maxAgeMs != null && maxAgeMs > 0 && currentTs > 0) {
            val now = System.currentTimeMillis()
            val age = now - currentTs
            if (age > maxAgeMs) {
              sp?.edit()?.putLong(KEY_LAST_TIMESTAMP, currentTs)?.apply()
              result.success(
                mapOf(
                  "shouldRead" to false,
                  "reason" to "expired",
                  "changeCount" to changeCountId
                )
              )
              return
            }
          }

          // 4. P0 无感时间戳对比（Android 8.0+ / 12+）：未发生新复制时不碰 primaryClip，消除 Toast
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && currentTs != 0L) {
            val lastTs = sp?.getLong(KEY_LAST_TIMESTAMP, -1L) ?: -1L
            if (currentTs == lastTs) {
              result.success(
                mapOf(
                  "shouldRead" to false,
                  "reason" to "unchanged",
                  "changeCount" to changeCountId
                )
              )
              return
            }
          }

          // 5. Android 12+ (API 31+) URL 无感分类探测（若开启 onlyWebURL）
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && onlyWebURL) {
            if (description?.classificationStatus == ClipDescription.CLASSIFICATION_COMPLETE) {
              val score = description.getConfidenceScore(TextClassifier.TYPE_URL)
              if (score < 0.5f) {
                sp?.edit()?.putLong(KEY_LAST_TIMESTAMP, currentTs)?.apply()
                result.success(
                  mapOf(
                    "shouldRead" to false,
                    "reason" to "nonUrl",
                    "changeCount" to changeCountId
                  )
                )
                return
              }
            }
          }

          // 有新内容待读取
          result.success(
            mapOf(
              "shouldRead" to true,
              "reason" to "newContent",
              "changeCount" to changeCountId
            )
          )
        } catch (e: SecurityException) {
          // Android 10+ 焦点未完全就绪异常防御
          result.success(mapOf("shouldRead" to false, "reason" to "notInFocus"))
        } catch (_: Exception) {
          result.success(mapOf("shouldRead" to false, "reason" to "error"))
        }
      }

      "readClipboardContent" -> {
        try {
          val clip = clipboard?.primaryClip
          var text = if (clip != null && clip.itemCount > 0) {
            clip.getItemAt(0).coerceToText(context).toString()
          } else {
            ""
          }

          // 大文本安全截断保护（防止极端大文本引发 Binder TransactionTooLargeException）
          if (text.length > MAX_CLIPBOARD_TEXT_LENGTH) {
            text = text.substring(0, MAX_CLIPBOARD_TEXT_LENGTH)
          }

          val currentHash = calculateSha256(text)
          val description = clipboard?.primaryClipDescription
          val currentTs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            description?.timestamp ?: 0L
          } else {
            0L
          }
          val changeCountId = (currentTs and 0x7FFFFFFF).toInt()

          val sp = prefs
          val lastHash = sp?.getString(KEY_LAST_CONTENT_HASH, null)
          val isDuplicate = (lastHash != null && lastHash == currentHash)

          sp?.edit()
            ?.putString(KEY_LAST_CONTENT_HASH, currentHash)
            ?.putLong(KEY_LAST_TIMESTAMP, currentTs)
            ?.putBoolean(KEY_HAS_RECORDED_BASELINE, true)
            ?.apply()

          result.success(
            mapOf(
              "content" to text,
              "changeCount" to changeCountId,
              "contentHash" to currentHash,
              "isDuplicate" to isDuplicate
            )
          )
        } catch (e: SecurityException) {
          result.success(
            mapOf(
              "content" to "",
              "changeCount" to 0,
              "contentHash" to "",
              "isDuplicate" to false
            )
          )
        } catch (_: Exception) {
          result.success(
            mapOf(
              "content" to "",
              "changeCount" to 0,
              "contentHash" to "",
              "isDuplicate" to false
            )
          )
        }
      }

      "recordChangeCount" -> {
        val sp = prefs
        val editor = sp?.edit()
        val customCount = call.argument<Int>("changeCount")
        val customHash = call.argument<String>("contentHash")

        if (customHash != null) {
          editor?.putString(KEY_LAST_CONTENT_HASH, customHash)
        }

        val currentTs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          clipboard?.primaryClipDescription?.timestamp ?: 0L
        } else {
          0L
        }
        val tsToSave = if (customCount != null) customCount.toLong() else currentTs
        editor?.putLong(KEY_LAST_TIMESTAMP, tsToSave)
        editor?.putBoolean(KEY_HAS_RECORDED_BASELINE, true)
        editor?.apply()

        result.success(true)
      }

      "clearClipboard" -> {
        if (clipboard != null) {
          try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
              clipboard.clearPrimaryClip()
            } else {
              clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
          } catch (_: Exception) {}
        }

        val description = clipboard?.primaryClipDescription
        val currentTs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          description?.timestamp ?: 0L
        } else {
          0L
        }
        prefs?.edit()
          ?.remove(KEY_LAST_CONTENT_HASH)
          ?.putLong(KEY_LAST_TIMESTAMP, currentTs)
          ?.apply()

        result.success(true)
      }

      "resetBaseline" -> {
        prefs?.edit()?.clear()?.apply()
        result.success(true)
      }

      else -> {
        result.notImplemented()
      }
    }
  }

  private fun calculateSha256(text: String): String {
    if (text.isEmpty()) return ""
    return try {
      val digest = MessageDigest.getInstance("SHA-256")
      val hashBytes = digest.digest(text.toByteArray(Charsets.UTF_8))
      hashBytes.joinToString("") { "%02x".format(it) }
    } catch (_: Exception) {
      text.hashCode().toString()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    context = null
  }
}
