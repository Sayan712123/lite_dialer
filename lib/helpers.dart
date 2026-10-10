import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'incall.dart';

const kBlue = Color(0xFF0D84FF);
const kGreen = Color(0xFF34C759);
const kRed = Color(0xFFFF3B30);

// ---------- helpers ----------

class Person {
  Person(this.name, this.number, this.fav, [this.thumb]);
  final String name, number;
  final bool fav;
  final Uint8List? thumb;
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
  const Avatar(this.name, {this.photo, super.key});
  final String name;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    const colors = [
      0xFF5B8DEF, 0xFF34C759, 0xFFFF9F0A, 0xFFAF52DE, 0xFFFF6B6B, 0xFF30B0C7,
    ];
    final c = Color(colors[name.codeUnits.fold(0, (a, b) => a + b) % colors.length]);
    final has = photo != null && photo!.isNotEmpty;
    return CircleAvatar(
      radius: 22,
      backgroundColor: name.isEmpty ? const Color(0xFF2C3E63) : c,
      backgroundImage: has ? ResizeImage(MemoryImage(photo!), width: 96) : null,
      child: has
          ? null
          : (name.isEmpty
              ? const Icon(Icons.person, color: Colors.white)
              : Text(
                  String.fromCharCode(name.runes.first).toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600),
                )),
    );
  }
}
