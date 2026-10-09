import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

const kBlue = Color(0xFF0D84FF);
const kGreen = Color(0xFF34C759);
const kRed = Color(0xFFFF3B30);

void main() => runApp(const App());

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

Future<void> placeCall(BuildContext c, String n) async {
  final num = n.trim();
  if (num.isEmpty) return;
  final ok = await FlutterPhoneDirectCaller.callNumber(num);
  if (ok != true && c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(
      const SnackBar(content: Text('Could not place call')),
    );
  }
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
              FlutterContacts.openExternalInsert(
                  Contact(phones: [Phone(n)]));
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
      backgroundColor: name.isEmpty ? Colors.grey : c,
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

class _HomeState extends State<Home> {
  List<Person> people = [];
  List<CallLogEntry> log = [];
  final Map<String, String> names = {};
  String q = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await [Permission.phone, Permission.contacts].request();
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
    if (!mounted) return;
    setState(() {
      people = ps;
      log = lg;
      loading = false;
    });
  }

  void _openDial() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DialSheet(people: people),
    );
  }

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

  Widget _card(Widget child) => Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: child,
      );

  Widget _recents() {
    final items = log.where((e) {
      final n = e.number ?? '';
      final nm = (e.name?.isNotEmpty ?? false) ? e.name! : (names[keyOf(n)] ?? '');
      return matches(nm, n, q);
    }).toList();
    if (items.isEmpty) return _empty();
    return ListView.builder(
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
        return _card(ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            Text(nm.isEmpty ? fmtTime(e.timestamp) : '$n  ${fmtTime(e.timestamp)}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          trailing: IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showActions(context, nm, n),
          ),
          onTap: () => placeCall(context, n),
          onLongPress: () => showActions(context, nm, n),
        ));
      },
    );
  }

  Widget _contacts({required bool favOnly}) {
    final list = people
        .where((p) => (!favOnly || p.fav) && matches(p.name, p.number, q))
        .toList();
    if (list.isEmpty) return _empty();
    final rows = <Object>[];
    String last = '';
    for (final p in list) {
      final l = p.name.isEmpty ? '#' : String.fromCharCode(p.name.runes.first).toUpperCase();
      if (!favOnly && l != last) {
        rows.add(l);
        last = l;
      }
      rows.add(p);
    }
    return ListView.builder(
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
        return _card(ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          leading: Avatar(p.name),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(p.number),
          trailing: IconButton(
            icon: const Icon(Icons.call, color: kGreen),
            onPressed: () => placeCall(context, p.number),
          ),
          onTap: () => showActions(context, p.name, p.number),
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          elevation: 2,
          backgroundColor: kBlue,
          onPressed: _openDial,
          child: const Icon(Icons.dialpad, color: Colors.white),
        ),
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Phone',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  onChanged: (v) => setState(() => q = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search contacts and numbers',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const TabBar(
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: 'Recents'),
                  Tab(text: 'Contacts'),
                  Tab(text: 'Favorites'),
                ],
              ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _recents(),
                          _contacts(favOnly: false),
                          _contacts(favOnly: true),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- keypad ----------

class DialSheet extends StatefulWidget {
  const DialSheet({super.key, required this.people});
  final List<Person> people;

  @override
  State<DialSheet> createState() => _DialSheetState();
}

class _DialSheetState extends State<DialSheet> {
  static const _rows = [
    [['1', ''], ['2', 'ABC'], ['3', 'DEF']],
    [['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO']],
    [['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ']],
    [['*', ''], ['0', '+'], ['#', '']],
  ];
  String num = '';

  void _add(String d) {
    if (num.length >= 20) return;
    HapticFeedback.selectionClick();
    setState(() => num += d);
  }

  @override
  Widget build(BuildContext context) {
    final sugg = num.isEmpty
        ? <Person>[]
        : widget.people
            .where((p) =>
                p.number.replaceAll(RegExp(r'\D'), '').contains(num) ||
                toT9(p.name).contains(num))
            .take(2)
            .toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            for (final p in sugg)
              ListTile(
                dense: true,
                leading: Avatar(p.name),
                title: Text(p.name),
                subtitle: Text(p.number),
                onTap: () => placeCall(context, p.number),
              ),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(num.isEmpty ? ' ' : num,
                      style: const TextStyle(fontSize: 36, letterSpacing: 2)),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  for (final row in _rows)
                    Expanded(
                      child: Row(
                        children: [
                          for (final k in row)
                            Expanded(
                              child: InkResponse(
                                onTap: () => _add(k[0]),
                                onLongPress:
                                    k[0] == '0' ? () => _add('+') : null,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(k[0],
                                        style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w500)),
                                    Text(k[1],
                                        style: const TextStyle(
                                            fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 84,
              child: Row(
                children: [
                  Expanded(
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: () => placeCall(context, num),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                              color: kGreen, shape: BoxShape.circle),
                          child: const Icon(Icons.call,
                              color: Colors.white, size: 30),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onLongPress: () => setState(() => num = ''),
                      child: IconButton(
                        icon: const Icon(Icons.backspace_outlined),
                        onPressed: () {
                          if (num.isNotEmpty) {
                            setState(() =>
                                num = num.substring(0, num.length - 1));
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
      ),
    );
  }
}
