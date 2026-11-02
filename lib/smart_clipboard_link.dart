import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 剪切板元数据检测状态
class ClipboardCheckStatus {
  /// 是否有需要读取的新文本内容
  /// (iOS 下当 hasStrings == false 或 changeCount 未发生变化时为 false)
  final bool shouldRead;

  /// 状态描述：empty (剪切板无文本) / unchanged (次数未变无需弹窗) / newContent (有新内容) / error
  final String? reason;

  /// 当前系统的复制计数（iOS 为 UIPasteboard.general.changeCount，Android 为 0）
  final int? changeCount;

  ClipboardCheckStatus({
    required this.shouldRead,
    this.reason,
    this.changeCount,
  });

  factory ClipboardCheckStatus.fromMap(Map<dynamic, dynamic> map) {
    return ClipboardCheckStatus(
      shouldRead: map['shouldRead'] as bool? ?? false,
      reason: map['reason'] as String?,
      changeCount: map['changeCount'] as int?,
    );
  }

  @override
  String toString() =>
      'ClipboardCheckStatus(shouldRead: $shouldRead, reason: $reason, changeCount: $changeCount)';
}

/// 剪切板实际读取结果
class ClipboardReadResult {
  /// 剪切板文本内容
  final String content;

  /// 读取时对应的 changeCount
  final int? changeCount;

  ClipboardReadResult({
    required this.content,
    this.changeCount,
  });

  factory ClipboardReadResult.fromMap(Map<dynamic, dynamic> map) {
    return ClipboardReadResult(
      content: map['content'] as String? ?? '',
      changeCount: map['changeCount'] as int?,
    );
  }

  @override
  String toString() =>
      'ClipboardReadResult(content: $content, changeCount: $changeCount)';
}

/// 专为 iOS 隐私权限优化的剪切板插件 API
class SmartClipboardLink {
  static const MethodChannel _channel = MethodChannel('smart_clipboard_link');

  /// 1. 无感预检状态（iOS 使用 hasStrings 与 changeCount 判定，**绝对不触发**系统粘贴提示）
  ///
  /// 返回结果中 [ClipboardCheckStatus.shouldRead] 为 true 时，才建议调用 [readContent]。
  static Future<ClipboardCheckStatus> checkStatus() async {
    try {
      final res =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('checkClipboardStatus');
      if (res != null) {
        return ClipboardCheckStatus.fromMap(res);
      }
    } catch (e) {
      debugPrint('SmartClipboardLink.checkStatus error: $e');
    }
    return ClipboardCheckStatus(shouldRead: false, reason: 'error');
  }

  /// 2. 读取剪切板内容（iOS 14/16+ 首次访问会触发系统权限弹窗/横幅）
  ///
  /// - 成功读取后，插件内部会自动将当次 `changeCount` 持久化，后续冷热启动调用 [checkStatus] 不会再弹窗。
  static Future<ClipboardReadResult> readContent() async {
    try {
      final res =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('readClipboardContent');
      if (res != null) {
        return ClipboardReadResult.fromMap(res);
      }
    } catch (e) {
      debugPrint('SmartClipboardLink.readContent error: $e');
    }
    return ClipboardReadResult(content: '');
  }

  /// 3. 手动记录当前的 changeCount
  ///
  /// 场景：当上层捕获到用户拒绝授权或外部业务判定无需继续处理该次复制时，
  /// 调用此方法将当前的 [changeCount] 记入原生持久化存储，避免下次冷热启动再次进入新内容判定流程。
  static Future<bool> recordChangeCount([int? count]) async {
    try {
      final res = await _channel.invokeMethod<bool>('recordChangeCount', {
        ...?count != null ? {'changeCount': count} : null,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('SmartClipboardLink.recordChangeCount error: $e');
      return false;
    }
  }

  /// 4. 清除系统剪切板内容
  ///
  /// 规范推荐在业务成功拉起承接页后调用，防止剪切板残留。
  static Future<bool> clear() async {
    try {
      final res = await _channel.invokeMethod<bool>('clearClipboard');
      return res ?? false;
    } catch (e) {
      debugPrint('SmartClipboardLink.clear error: $e');
      return false;
    }
  }
}
