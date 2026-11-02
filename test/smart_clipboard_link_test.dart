import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:smart_clipboard_link/smart_clipboard_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('smart_clipboard_link');
  late Map<String, dynamic> lastMethodCallArguments;

  setUp(() {
    lastMethodCallArguments = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      lastMethodCallArguments[methodCall.method] = methodCall.arguments;
      switch (methodCall.method) {
        case 'checkClipboardStatus':
          final args = methodCall.arguments as Map<dynamic, dynamic>?;
          final maxAgeMs = args?['maxAgeMs'] as int?;

          if (maxAgeMs != null && maxAgeMs < 1000) {
            return {
              'shouldRead': false,
              'reason': 'expired',
              'changeCount': 99,
            };
          }

          if (args?['mockScenario'] == 'firstLaunch') {
            return {
              'shouldRead': false,
              'reason': 'firstLaunchIgnored',
              'changeCount': 100,
            };
          }

          return {
            'shouldRead': true,
            'reason': 'newUrl',
            'changeCount': 10,
          };

        case 'readClipboardContent':
          return {
            'content': 'https://link.example.com/s/ABCDEF',
            'changeCount': 10,
            'contentHash': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
            'isDuplicate': false,
          };

        case 'clearClipboard':
          return true;

        case 'recordChangeCount':
          return true;

        case 'resetBaseline':
          return true;

        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SmartClipboardLink Advanced Tests', () {
    test('checkStatus respects cooldown / debounce throttled', () async {
      await SmartClipboardLink.resetBaseline();

      final first = await SmartClipboardLink.checkStatus(
        cooldown: const Duration(seconds: 2),
      );
      expect(first.shouldRead, true);

      // 立即再次检查，应触发 throttled 防抖
      final second = await SmartClipboardLink.checkStatus(
        cooldown: const Duration(seconds: 2),
      );
      expect(second.shouldRead, false);
      expect(second.reason, 'throttled');
    });

    test('checkStatus passes maxAgeMs for TTL expiration', () async {
      await SmartClipboardLink.resetBaseline();
      final status = await SmartClipboardLink.checkStatus(
        maxAge: const Duration(milliseconds: 500),
        cooldown: null,
      );
      expect(status.shouldRead, false);
      expect(status.reason, 'expired');
    });

    test('readContent filters by allowedDomains and urlPrefixes correctly', () async {
      // 匹配域名
      final okResult = await SmartClipboardLink.readContent(
        allowedDomains: ['example.com'],
      );
      expect(okResult.matchesPattern, true);
      expect(okResult.content, 'https://link.example.com/s/ABCDEF');

      // 匹配特定前缀
      final prefixOk = await SmartClipboardLink.readContent(
        urlPrefixes: ['https://link.example.com/'],
      );
      expect(prefixOk.matchesPattern, true);

      // 不匹配的域名
      final badDomain = await SmartClipboardLink.readContent(
        allowedDomains: ['google.com', 'other.org'],
      );
      expect(badDomain.matchesPattern, false);

      // 不匹配的前缀
      final badPrefix = await SmartClipboardLink.readContent(
        urlPrefixes: ['https://taobao.com/'],
      );
      expect(badPrefix.matchesPattern, false);
    });

    test('recordChangeCount and clear methods work as expected', () async {
      final rec = await SmartClipboardLink.recordChangeCount(50, 'hash_999');
      expect(rec, true);
      final clr = await SmartClipboardLink.clear();
      expect(clr, true);
    });
  });
}
