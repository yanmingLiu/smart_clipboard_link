# smart_clipboard_link

一个专为 iOS 隐私权限（iOS 14 / 16+）与 Android 12+ 隐私体验优化的 Flutter 剪切板管理与智能承接插件。

[English](README.md) | [中文说明](README_CN.md)

---

## 核心特性

- **P0: Android 12+ 零 Toast 无感预检**：利用 `ClipDescription.timestamp` 与 SHA-256 内容哈希对比，彻底消除切前台频繁弹出“已从剪贴板粘贴”系统 Toast 的顽疾。
- **P1: iOS 14+ URL 模式预检**：基于 `detectPatterns([.probableWebURL])`，复制普通文本绝不触发授权弹窗，仅当复制 Web URL 时才触发读取。
- **P2: 首次启动基线忽略策略**：新装 App 首次启动自动将当前剪切板标记为基线（`ignoreFirstLaunch: true`），避免误读用户安装前的无关历史文字。
- **剪切板 TTL 超时时效丢弃**：支持 `maxAge`，超过指定有效时长（如 2 小时）的剪切板内容自动判定为 `expired` 放弃处理。
- **高频切前台防抖冷却**：支持 `cooldown`，在快速切换第三方 App（如支付、授权、系统分享）返回时跳过重复 IPC 交互。
- **业务白名单与正则校验**：内置 `allowedDomains`、`urlPrefixes` 与 `customPattern`，非自身业务域名的链接静默跳过。
- **合规审计友好（零额外权限）**：不申请任何 `<uses-permission>`，自动避让 Android 13+ 敏感数据（`ClipDescription.EXTRA_IS_SENSITIVE`），提供大文本截断保护，轻松通过各大应用市场合规审核。
- **3 秒竞态业务调度模版**：提供标准化 `LinkDispatcher` 架构，优雅处理深链（AppsFlyer / Firebase）与剪切板兜底的竞态仲裁。

---

## 接入指南

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  smart_clipboard_link: ^0.0.2
```

然后执行：

```bash
flutter pub get
```

---

## 基础使用示例

```dart
import 'package:smart_clipboard_link/smart_clipboard_link.dart';

// 1. 无感预检（iOS 不弹窗，Android 12+ 不触发 Toast）
final status = await SmartClipboardLink.checkStatus(
  ignoreFirstLaunch: true, // 启用首次启动基线忽略
  onlyWebURL: true,        // 仅 Web URL 时触发
  maxAge: const Duration(hours: 2), // 2小时 TTL 时效
  cooldown: const Duration(milliseconds: 1500), // 1.5秒切前台防抖
);

if (!status.shouldRead) {
  // empty / unchanged / firstLaunchIgnored / nonUrl / sensitive / expired / throttled
  print('无需读取，原因: ${status.reason}');
  return;
}

// 2. 读取并支持白名单过滤（此时系统弹出权限提示 / Android Toast）
final result = await SmartClipboardLink.readContent(
  allowedDomains: ['example.com', 'link.example.com'],
  urlPrefixes: ['https://link.example.com/s/'],
);

if (result.content.isEmpty || result.isDuplicate || !result.matchesPattern) {
  return;
}

print('读取到内容: ${result.content}');
print('内容哈希: ${result.contentHash}');

// 3. 业务成功承接后清空剪切板
await SmartClipboardLink.clear();
```
