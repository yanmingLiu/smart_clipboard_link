import Flutter
import UIKit
import CommonCrypto

public class SmartClipboardLinkPlugin: NSObject, FlutterPlugin {
  private static let channelName = "smart_clipboard_link"
  private let keyLastChangeCount = "kLastClipboardChangeCount_smart_link"
  private let keyLastContentHash = "kLastClipboardHash_smart_link"
  private let keyHasRecordedBaseline = "kHasRecordedBaseline_smart_link"

  // 单次承接文本最大字符保护长度
  private let maxClipboardTextLength = 4096

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = SmartClipboardLinkPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkClipboardStatus":
      let pasteboard = UIPasteboard.general
      let args = call.arguments as? [String: Any]
      let ignoreFirstLaunch = args?["ignoreFirstLaunch"] as? Bool ?? true
      let onlyWebURL = args?["onlyWebURL"] as? Bool ?? true

      // 1. 无感检查：是否有文本
      if !pasteboard.hasStrings {
        result([
          "shouldRead": false,
          "reason": "empty"
        ])
        return
      }

      let currentCount = pasteboard.changeCount
      let hasRecordedBaseline = UserDefaults.standard.bool(forKey: keyHasRecordedBaseline)

      // 2. P2 首次启动基线忽略策略：新装首次启动时将当前剪切板标记为基线
      if !hasRecordedBaseline {
        if ignoreFirstLaunch {
          UserDefaults.standard.set(true, forKey: keyHasRecordedBaseline)
          UserDefaults.standard.set(currentCount, forKey: keyLastChangeCount)
          UserDefaults.standard.synchronize()
          result([
            "shouldRead": false,
            "reason": "firstLaunchIgnored",
            "changeCount": currentCount
          ])
          return
        } else {
          UserDefaults.standard.set(true, forKey: keyHasRecordedBaseline)
          UserDefaults.standard.synchronize()
        }
      }

      // 3. 无感检查：changeCount 是否一致
      let lastCount = UserDefaults.standard.integer(forKey: keyLastChangeCount)
      let hasRecordedCount = UserDefaults.standard.object(forKey: keyLastChangeCount) != nil
      if hasRecordedCount && currentCount == lastCount {
        result([
          "shouldRead": false,
          "reason": "unchanged",
          "changeCount": currentCount
        ])
        return
      }

      // 4. P1 iOS 14+ URL 模式无感检测：普通文本不弹授权窗，仅 URL 触发读取
      if #available(iOS 14.0, *), onlyWebURL {
        pasteboard.detectPatterns(for: [.probableWebURL]) { detectResult in
          switch detectResult {
          case .success(let patterns):
            if !patterns.contains(.probableWebURL) {
              UserDefaults.standard.set(currentCount, forKey: keyLastChangeCount)
              UserDefaults.standard.synchronize()
              result([
                "shouldRead": false,
                "reason": "nonUrl",
                "changeCount": currentCount
              ])
              return
            }

            result([
              "shouldRead": true,
              "reason": "newUrl",
              "changeCount": currentCount
            ])
          case .failure:
            result([
              "shouldRead": true,
              "reason": "newContent",
              "changeCount": currentCount
            ])
          }
        }
      } else {
        result([
          "shouldRead": true,
          "reason": "newContent",
          "changeCount": currentCount
        ])
      }

    case "readClipboardContent":
      let pasteboard = UIPasteboard.general
      let currentCount = pasteboard.changeCount

      var content = pasteboard.string ?? ""
      // 大文本安全截断保护
      if content.count > maxClipboardTextLength {
        content = String(content.prefix(maxClipboardTextLength))
      }

      let currentHash = calculateSha256(content)
      let lastHash = UserDefaults.standard.string(forKey: keyLastContentHash)
      let isDuplicate = (lastHash != nil && lastHash == currentHash)

      UserDefaults.standard.set(currentCount, forKey: keyLastChangeCount)
      UserDefaults.standard.set(currentHash, forKey: keyLastContentHash)
      UserDefaults.standard.set(true, forKey: keyHasRecordedBaseline)
      UserDefaults.standard.synchronize()

      result([
        "content": content,
        "changeCount": currentCount,
        "contentHash": currentHash,
        "isDuplicate": isDuplicate
      ])

    case "recordChangeCount":
      let pasteboard = UIPasteboard.general
      let countToRecord: Int
      let args = call.arguments as? [String: Any]
      if let count = args?["changeCount"] as? Int {
        countToRecord = count
      } else {
        countToRecord = pasteboard.changeCount
      }
      UserDefaults.standard.set(countToRecord, forKey: keyLastChangeCount)
      if let hash = args?["contentHash"] as? String {
        UserDefaults.standard.set(hash, forKey: keyLastContentHash)
      }
      UserDefaults.standard.set(true, forKey: keyHasRecordedBaseline)
      UserDefaults.standard.synchronize()
      result(true)

    case "clearClipboard":
      UIPasteboard.general.items = []
      let currentCount = UIPasteboard.general.changeCount
      UserDefaults.standard.set(currentCount, forKey: keyLastChangeCount)
      UserDefaults.standard.removeObject(forKey: keyLastContentHash)
      UserDefaults.standard.synchronize()
      result(true)

    case "resetBaseline":
      UserDefaults.standard.removeObject(forKey: keyHasRecordedBaseline)
      UserDefaults.standard.removeObject(forKey: keyLastChangeCount)
      UserDefaults.standard.removeObject(forKey: keyLastContentHash)
      UserDefaults.standard.synchronize()
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func calculateSha256(_ string: String) -> String {
    guard let data = string.data(using: .utf8) else { return "" }
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
      _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}
