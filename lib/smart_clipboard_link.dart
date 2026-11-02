import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 剪切板元数据检测状态
class ClipboardCheckStatus {
  /// 是否有需要读取的新文本内容
  /// (iOS 下当 hasStrings == false、changeCount 未变、或模式未匹配 URL 时为 false；
  /// Android 下当剪切板为空、时间戳未变、超过 TTL 时效或非 URL 时为 false)
  final bool shouldRead;

  /// 状态描述：
  /// - 'empty': 剪切板无文本
  /// - 'unchanged': 次数/时间戳未变，无需重复读取或弹窗
  /// - 'firstLaunchIgnored': 首次启动基线忽略策略生效，忽略历史内容
  /// - 'nonUrl': 剪切板存在文本但非 Web URL，忽略以避免无效弹窗 (iOS 14+ / Android 12+)
  /// - 'sensitive': 命中 Android 13+ 剪贴板敏感标记（如密码/验证码），自动避让保护隐私
  /// - 'notInFocus': Android 10+ 窗口尚未取得焦点，安全避让
  /// - 'expired': 内容已超过最大有效存活时间 (TTL)，判定为陈旧历史数据
  /// - 'throttled': 前后台切换高频防抖命中冷却期，跳过重复检查
  /// - 'newUrl': 剪切板存在新复制的有效 Web URL
  /// - 'newContent': 剪切板存在新复制的文本内容
  /// - 'error': 检测发生异常
  final String? reason;

  /// 当前系统的复制计数或时间戳标识（iOS 为 UIPasteboard.general.changeCount，Android 为时间戳截断值）
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

  /// 读取时对应的 changeCount 或时间戳标识
  final int? changeCount;

  /// 剪切板内容哈希值 (SHA-256)
  final String? contentHash;

  /// 是否为重复内容（内容哈希与上次处理一致）
  final bool isDuplicate;

  /// 是否命中了业务白名单过滤规则
  final bool matchesPattern;

  ClipboardReadResult({
    required this.content,
    this.changeCount,
    this.contentHash,
    this.isDuplicate = false,
    this.matchesPattern = true,
  });

  factory ClipboardReadResult.fromMap(Map<dynamic, dynamic> map) {
    return ClipboardReadResult(
      content: map['content'] as String? ?? '',
      changeCount: map['changeCount'] as int?,
      contentHash: map['contentHash'] as String?,
      isDuplicate: map['isDuplicate'] as bool? ?? false,
      matchesPattern: map['matchesPattern'] as bool? ?? true,
    );
  }

  @override
  String toString() =>
      'ClipboardReadResult(content: $content, changeCount: $changeCount, contentHash: $contentHash, isDuplicate: $isDuplicate, matchesPattern: $matchesPattern)';
}

/// 专为 iOS 隐私权限与 Android 12+ 体验优化的智能剪切板插件 API
class SmartClipboardLink {
  static const MethodChannel _channel = MethodChannel('smart_clipboard_link');

  /// 上次执行检测的本地时间戳（用于防抖）
  static DateTime? _lastCheckTime;

  /// 1. 无感预检状态（**绝对不触发**系统粘贴提示 / Android 12+ Toast）
  ///
  /// - [ignoreFirstLaunch]: 是否启用首次启动基线忽略策略（默认 true）。避免新装 App 误弹历史剪切板。
  /// - [onlyWebURL]: 是否仅针对 Web URL 触发（默认 true）。复制普通文本时不弹授权窗/不触发读取。
  /// - [maxAge]: 剪切板内容最大存活时间（TTL，Android 端生效，默认 null 不限制，推荐 `Duration(hours: 2)`）。
  /// - [cooldown]: 前后台切换高频防抖冷却时长（默认 `Duration(milliseconds: 1500)`），冷却期内静默返回 `throttled`。
  ///
  /// 返回结果中 [ClipboardCheckStatus.shouldRead] 为 true 时，才建议调用 [readContent]。
  static Future<ClipboardCheckStatus> checkStatus({
    bool ignoreFirstLaunch = true,
    bool onlyWebURL = true,
    Duration? maxAge,
    Duration? cooldown = const Duration(milliseconds: 1500),
  }) async {
    // 1. 防抖冷却检查
    final now = DateTime.now();
    if (cooldown != null && _lastCheckTime != null) {
      if (now.difference(_lastCheckTime!) < cooldown) {
        return ClipboardCheckStatus(
          shouldRead: false,
          reason: 'throttled',
        );
      }
    }
    _lastCheckTime = now;

    try {
      final res =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('checkClipboardStatus', {
        'ignoreFirstLaunch': ignoreFirstLaunch,
        'onlyWebURL': onlyWebURL,
        'maxAgeMs': maxAge?.inMilliseconds,
      });
      if (res != null) {
        return ClipboardCheckStatus.fromMap(res);
      }
    } catch (e) {
      debugPrint('SmartClipboardLink.checkStatus error: $e');
    }
    return ClipboardCheckStatus(shouldRead: false, reason: 'error');
  }

  /// 2. 读取剪切板内容（iOS 14/16+ 首次访问会触发系统权限弹窗/横幅；Android 12+ 首次访问触发 Toast）
  ///
  /// - [allowedDomains]: 允许的 URL 域名白名单列表（如 `['example.com', 'link.example.com']`）。
  /// - [urlPrefixes]: 允许的 URL 前缀列表（如 `['https://link.example.com/s/']`）。
  /// - [customPattern]: 自定义正则校验字符串（如 `r'^[A-Z0-9]{6}$'` 口令格式）。
  /// - 若配置了上述规则且内容不匹配，[ClipboardReadResult.matchesPattern] 将为 false。
  static Future<ClipboardReadResult> readContent({
    List<String>? allowedDomains,
    List<String>? urlPrefixes,
    String? customPattern,
  }) async {
    try {
      final res =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('readClipboardContent');
      if (res != null) {
        final result = ClipboardReadResult.fromMap(res);

        // 业务规则白名单校验
        if (result.content.isNotEmpty) {
          final matches = _validatePattern(
            result.content,
            allowedDomains: allowedDomains,
            urlPrefixes: urlPrefixes,
            customPattern: customPattern,
          );
          if (!matches) {
            return ClipboardReadResult(
              content: result.content,
              changeCount: result.changeCount,
              contentHash: result.contentHash,
              isDuplicate: result.isDuplicate,
              matchesPattern: false,
            );
          }
        }

        return result;
      }
    } catch (e) {
      debugPrint('SmartClipboardLink.readContent error: $e');
    }
    return ClipboardReadResult(content: '', matchesPattern: false);
  }

  /// 校验内容是否符合业务规则
  static bool _validatePattern(
    String content, {
    List<String>? allowedDomains,
    List<String>? urlPrefixes,
    String? customPattern,
  }) {
    final trimmed = content.trim();

    // 1. 前缀校验
    if (urlPrefixes != null && urlPrefixes.isNotEmpty) {
      final matchedPrefix = urlPrefixes.any((prefix) => trimmed.startsWith(prefix));
      if (!matchedPrefix) return false;
    }

    // 2. 域名白名单校验
    if (allowedDomains != null && allowedDomains.isNotEmpty) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty) return false;
      final host = uri.host.toLowerCase();
      final matchedDomain = allowedDomains.any((domain) {
        final d = domain.toLowerCase();
        return host == d || host.endsWith('.$d');
      });
      if (!matchedDomain) return false;
    }

    // 3. 自定义正则校验
    if (customPattern != null && customPattern.isNotEmpty) {
      final regExp = RegExp(customPattern);
      if (!regExp.hasMatch(trimmed)) return false;
    }

    return true;
  }

  /// 3. 手动记录当前的 changeCount 或 contentHash
  static Future<bool> recordChangeCount([
    int? count,
    String? contentHash,
  ]) async {
    try {
      final res = await _channel.invokeMethod<bool>('recordChangeCount', {
        ...?count != null ? {'changeCount': count} : null,
        ...?contentHash != null ? {'contentHash': contentHash} : null,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('SmartClipboardLink.recordChangeCount error: $e');
      return false;
    }
  }

  /// 4. 清除系统剪切板内容
  static Future<bool> clear() async {
    try {
      final res = await _channel.invokeMethod<bool>('clearClipboard');
      return res ?? false;
    } catch (e) {
      debugPrint('SmartClipboardLink.clear error: $e');
      return false;
    }
  }

  /// 5. 重置首次启动基线状态及防抖冷却记录
  static Future<bool> resetBaseline() async {
    _lastCheckTime = null;
    try {
      final res = await _channel.invokeMethod<bool>('resetBaseline');
      return res ?? false;
    } catch (e) {
      debugPrint('SmartClipboardLink.resetBaseline error: $e');
      return false;
    }
  }
}
