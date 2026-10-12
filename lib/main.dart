import 'dart:typed_data';

import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'contacts_app.dart';
import 'contacts_ui.dart';
import 'dialer_ui.dart';
import 'helpers.dart';
import 'incall.dart';

void main() => runApp(const App());

// Second entry point: the call screen (opened by Android during a call).
@pragma('vm:entry-point')
void inCallMain() => runApp(const InCallApp());

class App extends StatelessWidget {
  const App({super.key});

  // iOS-style colors: grouped gray background, white cards, system blue.
  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorSchemeSeed: kBlue,
      scaffoldBackgroundColor: dark ? Colors.black : const Color(0xFFF2F2F7),
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

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  List<Person> people = [];
  List<CallLogEntry> log = [];
  final Map<String, String> names = {};
  final Map<String, Uint8List> photos = {};
  String q = '';
  bool loading = true;
  bool _busy = false;
  int tab = 0;
  bool dialer = false;
  bool searching = false;
  String digits = '';
  bool isDefault = true;
  bool lite = false;
  List<Contact> contacts = [];
  String mode = 'phone';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    dialerChannel.setMethodCallHandler((c) async {
      if (c.method == 'page' && mounted) {
        setState(() {
          mode = (c.arguments as String?) ?? 'phone';
          dialer = false;
          searching = false;
        });
      }
      if (c.method == 'dial' && mounted) {
        setState(() {
          digits = (c.arguments as String?) ?? '';
          dialer = true;
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
      final pg = await dialerChannel.invokeMethod<String>('initialPage');
      if (pg != null) mode = pg;
    } catch (_) {}
    try {
      final n = await dialerChannel.invokeMethod<String>('initialNumber');
      if (n != null && n.isNotEmpty) {
        digits = n;
        dialer = true;
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
    var liteNow = false;
    try {
      liteNow = await dialerChannel.invokeMethod<bool>('isLite') ?? false;
    } catch (_) {}
    Map<Permission, PermissionStatus> r = {};
    try {
      r = await [Permission.phone, Permission.contacts, Permission.notification]
          .request();
    } catch (_) {}
    final ps = <Person>[];
    var cs = <Contact>[];
    var lg = <CallLogEntry>[];
    if (r[Permission.contacts]?.isGranted ?? false) {
      try {
        cs = await FlutterContacts.getContacts(
            withProperties: true, withThumbnail: !liteNow);
        for (final c in cs) {
          for (final p in c.phones) {
            final th = c.thumbnail;
            final has = th != null && th.isNotEmpty;
            ps.add(Person(c.displayName, p.number, c.isStarred, has ? th : null));
          }
        }
        ps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } catch (_) {}
    }
    try {
      lg = (await CallLog.get()).take(liteNow ? 100 : 300).toList();
    } catch (_) {}
    names.clear();
    photos.clear();
    for (final p in ps) {
      names[keyOf(p.number)] = p.name;
      if (p.thumb != null) photos[keyOf(p.number)] = p.thumb!;
    }
    _busy = false;
    if (!mounted) return;
    setState(() {
      lite = liteNow;
      contacts = cs;
      people = ps;
      log = lg;
      loading = false;
    });
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (d?.text ?? '').replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (t.isEmpty || !mounted) return;
    final all = digits + t;
    setState(() => digits = all.length > 20 ? all.substring(0, 20) : all);
  }

  Widget _menu(IconData ic, {bool phone = true}) => PopupMenuButton<String>(
        icon: Icon(ic),
        onSelected: (v) async {
          if (v == 'default') dialerChannel.invokeMethod('requestDefault');
          if (v == 'refresh') _load();
          if (v == 'lite') {
            await dialerChannel.invokeMethod('setLite', {'on': !lite});
            _load();
          }
        },
        itemBuilder: (_) => [
          if (phone)
            const PopupMenuItem(
                value: 'default', child: Text('Set as default phone app')),
          const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
          PopupMenuItem(
            value: 'lite',
            child: Text(lite ? 'Lite mode: ON' : 'Lite mode: OFF'),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !dialer && !searching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          if (dialer) {
            dialer = false;
          } else {
            searching = false;
            q = '';
          }
        });
      },
      child: Scaffold(
        body: SafeArea(
          child: mode == 'contacts'
              ? ContactsAppPage(
                  contacts: contacts,
                  loading: loading,
                  menu: _menu(Icons.more_vert_rounded, phone: false),
                  onChanged: _load,
                )
              : dialer
              ? DialerPage(
                  digits: digits,
                  people: people,
                  menu: _menu(Icons.more_vert_rounded),
                  onBack: () => setState(() => dialer = false),
                  onDigit: (d) {
                    if (digits.length >= 20) return;
                    HapticFeedback.selectionClick();
                    setState(() => digits += d);
                  },
                  onBackspace: () {
                    if (digits.isNotEmpty) {
                      setState(() =>
                          digits = digits.substring(0, digits.length - 1));
                    }
                  },
                  onClear: () => setState(() => digits = ''),
                  onPaste: _paste,
                  onCall: () async {
                    final ok = await placeCall(context, digits);
                    if (ok && mounted) setState(() => digits = '');
                  },
                  onCallNumber: (n) => placeCall(context, n),
                )
              : ContactsHome(
                  tab: tab,
                  searching: searching,
                  loading: loading,
                  isDefault: isDefault,
                  q: q,
                  people: people,
                  log: log,
                  names: names,
                  photos: photos,
                  menu: _menu(Icons.menu_rounded),
                  onTab: (i) => setState(() {
                    tab = i;
                    searching = false;
                    q = '';
                  }),
                  onSearching: (v) => setState(() {
                    searching = v;
                    if (!v) q = '';
                  }),
                  onQuery: (v) => setState(() => q = v.trim()),
                  onDialer: () => setState(() => dialer = true),
                  onSetDefault: () => dialerChannel.invokeMethod('requestDefault'),
                ),
        ),
      ),
    );
  }
}
