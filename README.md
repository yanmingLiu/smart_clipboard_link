# smart_clipboard_link

一个专为 iOS 隐私权限（iOS 14 / 16+）优化的无感知剪切板检测与管理 Flutter 插件。

---

## 一、核心特性与设计哲学

在 iOS 14 / 16+ 之后，随意调用读取剪切板 API 会频繁弹出“允许粘贴”系统授权对话框或系统横幅，严重损害用户体验。

本插件遵循**单一职责原则**，专注解决原生剪切板的无感检测与清理：
1. **零权限弹窗预检（`checkStatus`）**：
   - 依赖 iOS 原生 `UIPasteboard.general.hasStrings` 过滤空文本（**无弹窗**）。
   - 依赖 `UIPasteboard.general.changeCount` 对比本地 `lastChangeCount`（**无弹窗**）。
   - 只有用户在外部产生**新的复制动作**时，`shouldRead` 才会返回 `true`。
2. **安全读取与自动记录（`readContent`）**：
   - 仅在确认有新复制时由业务层按需触发，读取后原生内部自动持久化记录本次 `changeCount`，冷热启动不重复弹窗。
3. **安全清理（`clear`）**：
   - 支持业务承接成功后直接清空剪切板。

---

## 二、基础 API

```dart
import 'package:smart_clipboard_link/smart_clipboard_link.dart';

// 1. 无感预检（不触发 iOS 授权弹窗）
final status = await SmartClipboardLink.checkStatus();
if (!status.shouldRead) {
  // 剪切板为空，或该次复制之前已处理/已拒绝过，直接 return
  return;
}

// 2. 确认有新内容后读取（此时 iOS 触发授权提示）
final result = await SmartClipboardLink.readContent();
print('内容: ${result.content}, changeCount: ${result.changeCount}');

// 3. 业务使用完成后清空剪切板
await SmartClipboardLink.clear();
```

---

## 三、业务最佳实践：结合深链（如 AppsFlyer）实现 3 秒竞态与兜底

因为深链 SDK（如 AppsFlyer、Firebase Dynamic Links）和承接页路由逻辑属于具体业务层，建议在宿主 App 业务层封装调度器（Coordinator）。

以下为推荐的业务层实现模板：

```dart
import 'dart:async';
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

  /// 冷启动或前台唤醒时调用
  Future<void> onAppLaunchOrForeground() async {
    _isRaceWindowClosed = false;
    _pendingDeepLinkId = null;
    _pendingClipboardLinkId = null;

    // 开启 3 秒竞争窗口
    _raceTimer?.cancel();
    _raceTimer = Timer(const Duration(seconds: 3), _onRaceTimeout);

    // 检查剪切板
    await _checkClipboard();
  }

  /// 业务层收到深链回调时调用（如 AppsFlyer onDeepLinking）
  void onDeepLinkReceived(String deepLinkId) {
    if (_isRaceWindowClosed) {
      _handleLateDeepLink(deepLinkId);
      return;
    }
    _pendingDeepLinkId = deepLinkId;
    _resolve3sRace();
  }

  Future<void> _checkClipboard() async {
    // 1. 无感检测
    final status = await SmartClipboardLink.checkStatus();
    if (!status.shouldRead) return;

    // 2. 读取文本
    final result = await SmartClipboardLink.readContent();
    final linkId = _parseLinkId(result.content);
    if (linkId == null || linkId.isEmpty) return;

    _pendingClipboardLinkId = linkId;
    if (!_isRaceWindowClosed) {
      _resolve3sRace();
    }
  }

  void _resolve3sRace() {
    if (_pendingDeepLinkId != null) {
      _raceTimer?.cancel();
      _isRaceWindowClosed = true;

      final deepId = _pendingDeepLinkId!;
      final clipId = _pendingClipboardLinkId;

      if (clipId != null && clipId == deepId) {
        // ID 相同，优先展示先返回结果的
        _openLandingPage(deepId, LinkSource.deepLink);
      } else {
        // ID 不同或剪切板无效，深链优先
        _openLandingPage(deepId, LinkSource.deepLink, onSuccess: () {
          if (clipId != null) SmartClipboardLink.clear();
        });
      }
    }
  }

  void _onRaceTimeout() {
    _isRaceWindowClosed = true;
    final clipId = _pendingClipboardLinkId;
    if (clipId != null && clipId.isNotEmpty) {
      // 3秒深链未到达，剪切板兜底
      _openLandingPage(clipId, LinkSource.clipboard, onSuccess: () {
        SmartClipboardLink.clear();
      });
    }
  }

  void _handleLateDeepLink(String deepLinkId) {
    if (_currentDisplayLinkId == deepLinkId) return;

    // 若当前正在展示剪切板兜底页，深链强制覆盖并关闭旧承接页
    if (_currentDisplaySource == LinkSource.clipboard) {
      _closeLandingPage();
      _openLandingPage(deepLinkId, LinkSource.deepLink, onSuccess: () {
        SmartClipboardLink.clear();
      });
    } else {
      _openLandingPage(deepLinkId, LinkSource.deepLink);
    }
  }

  void _openLandingPage(String linkId, LinkSource source, {VoidCallback? onSuccess}) {
    _currentDisplayLinkId = linkId;
    _currentDisplaySource = source;
    // 调用项目实际路由进行跳转，并在展示成功后触发 onSuccess
    // AppRouter.openLandingPage(linkId).then((ok) { if (ok) onSuccess?.call(); });
  }

  void _closeLandingPage() {
    // 关闭当前正在展示的承接页
  }

  String? _parseLinkId(String text) {
    // 正则提取 link_id
    final uri = Uri.tryParse(text);
    return uri?.pathSegments.lastOrNull;
  }
}
```
