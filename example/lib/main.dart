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
  bool _ignoreFirstLaunch = true;
  bool _onlyWebURL = true;

  Future<void> _checkClipboard() async {
    // 1. 无感预检（iOS 不弹窗，Android 12+ 不触发 Toast）
    final status = await SmartClipboardLink.checkStatus(
      ignoreFirstLaunch: _ignoreFirstLaunch,
      onlyWebURL: _onlyWebURL,
    );

    if (!status.shouldRead) {
      setState(() {
        _status =
            'No new clipboard content:\nreason: ${status.reason}\nchangeCount: ${status.changeCount}';
      });
      return;
    }

    // 2. 有新内容时触发读取（此时系统弹出权限提示 / Android Toast）
    final result = await SmartClipboardLink.readContent();
    setState(() {
      _status =
          'Read content:\n"${result.content}"\nchangeCount: ${result.changeCount}\nhash: ${result.contentHash}\nisDuplicate: ${result.isDuplicate}';
    });
  }

  Future<void> _clearClipboard() async {
    final success = await SmartClipboardLink.clear();
    setState(() {
      _status = success ? 'Clipboard cleared' : 'Clear failed';
    });
  }

  Future<void> _resetBaseline() async {
    final success = await SmartClipboardLink.resetBaseline();
    setState(() {
      _status = success ? 'Baseline reset (next check will be first launch)' : 'Reset failed';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Smart Clipboard Link Demo'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text('Ignore First Launch Baseline (P2)'),
                    subtitle: const Text('避免新装 App 首次启动误读剪切板'),
                    value: _ignoreFirstLaunch,
                    onChanged: (val) => setState(() => _ignoreFirstLaunch = val),
                  ),
                  SwitchListTile(
                    title: const Text('Only Web URL (P1)'),
                    subtitle: const Text('普通文本不弹窗，仅 Web URL 弹窗'),
                    value: _onlyWebURL,
                    onChanged: (val) => setState(() => _onlyWebURL = val),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _checkClipboard,
                    child: const Text('Check & Read Clipboard'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _clearClipboard,
                    child: const Text('Clear Clipboard'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _resetBaseline,
                    child: const Text('Reset Baseline (Simulate New Install)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
