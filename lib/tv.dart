import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kAccent = Color(0xFF7C5CFF);
const kBg = Color(0xFF0B0D17);
const kPanel = Color(0xFF151828);

/// Fjärrkontrollsvänlig knapp/ruta: kan väljas med piltangenter och aktiveras med OK.
class Tv extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress; // håll OK nedan på fjärrkontrollen
  final bool autofocus;
  final BorderRadius radius;
  const Tv({super.key, required this.builder, this.onTap, this.onLongPress, this.autofocus = false, this.radius = const BorderRadius.all(Radius.circular(12))});

  @override
  State<Tv> createState() => _TvState();
}

class _TvState extends State<Tv> {
  bool _f = false;
  bool _down = false;
  bool _long = false;

  KeyEventResult _key(FocusNode n, KeyEvent e) {
    if (widget.onLongPress == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k != LogicalKeyboardKey.select && k != LogicalKeyboardKey.enter && k != LogicalKeyboardKey.gameButtonA) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _down = true;
      _long = false;
    } else if (e is KeyRepeatEvent) {
      if (_down && !_long) {
        _long = true;
        widget.onLongPress!();
      }
    } else if (e is KeyUpEvent) {
      final wasShort = _down && !_long;
      _down = false;
      _long = false;
      if (wasShort) widget.onTap?.call();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _key,
      child: InkWell(
      autofocus: widget.autofocus,
      borderRadius: widget.radius,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      onFocusChange: (f) {
        setState(() => _f = f);
        if (f) {
          Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 150));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          border: Border.all(color: _f ? Colors.white : Colors.transparent, width: 3),
          boxShadow: _f ? [BoxShadow(color: kAccent.withAlpha(140), blurRadius: 18)] : null,
        ),
        child: widget.builder(context, _f),
      ),
    ));
  }
}

class TvButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool selected;
  final bool autofocus;
  const TvButton({super.key, required this.label, required this.onTap, this.icon, this.selected = false, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return Tv(
      autofocus: autofocus,
      onTap: onTap,
      radius: BorderRadius.circular(24),
      builder: (c, f) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? kAccent : (f ? Colors.white24 : Colors.white10),
          borderRadius: BorderRadius.circular(21),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 20, color: Colors.white), const SizedBox(width: 8)],
          Text(label, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

String fmtTime(int sec) {
  if (sec < 0) sec = 0;
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

Widget posterImage(String? url, {double? w, double? h, BoxFit fit = BoxFit.cover}) {
  final ph = Container(width: w, height: h, color: Colors.white10, child: const Center(child: Icon(Icons.movie_outlined, color: Colors.white24, size: 40)));
  if (url == null || !url.startsWith('http')) return ph;
  return Image.network(url, width: w, height: h, fit: fit, errorBuilder: (_, __, ___) => ph, loadingBuilder: (c, child, p) => p == null ? child : ph);
}

/// Låter upp/ner på fjärrkontrollen flytta markeringen även när en textruta har fokus
/// (textrutor "äter" annars piltangenterna).
class DpadNav extends StatelessWidget {
  final Widget child;
  const DpadNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.select) {
          SystemChannels.textInput.invokeMethod<void>('TextInput.show');
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown) {
          FocusScope.of(context).focusInDirection(TraversalDirection.down);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp) {
          FocusScope.of(context).focusInDirection(TraversalDirection.up);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// Textruta för TV: OK öppnar ett eget tangentbord som styrs helt med piltangenterna
/// (systemets tangentbord låter piltangenterna flytta markören i stället).
class TvField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? action;
  final void Function(String)? onSubmitted;
  final void Function(String)? onChanged;
  final IconData? icon;
  const TvField({
    super.key,
    required this.controller,
    required this.label,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.action,
    this.onSubmitted,
    this.onChanged,
    this.icon,
  });

  Future<void> _open(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => TvKeyboard(
        label: label,
        controller: controller,
        obscure: obscure,
        url: keyboardType == TextInputType.url,
        onChanged: onChanged,
      ),
    );
    onSubmitted?.call(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Tv(
      autofocus: autofocus,
      onTap: () => _open(context),
      radius: BorderRadius.circular(12),
      builder: (c, f) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (c, v, _) {
          final t = v.text;
          final shown = obscure ? '•' * t.length : t;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: f ? Colors.white24 : Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, color: Colors.white70), const SizedBox(width: 12)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.white60)),
                  const SizedBox(height: 2),
                  Text(shown.isEmpty ? ' ' : shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, color: Colors.white)),
                ]),
              ),
              const Icon(Icons.keyboard, color: Colors.white38),
            ]),
          );
        },
      ),
    );
  }
}

/// Tangentbord som alla fjärrkontroller kan använda: välj tecken med piltangenterna och tryck OK.
class TvKeyboard extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final bool url;
  final void Function(String)? onChanged;
  const TvKeyboard({super.key, required this.label, required this.controller, this.obscure = false, this.url = false, this.onChanged});

  @override
  State<TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<TvKeyboard> {
  bool _shift = false;
  bool _show = false;

  static const _rows = [
    '1234567890',
    'qwertyuiopå',
    'asdfghjklöä',
    'zxcvbnm-_.@',
  ];

  void _set(String t) {
    widget.controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    widget.onChanged?.call(t);
    setState(() {});
  }

  void _type(String c) {
    _set(widget.controller.text + (_shift ? c.toUpperCase() : c));
    if (_shift) setState(() => _shift = false);
  }

  void _back() {
    final t = widget.controller.text;
    if (t.isNotEmpty) _set(t.substring(0, t.length - 1));
  }

  Widget _key(String label, VoidCallback onTap, {double w = 62, bool autofocus = false, bool selected = false, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        width: w,
        height: 54,
        child: Tv(
          autofocus: autofocus,
          onTap: onTap,
          radius: BorderRadius.circular(10),
          builder: (c, f) => Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: selected ? kAccent : (f ? Colors.white24 : Colors.white12), borderRadius: BorderRadius.circular(8)),
            child: icon != null ? Icon(icon, color: Colors.white) : Text(label, style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.controller.text;
    final shown = widget.obscure && !_show ? '•' * t.length : t;
    return Dialog(
      backgroundColor: kBg,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.label, style: const TextStyle(fontSize: 16, color: Colors.white60)),
            const SizedBox(height: 6),
            Container(
              width: 760,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: kAccent, width: 2)),
              child: Text('${shown.isEmpty ? '' : shown}▏', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.left, style: const TextStyle(fontSize: 24, color: Colors.white)),
            ),
            const SizedBox(height: 10),
            for (var r = 0; r < _rows.length; r++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final ch in _rows[r].split(''))
                  _key(_shift ? ch.toUpperCase() : ch, () => _type(ch), autofocus: r == 1 && ch == 'q'),
              ]),
            if (widget.url)
              Row(mainAxisSize: MainAxisSize.min, children: [
                _key('http://', () => _set('${widget.controller.text}http://'), w: 120),
                for (final ch in ':/?&=%#+'.split('')) _key(ch, () => _type(ch)),
              ])
            else
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final ch in '!?,:;/+*()'.split('')) _key(ch, () => _type(ch)),
              ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _key('Skift', () => setState(() => _shift = !_shift), w: 110, selected: _shift, icon: Icons.keyboard_capslock),
              _key('Mellanslag', () => _type(' '), w: 220, icon: Icons.space_bar),
              _key('Radera', _back, w: 110, icon: Icons.backspace_outlined),
              _key('Rensa', () => _set(''), w: 110, icon: Icons.delete_sweep),
              if (widget.obscure) _key('Visa', () => setState(() => _show = !_show), w: 90, selected: _show, icon: Icons.visibility),
            ]),
            const SizedBox(height: 8),
            TvButton(label: 'Klar', icon: Icons.check, selected: true, onTap: () => Navigator.of(context).pop()),
          ]),
        ),
      ),
    );
  }
}
