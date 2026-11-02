import Flutter
import UIKit

public class SmartClipboardLinkPlugin: NSObject, FlutterPlugin {
  private static let channelName = "smart_clipboard_link"
  private let keyLastChangeCount = "kLastClipboardChangeCount_smart_link"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = SmartClipboardLinkPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkClipboardStatus":
      // 1. 无感检查：是否有文本
      let pasteboard = UIPasteboard.general
      if !pasteboard.hasStrings {
        result([
          "shouldRead": false,
          "reason": "empty"
        ])
        return
      }

      // 2. 无感检查：changeCount 是否一致
      let lastCount = UserDefaults.standard.integer(forKey: keyLastChangeCount)
      let currentCount = pasteboard.changeCount

      // 如果未记录过或者当前不同
      let hasRecorded = UserDefaults.standard.object(forKey: keyLastChangeCount) != nil
      if hasRecorded && currentCount == lastCount {
        result([
          "shouldRead": false,
          "reason": "unchanged",
          "changeCount": currentCount
        ])
        return
      }

      // 说明有新的复制内容产生，需要外部触发读取
      result([
        "shouldRead": true,
        "changeCount": currentCount
      ])

    case "readClipboardContent":
      // 3. 读取内容并触发系统授权（iOS 14/16+ 提示）
      let pasteboard = UIPasteboard.general
      let currentCount = pasteboard.changeCount
      
      // 触发读取
      let content = pasteboard.string ?? ""
      
      // 同意或已读取：记录当前的 changeCount
      UserDefaults.standard.set(currentCount, forKey: keyLastChangeCount)
      UserDefaults.standard.synchronize()

      result([
        "content": content,
        "changeCount": currentCount
      ])

    case "recordChangeCount":
      // 4. 用户拒绝或其他情况，外部主动要求记录当前 changeCount
      let pasteboard = UIPasteboard.general
      let countToRecord: Int
      if let args = call.arguments as? [String: Any], let count = args["changeCount"] as? Int {
        countToRecord = count
      } else {
        countToRecord = pasteboard.changeCount
      }
      UserDefaults.standard.set(countToRecord, forKey: keyLastChangeCount)
      UserDefaults.standard.synchronize()
      result(true)

    case "clearClipboard":
      // 5. 成功承接后清空剪切板
      UIPasteboard.general.items = []
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
