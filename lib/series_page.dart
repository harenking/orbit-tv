import 'package:flutter/material.dart';
import 'api.dart';
import 'player_page.dart';
import 'storage.dart';
import 'tv.dart';

class SeriesPage extends StatefulWidget {
  final Xtream api;
  final Item item;
  const SeriesPage({super.key, required this.api, required this.item});

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  SeriesInfo? _info;
  String? _error;
  int? _season;

  @override
  void initState() {
    super.initState();
    widget.api.series(widget.item.id).then((i) {
      if (!mounted) return;
      final keys = i.seasons.keys.toList()..sort();
      setState(() {
        _info = i;
        _season = keys.isEmpty ? null : keys.first;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    });
  }

  void _play(Episode e) {
    final label = 'S${e.season.toString().padLeft(2, '0')}A${e.number.toString().padLeft(2, '0')}';
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => PlayerPage(
                  url: widget.api.episodeUrl(e.id, e.ext),
                  title: '${widget.item.name} · $label',
                  key2: 'e:${e.id}',
                  poster: e.image ?? widget.item.poster,
                  kind: 'episode',
                )))
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final seasons = info == null ? <int>[] : (info.seasons.keys.toList()..sort());
    final eps = info?.seasons[_season] ?? const <Episode>[];
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 24, 48, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.item.name, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 16),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 20)),
            if (info == null && _error == null) const Expanded(child: Center(child: CircularProgressIndicator())),
            if (info != null) ...[
              SizedBox(
                height: 52,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final s in seasons)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: TvButton(label: 'Säsong $s', selected: s == _season, onTap: () => setState(() => _season = s), autofocus: s == seasons.first),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: eps.length,
                  itemBuilder: (c, i) {
                    final e = eps[i];
                    final p = Store.progress('e:${e.id}');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Tv(
                        onTap: () => _play(e),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(color: f ? Colors.white24 : kPanel, borderRadius: BorderRadius.circular(9)),
                          child: Row(children: [
                            SizedBox(width: 56, child: Text('${e.number}', style: const TextStyle(fontSize: 20, color: Colors.white70))),
                            Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, color: Colors.white))),
                            if (p != null && p.durSec > 0 && p.posSec > 10 && p.posSec < p.durSec * 0.95)
                              Text('Fortsätt ${fmtTime(p.posSec)}', style: const TextStyle(fontSize: 16, color: kAccent)),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
