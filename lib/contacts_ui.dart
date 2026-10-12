import 'dart:typed_data';

import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'helpers.dart';

/// Home screen: top bar, white sheet (Contacts | History) and bottom labels.
class ContactsHome extends StatelessWidget {
  const ContactsHome({
    super.key,
    required this.tab,
    required this.searching,
    required this.loading,
    required this.isDefault,
    required this.q,
    required this.people,
    required this.log,
    required this.names,
    required this.photos,
    required this.menu,
    required this.onTab,
    required this.onSearching,
    required this.onQuery,
    required this.onDialer,
    required this.onSetDefault,
  });

  final int tab;
  final bool searching, loading, isDefault;
  final String q;
  final List<Person> people;
  final List<CallLogEntry> log;
  final Map<String, String> names;
  final Map<String, Uint8List> photos;
  final Widget menu;
  final ValueChanged<int> onTab;
  final ValueChanged<bool> onSearching;
  final ValueChanged<String> onQuery;
  final VoidCallback onDialer;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _topBar(),
        Expanded(child: _sheet(context)),
        _bottomBar(),
      ],
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              menu,
              const Expanded(child: Center(child: _Logo())),
              IconButton(
                icon: const Icon(Icons.person_add_alt_1_rounded),
                onPressed: () => FlutterContacts.openExternalInsert(),
              ),
            ],
          ),
        ),
      );

  Widget _sheet(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _tabs(context),
              if (!isDefault && !searching) _banner(context),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : (tab == 0 ? _contactList(context) : _historyList(context)),
              ),
            ],
          ),
          Positioned(left: 22, right: 22, bottom: 16, child: _addButton()),
        ],
      ),
    );
  }

  Widget _tabs(BuildContext context) {
    if (searching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                autofocus: true,
                onChanged: onQuery,
                decoration: InputDecoration(
                  hintText: 'Search contacts',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: fillColor(context),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => onSearching(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
    Widget t(int i, String label) => GestureDetector(
          onTap: () => onTab(i),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 26,
              letterSpacing: -0.5,
              fontWeight: tab == i ? FontWeight.w700 : FontWeight.w500,
              color: tab == i ? null : Colors.grey,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 6),
      child: Row(
        children: [
          t(0, 'Contacts'),
          const SizedBox(width: 20),
          t(1, 'History'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => onSearching(true),
          ),
        ],
      ),
    );
  }

  Widget _banner(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          color: fillColor(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text('Use this as your default phone app',
                  style: TextStyle(fontSize: 13)),
            ),
            TextButton(onPressed: onSetDefault, child: const Text('Set')),
          ],
        ),
      );

  Widget _addButton() => SizedBox(
        height: 50,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kBlue,
            shape: const StadiumBorder(),
          ),
          onPressed: () => FlutterContacts.openExternalInsert(),
          child: const Text(
            'ADD CONTACT',
            style: TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 13),
          ),
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

  Widget _pill(BuildContext context, String number) => GestureDetector(
        onTap: () => placeCall(context, number),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: fillColor(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'CALL',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: kBlue),
          ),
        ),
      );

  Widget _row(
    BuildContext context, {
    required Widget avatar,
    required String title,
    required String name,
    required String number,
    Widget? sub,
    bool bad = false,
  }) {
    return InkWell(
      onTap: () => showActions(context, name, number),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: bad ? kRed : null,
                    ),
                  ),
                  if (sub != null) sub,
                ],
              ),
            ),
            const SizedBox(width: 8),
            _pill(context, number),
          ],
        ),
      ),
    );
  }

  Widget _contactList(BuildContext context) {
    final list = people.where((p) => matches(p.name, p.number, q)).toList();
    if (list.isEmpty) return _empty();
    final rows = <Object>[];
    final favs = list.where((p) => p.fav).toList();
    if (favs.isNotEmpty) {
      rows.add('★ Favorites');
      rows.addAll(favs);
    }
    var last = '';
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
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        if (r is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Text(r,
                style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          );
        }
        final p = r as Person;
        return _row(
          context,
          avatar: Avatar(p.name, photo: p.thumb, radius: 24),
          title: p.name,
          name: p.name,
          number: p.number,
          sub: Text(p.number,
              style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
        );
      },
    );
  }

  Widget _historyList(BuildContext context) {
    final items = log.where((e) {
      final n = e.number ?? '';
      final nm = (e.name?.isNotEmpty ?? false) ? e.name! : (names[keyOf(n)] ?? '');
      return matches(nm, n, q);
    }).toList();
    if (items.isEmpty) return _empty();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
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
        return _row(
          context,
          avatar: Avatar(nm, photo: photos[keyOf(n)], radius: 24),
          title: nm.isEmpty ? (n.isEmpty ? 'Unknown' : n) : nm,
          name: nm,
          number: n,
          bad: bad,
          sub: Row(
            children: [
              Icon(icon, size: 13, color: bad ? kRed : Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  nm.isEmpty ? fmtTime(e.timestamp) : '$n  ${fmtTime(e.timestamp)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomBar() {
    Widget item(String label, bool sel, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 58,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: sel ? kBlue : Colors.grey,
                  ),
                ),
              ),
            ),
          ),
        );
    Widget divider() => Container(
          width: 1,
          height: 22,
          color: Colors.grey.withOpacity(0.35),
        );
    return Row(
      children: [
        item('CONTACTS', tab == 0, () => onTab(0)),
        divider(),
        item('DIALER', false, onDialer),
        divider(),
        item('HISTORY', tab == 1, () => onTab(1)),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF44F35A), Color(0xFF05BB07)],
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(Icons.call, color: Colors.white, size: 20),
    );
  }
}
