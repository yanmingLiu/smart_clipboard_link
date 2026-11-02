import 'package:flutter/material.dart';
import 'package:smart_clipboard_link/smart_clipboard_link.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Idle';

  Future<void> _checkClipboard() async {
    // 1. 无感预检（iOS 不弹窗）
    final status = await SmartClipboardLink.checkStatus();
    if (!status.shouldRead) {
      setState(() {
        _status = 'No new clipboard content: ${status.reason}';
      });
      return;
    }

    // 2. 有新内容时触发读取（此时系统弹出权限提示）
    final result = await SmartClipboardLink.readContent();
    setState(() {
      _status = 'Read content: ${result.content} (changeCount: ${result.changeCount})';
    });
  }

  Future<void> _clearClipboard() async {
    final success = await SmartClipboardLink.clear();
    setState(() {
      _status = success ? 'Clipboard cleared' : 'Clear failed';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Smart Clipboard Plugin Example'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Status: $_status',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _checkClipboard,
                  child: const Text('Check & Read Clipboard'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _clearClipboard,
                  child: const Text('Clear Clipboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
