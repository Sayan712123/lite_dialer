import 'package:flutter/material.dart';

import 'helpers.dart';

const _keyRows = [
  [['1', ''], ['2', 'ABC'], ['3', 'DEF']],
  [['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO']],
  [['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ']],
  [['*', ''], ['0', '+'], ['#', '']],
];

/// Dialer screen: rounded top panel with the number, round keys below.
class DialerPage extends StatelessWidget {
  const DialerPage({
    super.key,
    required this.digits,
    required this.people,
    required this.menu,
    required this.onBack,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onPaste,
    required this.onCall,
    required this.onCallNumber,
  });

  final String digits;
  final List<Person> people;
  final Widget menu;
  final VoidCallback onBack, onBackspace, onClear, onPaste, onCall;
  final ValueChanged<String> onDigit;
  final ValueChanged<String> onCallNumber;

  @override
  Widget build(BuildContext context) {
    Person? match;
    if (digits.isNotEmpty) {
      for (final p in people) {
        if (p.number.replaceAll(RegExp(r'\D'), '').contains(digits) ||
            toT9(p.name).contains(digits)) {
          match = p;
          break;
        }
      }
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(36)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: onBack,
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'DIALER',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8),
                      ),
                    ),
                  ),
                  menu,
                ],
              ),
              SizedBox(height: 40, child: _suggestion(match)),
              SizedBox(
                height: 84,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: onPaste,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: digits.isEmpty
                          ? const Text(
                              'Enter number',
                              style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w300,
                                  color: Colors.grey),
                            )
                          : Text(
                              digits,
                              style: const TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: 1),
                            ),
                    ),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, c) {
              const gap = 12.0;
              final size =
                  ((c.maxHeight - 5 * gap) / 5).clamp(44.0, 76.0).toDouble();
              final fill = fillColor(ctx);
              Widget key(List<String> k) => GestureDetector(
                    onTap: () => onDigit(k[0]),
                    onLongPress: k[0] == '0' ? () => onDigit('+') : null,
                    child: Container(
                      width: size,
                      height: size,
                      decoration:
                          BoxDecoration(color: fill, shape: BoxShape.circle),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(k[0],
                              style: TextStyle(
                                  fontSize: size * 0.4,
                                  fontWeight: FontWeight.w400)),
                          if (k[1].isNotEmpty)
                            Text(k[1],
                                style: const TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 1.5,
                                    color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final row in _keyRows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: gap),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [for (final k in row) key(k)],
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(width: size, height: size),
                        GestureDetector(
                          onTap: onCall,
                          child: Container(
                            width: size,
                            height: size,
                            decoration: const BoxDecoration(
                                color: kGreen, shape: BoxShape.circle),
                            child: Icon(Icons.call,
                                color: Colors.white, size: size * 0.42),
                          ),
                        ),
                        SizedBox(
                          width: size,
                          height: size,
                          child: GestureDetector(
                            onLongPress: onClear,
                            child: IconButton(
                              icon: const Icon(Icons.backspace_outlined),
                              onPressed: onBackspace,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _suggestion(Person? p) {
    if (p == null) return const SizedBox();
    return GestureDetector(
      onTap: () => onCallNumber(p.number),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Avatar(p.name, photo: p.thumb, radius: 14),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${p.name}  ${p.number}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
