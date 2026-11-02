## 0.0.1

* Initial release.
* Zero-prompt clipboard status checking on iOS using native `UIPasteboard.general.hasStrings` and `changeCount`.
* Safe content reading with automatic `changeCount` persistence.
* Support manual `changeCount` tracking and system clipboard clearing.
* Comprehensive business dispatcher template for 3-second DeepLink (e.g. AppsFlyer) vs clipboard race conditions.
