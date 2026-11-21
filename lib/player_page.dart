import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'storage.dart';
import 'tv.dart';

/// Fullskärmsspelare (mpv via media_kit). Styrs helt med fjärrkontrollen:
/// vänster/höger = spola, OK = paus/play, upp/ner = visa fält, Tillbaka = stäng.
class PlayerPage extends StatefulWidget {
  final String url;
  final String title;
  final String key2; // nyckel för fortsätt titta
  final String? poster;
  final bool live;
  final String kind; // movie | episode
  const PlayerPage({super.key, required this.url, required this.title, required this.key2, this.poster, this.live = false, this.kind = 'movie'});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player player = Player(configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
  late final VideoController controller = VideoController(player);
  final FocusNode _focus = FocusNode();

  bool _showUi = true;
  bool _playing = true;
  bool _buffering = true;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  Duration? _seekTarget;
  Timer? _hideTimer;
  Timer? _seekTimer;
  Timer? _saveTimer;
  final List<StreamSubscription> _subs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _start();
  }

  Future<void> _start() async {
    final saved = widget.live ? null : Store.progress(widget.key2);
    Duration? start;
    if (saved != null && saved.posSec > 10 && saved.durSec > 0 && saved.posSec < saved.durSec * 0.95) {
      start = Duration(seconds: saved.posSec);
    }
    _subs.add(player.stream.position.listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
    }));
    _subs.add(player.stream.duration.listen((d) {
      if (!mounted) return;
      setState(() => _dur = d);
    }));
    _subs.add(player.stream.playing.listen((p) {
      if (!mounted) return;
      setState(() => _playing = p);
    }));
    _subs.add(player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _buffering = b);
    }));
    _subs.add(player.stream.error.listen((e) {
      if (!mounted) return;
      setState(() => _error = e);
    }));
    _subs.add(player.stream.completed.listen((c) {
      if (c && !widget.live) {
        Store.removeProgress(widget.key2);
        if (mounted) Navigator.of(context).maybePop();
      }
    }));
    await player.open(Media(widget.url, start: start));
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    _poke();
  }

  void _save() {
    if (widget.live) return;
    final pos = player.state.position.inSeconds;
    final dur = player.state.duration.inSeconds;
    if (dur <= 0 || pos < 5) return;
    Store.saveProgress(Progress(
      key: widget.key2,
      title: widget.title,
      poster: widget.poster,
      url: widget.url,
      posSec: pos,
      durSec: dur,
      updated: DateTime.now().millisecondsSinceEpoch,
      kind: widget.kind,
    ));
  }

  void _poke() {
    _hideTimer?.cancel();
    if (!_showUi) setState(() => _showUi = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _showUi = false);
    });
  }

  /// Samlar flera tryck till ett enda hopp, så en lång fil inte behöver söka för varje tryck.
  void _seekBy(int seconds) {
    if (widget.live) return;
    final base = _seekTarget ?? _pos;
    var t = base + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (_dur > Duration.zero && t > _dur) t = _dur;
    setState(() => _seekTarget = t);
    _poke();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 600), () async {
      final target = _seekTarget;
      if (target == null) return;
      await player.seek(target);
      if (mounted) setState(() => _seekTarget = null);
    });
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // Längre tryck → större hopp
    final rep = e is KeyRepeatEvent;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(rep ? -30 : -10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(rep ? 30 : 10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.mediaPlayPause) {
      player.playOrPause();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      player.play();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause) {
      player.pause();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _poke();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekTimer?.cancel();
    _saveTimer?.cancel();
    _save();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    _focus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _seekTarget ?? _pos;
    final frac = _dur.inMilliseconds > 0 ? (shown.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(fit: StackFit.expand, children: [
          Video(controller: controller, controls: NoVideoControls, fit: BoxFit.contain),
          if (_buffering && _error == null) const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_error != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.all(48),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
                child: Text('Kunde inte spela upp:\n$_error', style: const TextStyle(fontSize: 22, color: Colors.white), textAlign: TextAlign.center),
              ),
            ),
          AnimatedOpacity(
            opacity: _showUi ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              child: Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(48, 32, 48, 48),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
                  child: Text(widget.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(48, 48, 48, 32),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                  child: widget.live
                      ? const Text('LIVE', style: TextStyle(fontSize: 20, color: Colors.redAccent, fontWeight: FontWeight.w800))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: frac, minHeight: 8, backgroundColor: Colors.white24, color: kAccent),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Icon(_playing ? Icons.play_arrow : Icons.pause, color: Colors.white, size: 30),
                            const SizedBox(width: 12),
                            Text('${fmtTime(shown.inSeconds)} / ${fmtTime(_dur.inSeconds)}', style: const TextStyle(fontSize: 22, color: Colors.white)),
                            if (_seekTarget != null) ...[
                              const SizedBox(width: 16),
                              const Text('Spolar…', style: TextStyle(fontSize: 18, color: Colors.white70)),
                            ],
                          ]),
                        ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
