import 'dart:async';

import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'incall.dart';

const kBlue = Color(0xFF0D84FF);
const kGreen = Color(0xFF34C759);
const kRed = Color(0xFFFF3B30);

void main() => runApp(const App());

// Second entry point: the call screen (opened by Android during a call).
@pragma('vm:entry-point')
void inCallMain() => runApp(const InCallApp());

class App extends StatelessWidget {
  const App({super.key});

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorSchemeSeed: kBlue,
      scaffoldBackgroundColor: dark ? Colors.black : const Color(0xFFF4F5F7),
      cardColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
      splashFactory: NoSplash.splashFactory,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Phone',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const Home(),
    );
  }
}

// ---------- helpers ----------

class Person {
  Person(this.name, this.number, this.fav);
  final String name, number;
  final bool fav;
}

String toT9(String s) {
  const m = {
    'abc': '2', 'def': '3', 'ghi': '4', 'jkl': '5',
    'mno': '6', 'pqrs': '7', 'tuv': '8', 'wxyz': '9',
  };
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    if (RegExp(r'\d').hasMatch(ch)) {
      b.write(ch);
      continue;
    }
    for (final e in m.entries) {
      if (e.key.contains(ch)) b.write(e.value);
    }
  }
  return b.toString();
}

bool matches(String name, String number, String q) {
  if (q.isEmpty) return true;
  final ql = q.toLowerCase();
  if (name.toLowerCase().contains(ql)) return true;
  if (number.replaceAll(' ', '').contains(ql)) return true;
  return RegExp(r'^\d+$').hasMatch(q) && toT9(name).contains(q);
}

String keyOf(String n) {
  final d = n.replaceAll(RegExp(r'\D'), '');
  return d.length > 9 ? d.substring(d.length - 9) : d;
}

String fmtTime(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  final t = '${two(d.hour)}:${two(d.minute)}';
  if (d.year == n.year && d.month == n.month && d.day == n.day) return t;
  return '${two(d.day)}/${two(d.month)} $t';
}

Future<bool> placeCall(BuildContext c, String n) async {
  final number = n.trim();
  if (number.isEmpty) return false;
  try {
    await Permission.phone.request();
  } catch (_) {}
  var ok = false;
  try {
    ok = await dialerChannel
            .invokeMethod<bool>('placeCall', {'number': number}) ??
        false;
  } catch (_) {}
  if (!ok && c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(
      const SnackBar(content: Text('Could not place call')),
    );
  }
  return ok;
}

void showActions(BuildContext c, String title, String n) {
  showModalBottomSheet<void>(
    context: c,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(title.isEmpty ? n : title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: title.isEmpty ? null : Text(n),
          ),
          ListTile(
            leading: const Icon(Icons.call, color: kGreen),
            title: const Text('Call'),
            onTap: () {
              Navigator.pop(ctx);
              placeCall(c, n);
            },
          ),
          ListTile(
            leading: const Icon(Icons.message_outlined),
            title: const Text('Message'),
            onTap: () {
              Navigator.pop(ctx);
              launchUrl(Uri(scheme: 'sms', path: n));
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy number'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: n));
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt),
            title: const Text('Add to contacts'),
            onTap: () {
              Navigator.pop(ctx);
              FlutterContacts.openExternalInsert(Contact(phones: [Phone(n)]));
            },
          ),
        ],
      ),
    ),
  );
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) {
    const colors = [
      0xFF5B8DEF, 0xFF34C759, 0xFFFF9F0A, 0xFFAF52DE, 0xFFFF6B6B, 0xFF30B0C7,
    ];
    final c = Color(colors[name.codeUnits.fold(0, (a, b) => a + b) % colors.length]);
    return CircleAvatar(
      radius: 22,
      backgroundColor: name.isEmpty ? const Color(0xFF2C3E63) : c,
      child: name.isEmpty
          ? const Icon(Icons.person, color: Colors.white)
          : Text(
              String.fromCharCode(name.runes.first).toUpperCase(),
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
    );
  }
}

// ---------- home ----------

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  static const _rows = [
    [['1', ''], ['2', 'ABC'], ['3', 'DEF']],
    [['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO']],
    [['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ']],
    [['*', ''], ['0', '+'], ['#', '']],
  ];

  List<Person> people = [];
  List<CallLogEntry> log = [];
  final Map<String, String> names = {};
  String q = '';
  bool loading = true;
  bool _busy = false;
  int tab = 0;
  bool pad = false;
  String digits = '';
  bool isDefault = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    dialerChannel.setMethodCallHandler((c) async {
      if (c.method == 'dial' && mounted) {
        setState(() {
          digits = (c.arguments as String?) ?? '';
          pad = true;
        });
      }
    });
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _checkDefault();
    }
  }

  Future<void> _init() async {
    try {
      final n = await dialerChannel.invokeMethod<String>('initialNumber');
      if (n != null && n.isNotEmpty) {
        digits = n;
        pad = true;
      }
    } catch (_) {}
    await _load();
    _checkDefault();
  }

  Future<void> _checkDefault() async {
    try {
      final d = await dialerChannel.invokeMethod<bool>('isDefault') ?? true;
      if (mounted) setState(() => isDefault = d);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    Map<Permission, PermissionStatus> r = {};
    try {
      r = await [Permission.phone, Permission.contacts, Permission.notification]
          .request();
    } catch (_) {}
    final ps = <Person>[];
    var lg = <CallLogEntry>[];
    if (r[Permission.contacts]?.isGranted ?? false) {
      try {
        final cs = await FlutterContacts.getContacts(withProperties: true);
        for (final c in cs) {
          for (final p in c.phones) {
            ps.add(Person(c.displayName, p.number, c.isStarred));
          }
        }
        ps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } catch (_) {}
    }
    try {
      lg = (await CallLog.get()).take(300).toList();
    } catch (_) {}
    names.clear();
    for (final p in ps) {
      names[keyOf(p.number)] = p.name;
    }
    _busy = false;
    if (!mounted) return;
    setState(() {
      people = ps;
      log = lg;
      loading = false;
    });
  }

  // ----- pieces -----

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Row(
          children: [
            const SizedBox(width: 48),
            Expanded(
              child: Center(
                child: Text(
                  tab == 0 ? 'Recents' : 'Contacts',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'default') dialerChannel.invokeMethod('requestDefault');
                if (v == 'refresh') _load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'default', child: Text('Set as default phone app')),
                PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              ],
            ),
          ],
        ),
      );

  Widget _search() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          onChanged: (v) => setState(() => q = v.trim()),
          decoration: InputDecoration(
            hintText: 'Search contacts',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _banner() => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Expanded(child: Text('Use this as your default phone app')),
            TextButton(
              onPressed: () => dialerChannel.invokeMethod('requestDefault'),
              child: const Text('Set'),
            ),
          ],
        ),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nothing here'),
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Check permissions'),
            ),
          ],
        ),
      );

  EdgeInsets get _listPad => EdgeInsets.only(
      bottom: pad ? MediaQuery.of(context).size.height * 0.62 : 110);

  Widget _recents() {
    final items = log.where((e) {
      final n = e.number ?? '';
      final nm = (e.name?.isNotEmpty ?? false) ? e.name! : (names[keyOf(n)] ?? '');
      return matches(nm, n, q);
    }).toList();
    if (items.isEmpty) return _empty();
    return ListView.builder(
      padding: _listPad,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final e = items[i];
        final n = e.number ?? '';
        final nm = (e.name?.isNotEmpty ?? false) ? e.name! : (names[keyOf(n)] ?? '');
        final t = e.callType;
        final bad = t == CallType.missed ||
            t == CallType.rejected ||
            t == CallType.blocked;
        final icon = t == CallType.outgoing
            ? Icons.call_made
            : (bad ? Icons.call_missed : Icons.call_received);
        return ListTile(
          leading: Avatar(nm),
          title: Text(
            nm.isEmpty ? (n.isEmpty ? 'Unknown' : n) : nm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: bad ? kRed : null, fontWeight: FontWeight.w500),
          ),
          subtitle: Row(children: [
            Icon(icon, size: 14, color: bad ? kRed : Colors.grey),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                nm.isEmpty ? fmtTime(e.timestamp) : '$n  ${fmtTime(e.timestamp)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          trailing: IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showActions(context, nm, n),
          ),
          onTap: () => placeCall(context, n),
          onLongPress: () => showActions(context, nm, n),
        );
      },
    );
  }

  Widget _contacts() {
    final list = people.where((p) => matches(p.name, p.number, q)).toList();
    if (list.isEmpty) return _empty();
    final rows = <Object>[];
    final favs = list.where((p) => p.fav).toList();
    if (favs.isNotEmpty) {
      rows.add('★ Favorites');
      rows.addAll(favs);
    }
    String last = '';
    for (final p in list) {
      final l = p.name.isEmpty
          ? '#'
          : String.fromCharCode(p.name.runes.first).toUpperCase();
      if (l != last) {
        rows.add(l);
        last = l;
      }
      rows.add(p);
    }
    return ListView.builder(
      padding: _listPad,
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        if (r is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Text(r,
                style: const TextStyle(color: kBlue, fontWeight: FontWeight.w600)),
          );
        }
        final p = r as Person;
        return ListTile(
          leading: Avatar(p.name),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(p.number),
          trailing: IconButton(
            icon: const Icon(Icons.call, color: kGreen),
            onPressed: () => placeCall(context, p.number),
          ),
          onTap: () => showActions(context, p.name, p.number),
        );
      },
    );
  }

  Widget _key(List<String> k) {
    return InkResponse(
      onTap: () {
        if (digits.length >= 20) return;
        HapticFeedback.selectionClick();
        setState(() => digits += k[0]);
      },
      onLongPress: k[0] == '0' ? () => setState(() => digits += '+') : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(k[0],
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w400)),
          Text(k[1], style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _keypad() {
    final sugg = digits.isEmpty
        ? <Person>[]
        : people
            .where((p) =>
                p.number.replaceAll(RegExp(r'\D'), '').contains(digits) ||
                toT9(p.name).contains(digits))
            .take(2)
            .toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in sugg)
            ListTile(
              dense: true,
              leading: Avatar(p.name),
              title: Text(p.name),
              subtitle: Text(p.number),
              onTap: () => placeCall(context, p.number),
            ),
          SizedBox(
            height: 46,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(digits.isEmpty ? ' ' : digits,
                    style: const TextStyle(fontSize: 30, letterSpacing: 2)),
              ),
            ),
          ),
          for (final row in _rows)
            SizedBox(
              height: 60,
              child: Row(children: [
                for (final k in row) Expanded(child: _key(k)),
              ]),
            ),
          SizedBox(
            height: 76,
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                      onPressed: () => setState(() => pad = false),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final ok = await placeCall(context, digits);
                    if (ok && mounted) setState(() => digits = '');
                  },
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: const BoxDecoration(
                        color: kGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.call, color: Colors.white, size: 30),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onLongPress: () => setState(() => digits = ''),
                    child: IconButton(
                      icon: const Icon(Icons.backspace_outlined),
                      onPressed: () {
                        if (digits.isNotEmpty) {
                          setState(() =>
                              digits = digits.substring(0, digits.length - 1));
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav() {
    final cs = Theme.of(context).colorScheme;
    final card = Theme.of(context).cardColor;
    Widget item(int i, IconData ic, String label) {
      final sel = tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => tab = i),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: sel ? cs.primary.withOpacity(0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(ic, size: 22, color: sel ? cs.primary : Colors.grey),
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: sel ? cs.primary : Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(children: [
                item(0, Icons.call, 'Recents'),
                item(1, Icons.contacts, 'Contacts'),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => pad = !pad),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: card, shape: BoxShape.circle),
              child: Icon(Icons.dialpad, color: pad ? cs.primary : null),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _header(),
                _search(),
                if (!isDefault && tab == 0) _banner(),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
       
