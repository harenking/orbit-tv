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
  final bool locked;
  final Fav? fav; // om titeln kan göras till favorit
  final EpMeta? ep; // vilket avsnitt (serier)
  final PlayerPage Function()? next; // nästa avsnitt
  final String? nextLabel;
  const PlayerPage({super.key, required this.url, required this.title, required this.key2, this.poster, this.live = false, this.kind = 'movie', this.locked = false, this.fav, this.ep, this.next, this.nextLabel});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player player = Player(configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
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

  // Fortsätt titta: hoppet görs först när filen är laddad (mpv ignorerar annars ofta startpunkten)
  Duration? _pendingResume;
  bool _resuming = false;

  // Nästa avsnitt
  bool _nextDismissed = false;
  bool _leaving = false;

  // Meny (undertexter, ljud, hastighet, favorit)
  String? _menu; // null | main | subs | audio | speed
  double _speed = Store.defaultSpeed;
  bool _autoSubDone = false;
  late bool _isFav = widget.fav != null && Store.isFav(widget.fav!);

  static const _langCodes = {
    'sv': ['sv', 'swe', 'svenska', 'swedish'],
    'en': ['en', 'eng', 'english', 'engelska'],
    'no': ['no', 'nor', 'nob', 'norwegian', 'norska'],
    'da': ['da', 'dan', 'danish', 'danska'],
    'fi': ['fi', 'fin', 'finnish', 'finska'],
  };

  String _trackName(String id, String? title, String? language, int n) {
    if (id == 'no') return 'Av';
    if (id == 'auto') return 'Automatiskt';
    final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) language];
    return parts.isEmpty ? 'Spår $n' : parts.join(' · ');
  }

  bool _isPreferred(SubtitleTrack t) {
    final codes = _langCodes[Store.subLang] ?? [Store.subLang];
    final l = (t.language ?? '').toLowerCase();
    final ti = (t.title ?? '').toLowerCase();
    return codes.any((c) => l == c || (c.length > 3 && (l.contains(c) || ti.contains(c))) || ti == c);
  }

  /// Väljer önskat undertextspråk automatiskt när spåren blivit kända.
  void _autoSubs(Tracks t) {
    if (_autoSubDone || !Store.autoSubs) return;
    final real = t.subtitle.where((x) => x.id != 'auto' && x.id != 'no').toList();
    if (real.isEmpty) return;
    _autoSubDone = true;
    final pick = real.where(_isPreferred).toList();
    if (pick.isNotEmpty) player.setSubtitleTrack(pick.first);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _start();
  }

  Future<void> _start() async {
    final saved = (widget.live || !Store.autoResume) ? null : Store.progress(widget.key2);
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
      final r = _pendingResume;
      if (r != null && d > Duration.zero) {
        _pendingResume = null;
        _resume(r);
      }
    }));
    _subs.add(player.stream.playing.listen((p) {
      if (!mounted) return;
      setState(() => _playing = p);
    }));
    _subs.add(player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _buffering = b);
    }));
    _subs.add(player.stream.tracks.listen((t) {
      if (!mounted) return;
      _autoSubs(t);
      setState(() {});
    }));
    _subs.add(player.stream.error.listen((e) {
      if (!mounted) return;
      setState(() => _error = e);
    }));
    _subs.add(player.stream.completed.listen((c) {
      if (c && !widget.live && !_leaving) {
        if (widget.next != null) {
          _playNext();
        } else {
          _leaving = true;
          Store.markWatched(widget.key2);
          Store.removeProgress(widget.key2);
          if (mounted) Navigator.of(context).maybePop();
        }
      }
    }));
    if (widget.ep != null) Store.setLastEp(widget.ep!.seriesId, widget.key2);
    _pendingResume = start;
    await player.open(Media(widget.url));
    if (_speed != 1.0 && !widget.live) await player.setRate(_speed);
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    _poke();
  }

  /// Hoppar till sparad position och kontrollerar att det verkligen hamnade där.
  Future<void> _resume(Duration to) async {
    _resuming = true;
    for (var i = 0; i < 5 && mounted; i++) {
      await Future.delayed(Duration(milliseconds: i == 0 ? 250 : 1500));
      if (!mounted) return;
      if ((player.state.position - to).abs() < const Duration(seconds: 15)) break;
      await player.seek(to);
    }
    _resuming = false;
  }

  bool get _nextVisible {
    if (widget.next == null || _nextDismissed || _menu != null || _leaving) return false;
    if (_dur < const Duration(minutes: 5)) return false;
    final remain = _dur - _pos;
    final window = _dur > const Duration(minutes: 20) ? const Duration(seconds: 90) : const Duration(seconds: 30);
    return remain > Duration.zero && remain <= window;
  }

  void _playNext() {
    if (_leaving || widget.next == null || !mounted) return;
    _leaving = true;
    Store.markWatched(widget.key2);
    Store.removeProgress(widget.key2);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.next!()));
  }

  void _save() {
    if (widget.live || _leaving || _resuming || _pendingResume != null) return;
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
      locked: widget.locked,
      ep: widget.ep,
    ));
    if (pos >= dur * 0.95) Store.markWatched(widget.key2);
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
    if (_menu != null) return KeyEventResult.ignored; // menyn sköter sina egna tangenter
    if (_nextVisible) {
      if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.mediaPlayPause) {
        _playNext();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        setState(() => _nextDismissed = true);
        return KeyEventResult.handled;
      }
    }
    // Meny: tryck ner när fälten syns, eller på menyknappen
    if (k == LogicalKeyboardKey.arrowDown && _showUi && e is KeyDownEvent) {
      setState(() => _menu = 'main');
      _hideTimer?.cancel();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.contextMenu || k == LogicalKeyboardKey.keyM) {
      setState(() => _menu = 'main');
      _hideTimer?.cancel();
      return KeyEventResult.handled;
    }
    // Längre tryck → större hopp
    final rep = e is KeyRepeatEvent;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(rep ? -Store.seekStep * 3 : -Store.seekStep);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(rep ? Store.seekStep * 3 : Store.seekStep);
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

  void _closeMenu() {
    setState(() => _menu = null);
    _focus.requestFocus();
    _poke();
  }

  Widget _opt(String label, bool selected, VoidCallback onTap, {bool autofocus = false, IconData? icon}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: TvButton(label: label, icon: icon ?? (selected ? Icons.check : null), selected: selected, autofocus: autofocus, onTap: onTap),
      );

  Widget _nextCard() {
    final remain = (_dur - _pos).inSeconds;
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.fromLTRB(48, 48, 48, 150),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(color: Colors.black.withAlpha(230), borderRadius: BorderRadius.circular(16), border: Border.all(color: kAccent, width: 2)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.skip_next, color: Colors.white, size: 32),
            const SizedBox(width: 10),
            const Text('Spela nästa avsnitt', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            Text('$remain s', style: const TextStyle(fontSize: 18, color: Colors.white70)),
          ]),
          if (widget.nextLabel != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(widget.nextLabel!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, color: Colors.white))),
          const SizedBox(height: 10),
          const Text('OK = spela nu   ▲ = dölj', style: TextStyle(fontSize: 16, color: Colors.white60)),
        ]),
      ),
    );
  }

  Widget _menuPanel() {
    final tr = player.state.tracks;
    final cur = player.state.track;
    final children = <Widget>[];
    String title;
    switch (_menu) {
      case 'subs':
        title = 'Undertexter';
        final subs = tr.subtitle.where((x) => x.id != 'auto').toList();
        var n = 0;
        for (final t in subs) {
          if (t.id != 'no') n++;
          final sel = cur.subtitle.id == t.id;
          children.add(_opt(_trackName(t.id, t.title, t.language, n), sel, () {
            player.setSubtitleTrack(t);
            _closeMenu();
          }, autofocus: sel));
        }
        if (subs.length <= 1) children.add(const Padding(padding: EdgeInsets.only(top: 8), child: Text('Inga undertexter hittades i filen.', style: TextStyle(color: Colors.white70, fontSize: 16))));
      case 'audio':
        title = 'Ljudspår';
        final aud = tr.audio.where((x) => x.id != 'auto' && x.id != 'no').toList();
        var n = 0;
        for (final t in aud) {
          n++;
          final sel = cur.audio.id == t.id;
          children.add(_opt(_trackName(t.id, t.title, t.language, n), sel, () {
            player.setAudioTrack(t);
            _closeMenu();
          }, autofocus: sel));
        }
        if (aud.isEmpty) children.add(const Text('Inga ljudspår hittades.', style: TextStyle(color: Colors.white70, fontSize: 16)));
      case 'speed':
        title = 'Hastighet';
        for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) {
          children.add(_opt('${r == r.roundToDouble() ? r.toInt() : r}×', _speed == r, () {
            setState(() => _speed = r);
            player.setRate(r);
            _closeMenu();
          }, autofocus: _speed == r));
        }
      default:
        title = 'Meny';
        if (!widget.live) {
          children.add(_opt('Undertexter', false, () => setState(() => _menu = 'subs'), autofocus: true, icon: Icons.subtitles));
          children.add(_opt('Ljudspår', false, () => setState(() => _menu = 'audio'), icon: Icons.audiotrack));
          children.add(_opt('Hastighet (${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}×)', false, () => setState(() => _menu = 'speed'), icon: Icons.speed));
        } else {
          children.add(_opt('Ljudspår', false, () => setState(() => _menu = 'audio'), autofocus: true, icon: Icons.audiotrack));
        }
        if (widget.fav != null) {
          children.add(_opt(_isFav ? 'Ta bort favorit' : 'Lägg till favorit', false, () async {
            final on = await Store.toggleFav(widget.fav!);
            if (mounted) setState(() => _isFav = on);
          }, icon: _isFav ? Icons.favorite : Icons.favorite_border));
        }
        children.add(_opt('Stäng', false, _closeMenu, icon: Icons.close));
    }
    return FocusScope(
      key: ValueKey('menu-$_menu'),
      autofocus: true,
      child: Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 420,
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.black.withAlpha(225), borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      ),
    ));
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
    return PopScope(
      canPop: _menu == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_menu != null && _menu != 'main') {
          setState(() => _menu = 'main');
        } else {
          _closeMenu();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(fit: StackFit.expand, children: [
          Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
            subtitleViewConfiguration: SubtitleViewConfiguration(
              style: TextStyle(
                fontSize: Store.subSize.toDouble(),
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Store.subYellow ? const Color(0xFFFFE94A) : Colors.white,
                backgroundColor: Store.subBg ? const Color(0xAA000000) : null,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
              textAlign: TextAlign.center,
              padding: const EdgeInsets.fromLTRB(48, 0, 48, 56),
            ),
          ),
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.ep?.series ?? widget.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (widget.ep != null) Text('${widget.ep!.short}${widget.ep!.title.isNotEmpty ? ' · ${widget.ep!.title}' : ''}', style: const TextStyle(fontSize: 20, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(48, 48, 48, 32),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                  child: widget.live
                      ? const Row(children: [Text('LIVE', style: TextStyle(fontSize: 20, color: Colors.redAccent, fontWeight: FontWeight.w800)), Spacer(), Text('▼ Meny', style: TextStyle(fontSize: 16, color: Colors.white60))])
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
                            const Spacer(),
                            const Text('▼ Meny', style: TextStyle(fontSize: 16, color: Colors.white60)),
                          ]),
                        ]),
                ),
              ]),
            ),
          ),
          if (_nextVisible) _nextCard(),
          if (_menu != null) _menuPanel(),
        ]),
      ),
    ));
  }
}
