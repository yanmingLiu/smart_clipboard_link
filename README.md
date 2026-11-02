# smart_clipboard_link

A privacy-focused Flutter clipboard plugin designed to eliminate intrusive iOS 14 / 16+ "Paste from Clipboard" system permission dialogs by utilizing native metadata (`hasStrings` and `changeCount`).

[![pub package](https://img.shields.io/pub/v/smart_clipboard_link.svg)](https://pub.dev/packages/smart_clipboard_link)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

[English](README.md) | [中文说明](README_CN.md)

---

## Features

- **Zero-Prompt Preflight (iOS)**: Checks `UIPasteboard.general.hasStrings` and `changeCount` without triggering any iOS privacy authorization alerts.
- **Safe Reading**: Prompts user permission only when a new copy action is detected outside the app. Automatically persists the `changeCount` so subsequent launches remain prompt-free.
- **Clipboard Clearing**: Clear clipboard securely once links/content have been consumed by landing pages.
- **Single Responsibility**: Lightweight, clean architecture without third-party deep-link SDK dependencies.
- **Race Condition Dispatcher Guide**: Ready-to-use business template for handling 3-second timeout race conditions between DeepLink providers (e.g., AppsFlyer) and clipboard fallback.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  smart_clipboard_link: ^0.0.1
```

Then run:

```bash
flutter pub get
```

---

## Basic Usage

```dart
import 'package:smart_clipboard_link/smart_clipboard_link.dart';

// 1. Silent preflight check (does NOT trigger iOS permission dialog)
final status = await SmartClipboardLink.checkStatus();
if (!status.shouldRead) {
  // Clipboard is empty or hasn't changed since last inspection
  return;
}

// 2. Read content (triggers iOS permission alert only on newly copied content)
final result = await SmartClipboardLink.readContent();
print('Content: ${result.content}');
print('Change count: ${result.changeCount}');

// 3. Clear clipboard after consumption
await SmartClipboardLink.clear();
```

---

## Recommended Architecture: 3-Second DeepLink vs Clipboard Race Condition

DeepLink SDKs (such as AppsFlyer, Firebase Dynamic Links) and navigation routers (GetX, GoRouter, Navigator) belong to the application layer. Below is the standard production-ready dispatcher template to orchestrate 3-second race conditions and page replacement:

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

  /// Call on cold launch or when resuming from background
  Future<void> onAppLaunchOrForeground() async {
    _isRaceWindowClosed = false;
    _pendingDeepLinkId = null;
    _pendingClipboardLinkId = null;

    // Start 3-second window
    _raceTimer?.cancel();
    _raceTimer = Timer(const Duration(seconds: 3), _onRaceTimeout);

    // Asynchronously preflight clipboard
    await _checkClipboard();
  }

  /// Call when deep link arrives (e.g. AppsFlyer onDeepLinking)
  void onDeepLinkReceived(String deepLinkId) {
    if (_isRaceWindowClosed) {
      _handleLateDeepLink(deepLinkId);
      return;
    }
    _pendingDeepLinkId = deepLinkId;
    _resolve3sRace();
  }

  Future<void> _checkClipboard() async {
    final status = await SmartClipboardLink.checkStatus();
    if (!status.shouldRead) return;

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
        // Same ID: prioritize the first returned result without duplication
        _openLandingPage(deepId, LinkSource.deepLink);
      } else {
        // Different ID: DeepLink wins, clear clipboard upon success
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
      // DeepLink timed out: fallback to clipboard
      _openLandingPage(clipId, LinkSource.clipboard, onSuccess: () {
        SmartClipboardLink.clear();
      });
    }
  }

  void _handleLateDeepLink(String deepLinkId) {
    if (_currentDisplayLinkId == deepLinkId) return;

    // Override and close clipboard landing page if different
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
    // Route to landing page and invoke onSuccess() upon completion
  }

  void _closeLandingPage() {
    // Pop/dismiss current landing page
  }

  String? _parseLinkId(String text) {
    final uri = Uri.tryParse(text);
    return uri?.pathSegments.lastOrNull;
  }
}
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
