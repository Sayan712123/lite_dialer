import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

void main() => runApp(const DialerApp());

class DialerApp extends StatelessWidget {
  const DialerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lite Dialer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        primarySwatch: Colors.green,
        splashFactory: NoSplash.splashFactory,
      ),
      home: const DialerPage(),
    );
  }
}

class DialerPage extends StatefulWidget {
  const DialerPage({super.key});

  @override
  State<DialerPage> createState() => _DialerPageState();
}

class _DialerPageState extends State<DialerPage> {
  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];
  static const _maxLength = 20;
  static const _maxRecents = 10;

  String _number = '';
  final List<String> _recents = [];

  void _add(String d) {
    if (_number.length >= _maxLength) return;
    HapticFeedback.selectionClick();
    setState(() => _number += d);
  }

  void _backspace() {
    if (_number.isEmpty) return;
    setState(() => _number = _number.substring(0, _number.length - 1));
  }

  void _clear() => setState(() => _number = '');

  Future<void> _call() async {
    final n = _number.trim();
    if (n.isEmpty) return;
    final ok = await FlutterPhoneDirectCaller.callNumber(n);
    if (!mounted) return;
    if (ok == true) {
      setState(() {
        _recents.remove(n);
        _recents.insert(0, n);
        if (_recents.length > _maxRecents) _recents.removeLast();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not place call')),
      );
    }
  }

  void _showRecents() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        if (_recents.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(child: Text('No recent calls')),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: _recents.length,
          itemBuilder: (_, i) => ListTile(
            leading: const Icon(Icons.history),
            title: Text(_recents[i]),
            onTap: () {
              setState(() => _number = _recents[i]);
              Navigator.pop(ctx);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dialer'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Recent',
            onPressed: _showRecents,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _number.isEmpty ? ' ' : _number,
                      style: const TextStyle(
                        fontSize: 36,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  for (final row in _keys)
                    Expanded(
                      child: Row(
                        children: [
                          for (final k in row)
                            Expanded(
                              child: _Key(label: k, onTap: () => _add(k)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  const Spacer(),
                  Expanded(
                    child: Center(
                      child: FloatingActionButton(
                        heroTag: null,
                        elevation: 0,
                        backgroundColor: Colors.green,
                        onPressed: _call,
                        child: const Icon(Icons.call, color: Colors.white),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onLongPress: _clear,
                      child: IconButton(
                        iconSize: 30,
                        icon: const Icon(Icons.backspace_outlined),
                        onPressed: _backspace,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
