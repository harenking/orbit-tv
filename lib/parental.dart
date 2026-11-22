import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'storage.dart';
import 'tv.dart';

/// Föräldralås: regler gäller bara när en PIN finns och minst en regel är satt.
class Guard {
  static DateTime? _until;
  static bool _forever = false;
  static int _fails = 0;
  static DateTime? _blockedUntil;

  static const vaultId = '__vault__';
  static const vaultName = 'Systemfiler 7F';

  static bool get active => Store.hasPin && (Store.lockedCats.isNotEmpty || Store.keywords.trim().isNotEmpty);
  static bool get unlocked => _forever || (_until != null && DateTime.now().isBefore(_until!));

  /// Gäller reglerna den här kategorin?
  static bool matches(String catName) {
    if (!active) return false;
    final n = catName.toLowerCase();
    if (Store.lockedCats.any((c) => c.toLowerCase() == n)) return true;
    final kws = Store.keywords.split(',').map((k) => k.trim().toLowerCase()).where((k) => k.isNotEmpty);
    return kws.any((k) => n.contains(k));
  }

  static void _unlock() {
    final m = Store.unlockMinutes;
    if (m == 0) {
      _forever = true;
    } else {
      _until = DateTime.now().add(Duration(minutes: m));
    }
  }

  static void lock() {
    _forever = false;
    _until = null;
  }

  static String mask(String t) {
    final x = t.trim();
    return x.length <= 2 ? '*****' : '${x.substring(0, 2)}*****';
  }

  /// Ber om PIN om något är låst. Returnerar true när det är upplåst (eller inget lås finns).
  static Future<bool> ensure(BuildContext context, {String title = 'Ange PIN-kod'}) async {
    if (!Store.hasPin || unlocked) return true;
    final pin = await askPin(context, title: title, check: _check);
    return pin != null;
  }

  static String? _check(String pin) {
    if (_blockedUntil != null && DateTime.now().isBefore(_blockedUntil!)) {
      return 'För många försök. Vänta ${_blockedUntil!.difference(DateTime.now()).inSeconds} s.';
    }
    if (Store.verifyPin(pin)) {
      _fails = 0;
      _unlock();
      return null;
    }
    _fails++;
    if (_fails >= 5) {
      _fails = 0;
      _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
      return 'För många försök. Vänta 30 s.';
    }
    return 'Fel PIN';
  }

  /// Dialog med sifferpad. [check] returnerar null om koden är godkänd, annars ett felmeddelande.
  static Future<String?> askPin(BuildContext context, {required String title, String? hint, String? Function(String pin)? check}) {
    return showDialog<String>(context: context, barrierDismissible: true, builder: (_) => _PinDialog(title: title, hint: hint, check: check));
  }
}

class _PinDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String? Function(String pin)? check;
  const _PinDialog({required this.title, this.hint, this.check});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';
  String? _error;

  // Knappsatsen styrs med egna fokusnoder så att piltangenterna alltid fungerar
  static const _grid = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['<', '0', 'OK'],
  ];
  final List<List<FocusNode>> _nodes = List.generate(4, (_) => List.generate(3, (_) => FocusNode()));

  @override
  void dispose() {
    for (final r in _nodes) {
      for (final n in r) {
        n.dispose();
      }
    }
    super.dispose();
  }

  bool _move(int dr, int dc) {
    var r = 1, c = 1;
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 3; j++) {
        if (_nodes[i][j].hasFocus) {
          r = i;
          c = j;
        }
      }
    }
    final nr = (r + dr).clamp(0, 3);
    final nc = (c + dc).clamp(0, 2);
    _nodes[nr][nc].requestFocus();
    return true;
  }

  void _press(String k) {
    if (k == '<') {
      _back();
    } else if (k == 'OK') {
      _ok();
    } else {
      _add(k);
    }
  }

  void _add(String d) {
    if (_pin.length >= 8) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _back() => setState(() {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
        _error = null;
      });

  void _ok() {
    if (_pin.length < 4) {
      setState(() => _error = 'Minst 4 siffror');
      return;
    }
    final err = widget.check?.call(_pin);
    if (err != null) {
      setState(() {
        _error = err;
        _pin = '';
      });
      return;
    }
    Navigator.of(context).pop(_pin);
  }

  Widget _key(String label, VoidCallback onTap, {bool autofocus = false, IconData? icon, FocusNode? node}) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Tv(
        autofocus: autofocus,
        focusNode: node,
        onTap: onTap,
        builder: (c, f) => Container(
          width: 76,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: f ? Colors.white24 : Colors.white10, borderRadius: BorderRadius.circular(10)),
          child: icon != null ? Icon(icon, size: 26) : Text(label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        final isDown = e is KeyDownEvent;
        final ch = e.character;
        if (isDown && ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
          _add(ch);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.backspace) {
          _back();
          return KeyEventResult.handled;
        }
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowUp && _move(-1, 0)) return KeyEventResult.handled;
        if (k == LogicalKeyboardKey.arrowDown && _move(1, 0)) return KeyEventResult.handled;
        if (k == LogicalKeyboardKey.arrowLeft && _move(0, -1)) return KeyEventResult.handled;
        if (k == LogicalKeyboardKey.arrowRight && _move(0, 1)) return KeyEventResult.handled;
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        backgroundColor: kPanel,
        title: Text(widget.title, textAlign: TextAlign.center),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.hint != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(widget.hint!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center)),
            Text(_pin.isEmpty ? '–' : '•' * _pin.length, style: const TextStyle(fontSize: 34, letterSpacing: 6)),
            SizedBox(height: 22, child: Text(_error ?? '', style: const TextStyle(color: Colors.redAccent))),
            for (var r = 0; r < 4; r++)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var c = 0; c < 3; c++)
                  _key(_grid[r][c] == '<' ? '' : _grid[r][c], () => _press(_grid[r][c]),
                      autofocus: r == 1 && c == 1, node: _nodes[r][c], icon: _grid[r][c] == '<' ? Icons.backspace_outlined : null),
              ]),
          ]),
        ),
      ),
    );
  }
}
