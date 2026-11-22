import 'package:flutter/material.dart';
import 'api.dart';
import 'open.dart';
import 'storage.dart';
import 'tv.dart';

class SeriesPage extends StatefulWidget {
  final Source api;
  final Item item;
  final bool locked;
  const SeriesPage({super.key, required this.api, required this.item, this.locked = false});

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  SeriesInfo? _info;
  String? _error;
  int? _season;
  late bool _fav = Store.isFav(Fav(accId: widget.api.a.id, kind: 'series', id: widget.item.id, name: ''));

  @override
  void initState() {
    super.initState();
    widget.api.series(widget.item.id).then((i) {
      if (!mounted) return;
      final keys = i.seasons.keys.toList()..sort();
      // Öppna säsongen med avsnittet man senast tittade på
      final last = Store.lastEp(widget.item.id);
      int? season;
      if (last != null) {
        for (final e in flatEpisodes(i)) {
          if ('e:${e.id}' == last) season = e.season;
        }
      }
      setState(() {
        _info = i;
        _season = season ?? (keys.isEmpty ? null : keys.first);
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    });
  }

  void _play(Episode e) {
    final all = flatEpisodes(_info!);
    final i = all.indexWhere((x) => x.id == e.id);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => episodePlayer(widget.api, widget.item, all, i < 0 ? 0 : i, locked: widget.locked))).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Avsnittet man är på: senast spelade, eller nästa om det är färdigsett.
  String? _currentKey() {
    final info = _info;
    final last = Store.lastEp(widget.item.id);
    if (info == null || last == null) return null;
    if (!Store.isWatched(last) || Store.progress(last) != null) return last;
    final all = flatEpisodes(info);
    final i = all.indexWhere((e) => 'e:${e.id}' == last);
    if (i >= 0 && i + 1 < all.length) return 'e:${all[i + 1].id}';
    return last;
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final seasons = info == null ? <int>[] : (info.seasons.keys.toList()..sort());
    final eps = [...(info?.seasons[_season] ?? const <Episode>[])]..sort((a, b) => a.number.compareTo(b.number));
    final cur = _currentKey();
    Episode? curEp;
    if (info != null && cur != null) {
      for (final e in flatEpisodes(info)) {
        if ('e:${e.id}' == cur) curEp = e;
      }
    }
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 24, 48, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white))),
              TvButton(
                label: _fav ? 'Favorit' : 'Lägg till favorit',
                icon: _fav ? Icons.favorite : Icons.favorite_border,
                selected: _fav,
                onTap: () async {
                  final on = await Store.toggleFav(Fav(accId: widget.api.a.id, kind: 'series', id: widget.item.id, name: widget.item.name, poster: widget.item.poster, ext: widget.item.ext, locked: widget.locked));
                  if (mounted) setState(() => _fav = on);
                },
              ),
            ]),
            if (curEp != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  TvButton(
                    label: '${Store.progress(cur!) != null ? 'Fortsätt' : 'Spela'} ${epCode(curEp)}',
                    icon: Icons.play_arrow,
                    selected: true,
                    autofocus: true,
                    onTap: () => _play(curEp!),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text('Du är på säsong ${curEp.season}, avsnitt ${curEp.number}${curEp.title.isNotEmpty ? ' – ${curEp.title}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, color: Colors.white70))),
                ]),
              ),
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
                      child: TvButton(label: 'Säsong $s', selected: s == _season, onTap: () => setState(() => _season = s), autofocus: curEp == null && s == seasons.first),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: eps.length,
                  itemBuilder: (c, i) {
                    final e = eps[i];
                    final key = 'e:${e.id}';
                    final p = Store.progress(key);
                    final watched = Store.isWatched(key);
                    final isCur = key == cur;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Tv(
                        onTap: () => _play(e),
                        builder: (c, f) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: f ? Colors.white24 : (isCur ? kAccent.withAlpha(60) : kPanel),
                            borderRadius: BorderRadius.circular(9),
                            border: isCur ? Border.all(color: kAccent, width: 2) : null,
                          ),
                          child: Row(children: [
                            SizedBox(width: 56, child: Text('${e.number}', style: const TextStyle(fontSize: 20, color: Colors.white70))),
                            if (isCur) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.play_circle, color: kAccent, size: 22)),
                            Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, color: Colors.white))),
                            if (p != null && p.durSec > 0 && p.posSec > 10 && p.posSec < p.durSec * 0.95)
                              Text('Fortsätt ${fmtTime(p.posSec)}', style: const TextStyle(fontSize: 16, color: kAccent))
                            else if (watched)
                              const Row(children: [Icon(Icons.check_circle, color: Colors.white54, size: 20), SizedBox(width: 6), Text('Sett', style: TextStyle(fontSize: 16, color: Colors.white54))]),
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
