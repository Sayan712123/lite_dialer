import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'helpers.dart';

Uint8List? _thumb(Contact c) {
  final t = c.thumbnail;
  return (t != null && t.isNotEmpty) ? t : null;
}

String _group(Contact c) {
  final n = c.displayName.trim();
  if (n.isEmpty) return '#';
  final l = String.fromCharCode(n.runes.first).toUpperCase();
  return RegExp(r'^[A-Z]$').hasMatch(l) ? l : '#';
}

/// The Contacts app: large title, search, sections A-Z, contact card.
class ContactsAppPage extends StatefulWidget {
  const ContactsAppPage({
    super.key,
    required this.contacts,
    required this.loading,
    required this.menu,
    required this.onChanged,
  });

  final List<Contact> contacts;
  final bool loading;
  final Widget menu;
  final VoidCallback onChanged;

  @override
  State<ContactsAppPage> createState() => _ContactsAppPageState();
}

class _ContactsAppPageState extends State<ContactsAppPage> {
  String q = '';

  bool _match(Contact c) {
    if (q.isEmpty) return true;
    final ql = q.toLowerCase();
    if (c.displayName.toLowerCase().contains(ql)) return true;
    for (final p in c.phones) {
      if (p.number.replaceAll(' ', '').contains(ql)) return true;
    }
    return false;
  }

  Future<void> _open(Contact c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => ContactDetailPage(contact: c)),
    );
    if (changed == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.contacts.where(_match).toList();
    list.sort((a, b) {
      final ga = _group(a), gb = _group(b);
      if (ga != gb) {
        if (ga == '#') return 1;
        if (gb == '#') return -1;
        return ga.compareTo(gb);
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    final rows = <Object>[];
    final favs = list.where((c) => c.isStarred).toList();
    if (favs.isNotEmpty) {
      rows.add('★ Favorites');
      rows.addAll(favs);
    }
    var last = '';
    for (final c in list) {
      final g = _group(c);
      if (g != last) {
        rows.add(g);
        last = g;
      }
      rows.add(c);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Contacts',
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 28),
                color: kBlue,
                onPressed: () => FlutterContacts.openExternalInsert(),
              ),
              widget.menu,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            onChanged: (v) => setState(() => q = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search',
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
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(30),
            ),
            child: widget.loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    itemCount: rows.length + 1,
                    itemBuilder: (_, i) {
                      if (i == rows.length) {
                        return Padding(
                          padding: const EdgeInsets.all(18),
                          child: Center(
                            child: Text('${list.length} Contacts',
                                style: const TextStyle(color: Colors.grey)),
                          ),
                        );
                      }
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
                      final c = r as Contact;
                      return InkWell(
                        onTap: () => _open(c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          child: Row(
                            children: [
                              Avatar(c.displayName, photo: _thumb(c), radius: 22),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  c.displayName.isEmpty
                                      ? '(No name)'
                                      : c.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ),
                              if (c.isStarred)
                                const Icon(Icons.star_rounded,
                                    size: 18, color: Colors.amber),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// Contact card: big photo, Message / Call / Mail, numbers, delete.
class ContactDetailPage extends StatefulWidget {
  const ContactDetailPage({super.key, required this.contact});
  final Contact contact;

  @override
  State<ContactDetailPage> createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends State<ContactDetailPage> {
  late Contact c = widget.contact;
  Uint8List? photo;

  @override
  void initState() {
    super.initState();
    photo = _thumb(c);
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    try {
      final full = await FlutterContacts.getContact(c.id,
          withProperties: true, withPhoto: true);
      if (full != null && mounted) {
        setState(() {
          c = full;
          final p = full.photo;
          if (p != null && p.isNotEmpty) photo = p;
        });
      }
    } catch (_) {}
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('${c.displayName} will be removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FlutterContacts.requestPermission(readonly: false);
      await FlutterContacts.deleteContact(c);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this contact')),
        );
      }
    }
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(icon, color: kBlue),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 11, color: kBlue)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: children),
      );

  Widget _line(String label, String value,
      {VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 16, color: kBlue)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = c.phones.isNotEmpty ? c.phones.first.number : null;
    final mail = c.emails.isNotEmpty ? c.emails.first.address : null;
    final org = c.organizations.isNotEmpty ? c.organizations.first.company : '';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  label: const Text('Contacts'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => FlutterContacts.openExternalEdit(c.id),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(child: Avatar(c.displayName, photo: photo, radius: 56)),
            const SizedBox(height: 14),
            Center(
              child: Text(
                c.displayName.isEmpty ? '(No name)' : c.displayName,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),
            if (org.isNotEmpty)
              Center(
                child: Text(org,
                    style: const TextStyle(fontSize: 15, color: Colors.grey)),
              ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: [
                  _action(Icons.message_rounded, 'message',
                      first == null ? null : () => launchUrl(Uri(scheme: 'sms', path: first))),
                  _action(Icons.call_rounded, 'call',
                      first == null ? null : () => placeCall(context, first)),
                  _action(Icons.mail_rounded, 'mail',
                      mail == null ? null : () => launchUrl(Uri(scheme: 'mailto', path: mail))),
                ],
              ),
            ),
            if (c.phones.isNotEmpty)
              _card([
                for (final p in c.phones)
                  _line(
                    p.customLabel.isNotEmpty ? p.customLabel : p.label.name,
                    p.number,
                    onTap: () => placeCall(context, p.number),
                    trailing: IconButton(
                      icon: const Icon(Icons.message_outlined,
                          size: 20, color: kBlue),
                      onPressed: () =>
                          launchUrl(Uri(scheme: 'sms', path: p.number)),
                    ),
                  ),
              ]),
            if (c.emails.isNotEmpty)
              _card([
                for (final e in c.emails)
                  _line(
                    e.customLabel.isNotEmpty ? e.customLabel : e.label.name,
                    e.address,
                    onTap: () => launchUrl(Uri(scheme: 'mailto', path: e.address)),
                  ),
              ]),
            _card([
              InkWell(
                onTap: _delete,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text('Delete Contact',
                        style: TextStyle(color: kRed, fontSize: 16)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
