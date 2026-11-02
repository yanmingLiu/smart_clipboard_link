---
name: smart-clipboard-link
description: 指导与自动化接入 smart_clipboard_link 插件。支持 iOS 零弹窗隐私预检（hasStrings & changeCount）、剪切板安全读取与清理、以及业务层 3 秒竞态（深链/AppsFlyer vs 剪切板兜底/覆盖）调度。
---

# Smart Clipboard Link 接入指南

本 Skill 用于指导 AI 或开发者在任何 Flutter 项目中快速、规范地集成 `smart_clipboard_link` 插件，解决 iOS 14/16+ 剪切板频繁弹窗问题，并落地完整的深链（DeepLink/AppsFlyer）与剪切板 3 秒竞态兜底方案。

---

## 一、添加插件依赖

在目标 Flutter 项目的 `pubspec.yaml` 中添加本地路径或 Git 依赖：

```yaml
dependencies:
  flutter:
    sdk: flutter
  smart_clipboard_link:
    path: /Users/ai3/Documents/smart_clipboard_link # 本地插件路径或 git 仓库
```

保存后执行：
```bash
flutter pub get # 或 fvm flutter pub get
```

---

## 二、插件 API 速查

插件本身职责纯粹，仅暴露底层的无感预检、读取、记录与清理能力：

```dart
import 'package:smart_clipboard_link/smart_clipboard_link.dart';

// 1. 无感预检（iOS 不弹窗）：检查是否有新复制的文本
final status = await SmartClipboardLink.checkStatus();
if (!status.shouldRead) {
  // empty（为空）或 unchanged（未发生新复制），直接 return
  return;
}

// 2. 确认有新复制后读取（此时 iOS 会触发系统授权提示）
// 读取成功后原生会自动记录当前 changeCount，冷热启动不再弹窗
final result = await SmartClipboardLink.readContent();
print('读取到内容: ${result.content}');

// 3. 业务完成承接后清空剪切板
await SmartClipboardLink.clear();

// 4. 手动记录 changeCount（如用户拒绝授权时）
await SmartClipboardLink.recordChangeCount();
```

---

## 三、业务层 3 秒竞态与深链调度落地（标准化实现）

由于深链 SDK（如 AppsFlyer / Firebase）及页面路由（Navigator / GetX / GoRouter）属于业务层，业务项目建议直接在项目内创建调度器文件（如 `lib/manager/link_dispatcher.dart`）：

### 推荐的 `LinkDispatcher.dart` 完整实现：

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smart_clipboard_link/smart_clipboard_link.dart';

enum LinkSource { deepLink, clipboard }

class LinkDispatcher {
  static final LinkDispatcher instance = LinkDispatcher._();
  LinkDispatcher._();

  Timer? _raceTimer;
  bool _isRaceWindowClosed = false;

  String? _pendingDeepLinkId;
  String? _pendingClipboardLinkId;

  String? _currentDisplayLinkId;
  LinkSource? _currentDisplaySource;

  /// 外部配置：从文本中提取 link_id 的逻辑
  String? Function(String text)? linkIdParser;

  /// 外部配置：跳转承接页回调，返回 true 表示展示成功
  Future<bool> Function(String linkId, LinkSource source)? onNavigateToLanding;

  /// 外部配置：关闭/覆盖旧承接页回调
  Future<void> Function()? onCloseLanding;

  /// 1. 冷启动 或 从后台切回前台（生命周期 resumed）时调用
  Future<void> onAppLaunchOrForeground() async {
    _isRaceWindowClosed = false;
    _pendingDeepLinkId = null;
    _pendingClipboardLinkId = null;

    // 开启 3 秒竞争窗口
    _raceTimer?.cancel();
    _raceTimer = Timer(const Duration(seconds: 3), _onRaceTimeout);

    // 异步执行剪切板预检
    await _checkClipboard();
  }

  /// 2. 外部深链 SDK 回调（如 AppsFlyer onDeepLinking）收到 linkId 时调用
  void onDeepLinkReceived(String deepLinkId) {
    if (deepLinkId.isEmpty) return;

    if (_isRaceWindowClosed) {
      _handleLateDeepLink(deepLinkId);
      return;
    }

    _pendingDeepLinkId = deepLinkId;
    _resolve3sRace();
  }

  Future<void> _checkClipboard() async {
    // 无感检测（不触发 iOS 授权提示）
    final status = await SmartClipboardLink.checkStatus();
    if (!status.shouldRead) return;

    // 触发读取
    final result = await SmartClipboardLink.readContent();
    if (result.content.isEmpty) return;

    final linkId = linkIdParser != null
        ? linkIdParser!(result.content)
        : result.content.trim();

    if (linkId == null || linkId.isEmpty) return;

    _pendingClipboardLinkId = linkId;

    if (!_isRaceWindowClosed) {
      _resolve3sRace();
    }
  }

  /// 3 秒内竞态仲裁
  void _resolve3sRace() {
    if (_pendingDeepLinkId != null) {
      _raceTimer?.cancel();
      _isRaceWindowClosed = true;

      final deepId = _pendingDeepLinkId!;
      final clipId = _pendingClipboardLinkId;

      if (clipId != null && clipId == deepId) {
        // ID 相同，优先展示先返回的，不重复展示
        _navigate(deepId, LinkSource.deepLink);
      } else {
        // ID 不同 或 剪切板未获取到，使用深链拉起
        _navigate(deepId, LinkSource.deepLink, onSuccess: () {
          // 若深链与剪切板不同且深链承接成功，清理剪切板
          if (clipId != null) {
            SmartClipboardLink.clear();
          }
        });
      }
    }
  }

  /// 3 秒超时：深链未在 3 秒内到达，剪切板兜底
  void _onRaceTimeout() {
    _isRaceWindowClosed = true;
    final clipId = _pendingClipboardLinkId;
    if (clipId != null && clipId.isNotEmpty) {
      _navigate(clipId, LinkSource.clipboard, onSuccess: () {
        // 剪切板兜底成功后清空剪切板
        SmartClipboardLink.clear();
      });
    }
  }

  /// 3 秒后延迟收到的深链
  Future<void> _handleLateDeepLink(String deepLinkId) async {
    // link_id 相同，不重复展示
    if (_currentDisplayLinkId == deepLinkId) return;

    // 若当前正在展示剪切板承接页，深链强制覆盖并关闭剪切板承接页
    if (_currentDisplaySource == LinkSource.clipboard) {
      if (onCloseLanding != null) {
        await onCloseLanding!();
      }
      _currentDisplayLinkId = null;
      _currentDisplaySource = null;

      _navigate(deepLinkId, LinkSource.deepLink, onSuccess: () {
        SmartClipboardLink.clear();
      });
    } else {
      _navigate(deepLinkId, LinkSource.deepLink);
    }
  }

  Future<void> _navigate(String linkId, LinkSource source, {VoidCallback? onSuccess}) async {
    _currentDisplayLinkId = linkId;
    _currentDisplaySource = source;

    if (onNavigateToLanding != null) {
      final success = await onNavigateToLanding!(linkId, source);
      if (success) {
        onSuccess?.call();
      }
    }
  }

  /// 承接页关闭时重置状态
  void onLandingPageDismissed(String linkId) {
    if (_currentDisplayLinkId == linkId) {
      _currentDisplayLinkId = null;
      _currentDisplaySource = null;
    }
  }
}
```

---

## 四、接入验证清单（Checklist）

集成完成后，按以下清单核验：
1. **冷启动无新复制**：iOS 绝对不弹窗（控制台无 `readClipboardContent` 触发）。
2. **复制新链接后冷启动**：
   - 3 秒内收到深链：深链直接进入承接页。
   - 3 秒内无深链：弹出 iOS 粘贴提示，允许后剪切板拉起承接页并清空剪切板。
3. **拒绝授权测试**：用户点击拒绝后，原生记录 `changeCount`，热启动切回 App 不再重复提示。
4. **延迟深链覆盖**：剪切板拉起承接页后，如果异步到达了不同 link_id 的深链，应正确关闭旧承接页并展示新深链承接页。
