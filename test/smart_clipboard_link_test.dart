import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:smart_clipboard_link/smart_clipboard_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('smart_clipboard_link');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'checkClipboardStatus':
          return {
            'shouldRead': true,
            'changeCount': 10,
          };
        case 'readClipboardContent':
          return {
            'content': 'https://example.com/s/ABCDEF',
            'changeCount': 10,
          };
        case 'clearClipboard':
          return true;
        case 'recordChangeCount':
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

  test('checkStatus returns mock status', () async {
    final status = await SmartClipboardLink.checkStatus();
    expect(status.shouldRead, true);
    expect(status.changeCount, 10);
  });

  test('readContent returns mock content', () async {
    final res = await SmartClipboardLink.readContent();
    expect(res.content, 'https://example.com/s/ABCDEF');
    expect(res.changeCount, 10);
  });

  test('clear returns true', () async {
    final ok = await SmartClipboardLink.clear();
    expect(ok, true);
  });
}
