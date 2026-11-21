import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kAccent = Color(0xFF7C5CFF);
const kBg = Color(0xFF0B0D17);
const kPanel = Color(0xFF151828);

/// Fjärrkontrollsvänlig knapp/ruta: kan väljas med piltangenter och aktiveras med OK.
class Tv extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onTap;
  final bool autofocus;
  final BorderRadius radius;
  const Tv({super.key, required this.builder, this.onTap, this.autofocus = false, this.radius = const BorderRadius.all(Radius.circular(12))});

  @override
  State<Tv> createState() => _TvState();
}

class _TvState extends State<Tv> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: widget.radius,
      onTap: widget.onTap,
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
    );
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
