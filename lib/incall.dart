import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const dialerChannel = MethodChannel('dialer');

const _green = Color(0xFF34C759);
const _red = Color(0xFFFF3B30);

Future<void> _native(String m, [Map<String, dynamic>? args]) async {
  try {
    await dialerChannel.invokeMethod(m, args);
  } catch (_) {}
}

class InCallApp extends StatelessWidget {
  const InCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const InCallPage(),
    );
  }
}

class InCallPage extends StatefulWidget {
  const InCallPage({super.key});

  @override
  State<InCallPage> createState() => _InCallPageState();
}

class _InCallPageState extends State<InCallPage> {
  Map<dynamic, dynamic> s = {};
  Timer? _ticker;
  bool _seen = false;
  bool _late = false;
  bool _pad = false;
  String _digits = '';
  String _note = '';

  @override
  void initState() {
    super.initState();
    dialerChannel.setMethodCallHandler((c) async {
      if (c.method == 'changed') {
        _apply(Map<dynamic, dynamic>.from(c.arguments as Map));
      }
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _refresh();
    Future.delayed(const Duration(seconds: 3), () => _refresh(late: true));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool late = false}) async {
    if (late) _late = true;
    try {
      final r = await dialerChannel.invokeMethod('snapshot');
      if (r is Map) _apply(Map<dynamic, dynamic>.from(r));
    } catch (_) {}
  }

  void _apply(Map<dynamic, dynamic> m) {
    if (!mounted) return;
    setState(() => s = m);
    final active = m['active'] == true;
    if (active) _seen = true;
    if (!active && (_seen || _late)) {
      Future.delayed(const Duration(milliseconds: 300), () => _native('finish'));
    }
  }

  String get _state => (s['state'] ?? '') as String;
  String get _number => (s['number'] ?? '') as String;
  String get _name => (s['name'] ?? '') as String;
  String get _title =>
      _name.isNotEmpty ? _name : (_number.isNotEmpty ? _number : 'Unknown');
  String get _sub => _name.isNotEmpty ? _number : '';
  bool get _muted => s['muted'] == true;
  bool get _speaker => s['speaker'] == true;

  String _status() {
    switch (_state) {
      case 'active':
        final ct = (s['connectTime'] as num?)?.toInt() ?? 0;
        if (ct <= 0) return '00:00';
        final sec =
            ((DateTime.now().millisecondsSinceEpoch - ct) / 1000).floor();
        final t = sec < 0 ? 0 : sec;
        String two(int x) => x.toString().padLeft(2, '0');
        final h = t ~/ 3600;
        final m = (t % 3600) ~/ 60;
        final x = t % 60;
        return h > 0 ? '${two(h)}:${two(m)}:${two(x)}' : '${two(m)}:${two(x)}';
      case 'holding':
        return 'On hold';
      case 'ringing':
        return 'Incoming call';
      case 'ended':
        return 'Call ended';
      default:
        return 'Calling…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ringing = _state == 'ringing';
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: ringing
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF7FA6D6), Color(0xFF3B5E8C), Color(0xFF14202F)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2E5C8C), Color(0xFFB22A32), Color(0xFF1E7C8C)],
                  stops: [0, 0.5, 1],
                ),
        ),
        child: SafeArea(child: ringing ? _incoming() : _ongoing()),
      ),
    );
  }

  // ---------- incoming call card ----------

  Widget _incoming() {
    return Column(
      children: [
        const SizedBox(height: 56),
        CircleAvatar(
          radius: 46,
          backgroundColor: Colors.white24,
          child: _name.isEmpty
              ? const Icon(Icons.person, size: 48, color: Colors.white)
              : Text(
                  String.fromCharCode(_name.runes.first).toUpperCase(),
                  style: const TextStyle(fontSize: 38, color: Colors.white),
                ),
        ),
        const SizedBox(height: 18),
        Text(_title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 30, fontWeight: FontWeight.w600, color: Colors.white)),
        if (_sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_sub,
                style: const TextStyle(fontSize: 16, color: Colors.white70)),
          ),
        const SizedBox(height: 8),
        const Text('Incoming call', style: TextStyle(color: Colors.white70)),
        const Spacer(),
        GestureDetector(
          onTap: _quickReply,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.message_outlined, size: 16, color: Colors.white70),
                SizedBox(width: 8),
                Text('Reply with message', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 44),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 52),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _circle(_red, Icons.call_end, () => _native('reject')),
              _circle(_green, Icons.call, () => _native('answer')),
            ],
          ),
        ),
        const SizedBox(height: 64),
      ],
    );
  }

  void _quickReply() {
    const replies = [
      "Can't talk now. I'll call you later.",
      "I'm in a meeting. I'll call you back.",
      'Call me later, please.',
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in replies)
              ListTile(
                title: Text(r),
                onTap: () {
                  Navigator.pop(ctx);
                  _native('reject');
                  if (_number.isNotEmpty) {
                    launchUrl(Uri(
                        scheme: 'sms',
                        path: _number,
                        queryParameters: {'body': r}));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  // ---------- ongoing call ----------

  Widget _ongoing() {
    final holding = _state == 'holding';
    final count = (s['count'] as num?)?.toInt() ?? 1;
    return Column(
      children: [
        const SizedBox(height: 56),
        Text(_title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 34, fontWeight: FontWeight.w500, color: Colors.white)),
        if (_sub.isNotEmpty)
          Text(_sub, style: const TextStyle(fontSize: 15, color: Colors.white70)),
        const SizedBox(height: 10),
        Text(_status(),
            style: const TextStyle(fontSize: 18, color: Colors.white70)),
        if (count > 1)
          TextButton(
            onPressed: () => _native('swap'),
            child: const Text('Swap calls'),
          ),
        const Spacer(),
        if (_pad) _dtmf() else _grid(holding),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _toggle(Icons.volume_up, _speaker,
                () => _native('speaker', {'on': !_speaker})),
            _circle(_red, Icons.call_end, () => _native('hangup'), size: 78),
            _toggle(Icons.dialpad, _pad, () => setState(() => _pad = !_pad)),
          ],
        ),
        const SizedBox(height: 44),
      ],
    );
  }

  Widget _grid(bool holding) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _btn(Icons.person, 'Contacts', () => _native('openContacts')),
            _btn(Icons.add, 'Add call', () => _native('addCall')),
            _btn(Icons.sticky_note_2_outlined, 'Note', _noteDialog),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _btn(_muted ? Icons.mic_off : Icons.mic_none, 'Mute',
                () => _native('mute', {'on': !_muted}),
                on: _muted),
            _btn(Icons.pause, 'Hold', () => _native('hold', {'on': !holding}),
                on: holding),
            _btn(Icons.graphic_eq, 'Record', () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Call recording is not supported')));
            }, enabled: false),
          ],
        ),
      ],
    );
  }

  Widget _dtmf() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: Text(_digits,
              style: const TextStyle(
                  fontSize: 26, letterSpacing: 2, color: Colors.white)),
        ),
        for (final row in keys)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final k in row)
                InkResponse(
                  onTap: () {
                    setState(() => _digits += k);
                    _native('dtmf', {'digit': k});
                  },
                  child: SizedBox(
                    width: 90,
                    height: 56,
                    child: Center(
                      child: Text(k,
                          style: const TextStyle(
                              fontSize: 30, color: Colors.white)),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  void _noteDialog() {
    final c = TextEditingController(text: _note);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: TextField(controller: c, maxLines: 4, autofocus: true),
        actions: [
          TextButton(
            onPressed: () {
              _note = c.text;
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---------- small widgets ----------

  Widget _circle(Color color, IconData icon, VoidCallback onTap,
      {double size = 72}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: size * 0.42),
      ),
    );
  }

  Widget _toggle(IconData icon, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.black.withOpacity(0.28),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: on ? Colors.black87 : Colors.white),
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool on = false, bool enabled = true}) {
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: on
                    ? Colors.white
                    : Colors.black.withOpacity(enabled ? 0.28 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: on
                    ? Colors.black87
                    : Colors.white.withOpacity(enabled ? 1 : 0.4),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(enabled ? 1 : 0.5))),
        ],
      ),
    );
  }
}
