## 0.0.2

* **P0 Optimization**: Android zero-toast clipboard preflight using `ClipDescription.timestamp` and SHA-256 content hash comparison, completely eliminating frequent Android 12+ "Pasted from clipboard" toasts when switching to foreground.
* **P1 Optimization**: iOS 14+ `detectPatterns([.probableWebURL])` integration, ensuring ordinary copied text does not trigger system authorization alerts; only genuine Web URLs trigger permission prompts.
* **P2 Optimization**: First launch baseline ignore strategy (`ignoreFirstLaunch: true`), preventing newly installed apps from reading and popping up unrelated historical clipboard text.
* Added `maxAge` TTL expiration support on Android to discard stale historical clipboard content.
* Added `cooldown` debounce support to eliminate redundant cross-process IPC during rapid app foreground switching.
* Added URL pattern matching and whitelist filtering (`allowedDomains`, `urlPrefixes`, `customPattern`).
* Enhanced zero-permission privacy compliance: Android 13+ sensitive data avoidance (`ClipDescription.EXTRA_IS_SENSITIVE`), Android 10+ window focus exception handling, and large text length truncation protection.
* Added `isDuplicate` flag and `contentHash` in `ClipboardReadResult` for reliable content deduplication.
* Added `resetBaseline` API for testing and reset scenarios.

## 0.0.1

* Initial release.
* Zero-prompt clipboard status checking on iOS using native `UIPasteboard.general.hasStrings` and `changeCount`.
* Safe content reading with automatic `changeCount` persistence.
* Support manual `changeCount` tracking and system clipboard clearing.
* Comprehensive business dispatcher template for 3-second DeepLink (e.g. AppsFlyer) vs clipboard race conditions.
