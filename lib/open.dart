import 'package:flutter/material.dart';
import 'api.dart';
import 'player_page.dart';
import 'series_page.dart';
import 'storage.dart';

Kind kindOf(String s) => Kind.values.firstWhere((k) => k.name == s, orElse: () => Kind.movie);

Fav favOf(Source api, Item it, {bool locked = false}) =>
    Fav(accId: api.a.id, kind: it.kind.name, id: it.id, name: it.name, poster: it.poster, ext: it.ext, locked: locked);

Item itemOf(Fav f) => Item(kindOf(f.kind), f.id, f.name, f.poster, f.ext);

/// Öppnar en film, serie eller kanal. Returnerar när användaren kommer tillbaka.
Future<void> openItem(BuildContext context, Source api, Item it, {bool locked = false}) {
  final nav = Navigator.of(context);
  final fav = favOf(api, it, locked: locked);
  switch (it.kind) {
    case Kind.series:
      return nav.push(MaterialPageRoute(builder: (_) => SeriesPage(api: api, item: it, locked: locked)));
    case Kind.movie:
      return nav.push(MaterialPageRoute(
          builder: (_) => PlayerPage(url: api.movieUrl(it.id, it.ext), title: it.name, key2: 'm:${it.id}', poster: it.poster, kind: 'movie', locked: locked, fav: fav)));
    case Kind.live:
      return nav.push(MaterialPageRoute(builder: (_) => PlayerPage(url: api.liveUrl(it.id), title: it.name, key2: 'l:${it.id}', poster: it.poster, live: true, fav: fav)));
  }
}

/// Alla avsnitt i ordning (säsong, avsnitt).
List<Episode> flatEpisodes(SeriesInfo info) {
  final ks = info.seasons.keys.toList()..sort();
  return [
    for (final k in ks) ...([...info.seasons[k]!]..sort((a, b) => a.number.compareTo(b.number))),
  ];
}

String epCode(Episode e) => 'S${e.season} E${e.number}';

/// Spelare för avsnitt [i] som vet vilket avsnitt som kommer härnäst.
PlayerPage episodePlayer(Source api, Item series, List<Episode> all, int i, {bool locked = false}) {
  final e = all[i];
  final meta = EpMeta(seriesId: series.id, series: series.name, poster: series.poster, season: e.season, number: e.number, title: e.title);
  final hasNext = i + 1 < all.length;
  final n = hasNext ? all[i + 1] : null;
  return PlayerPage(
    url: api.episodeUrl(e.id, e.ext),
    title: '${series.name} · ${epCode(e)}${e.title.isNotEmpty && !e.title.contains(series.name) ? ' · ${e.title}' : ''}',
    key2: 'e:${e.id}',
    poster: e.image ?? series.poster,
    kind: 'episode',
    locked: locked,
    ep: meta,
    next: n == null ? null : () => episodePlayer(api, series, all, i + 1, locked: locked),
    nextLabel: n == null ? null : '${epCode(n)}${n.title.isNotEmpty ? ' · ${n.title}' : ''}',
  );
}

/// Öppnar en post från "Fortsätt titta". För avsnitt hämtas serien så att
/// "Spela nästa avsnitt" fungerar även härifrån.
Future<void> openProgress(BuildContext context, Source api, Progress p) async {
  final nav = Navigator.of(context);
  final ep = p.ep;
  if (p.kind == 'episode' && ep != null && ep.seriesId.isNotEmpty) {
    try {
      final info = await api.series(ep.seriesId).timeout(const Duration(seconds: 15));
      final all = flatEpisodes(info);
      final i = all.indexWhere((e) => 'e:${e.id}' == p.key);
      if (i >= 0) {
        await nav.push(MaterialPageRoute(builder: (_) => episodePlayer(api, Item(Kind.series, ep.seriesId, ep.series, ep.poster, ''), all, i, locked: p.locked)));
        return;
      }
    } catch (_) {
      // Spela utan "nästa avsnitt" om serien inte gick att hämta
    }
  }
  await nav.push(MaterialPageRoute(builder: (_) => PlayerPage(url: p.url, title: p.title, key2: p.key, poster: p.poster, kind: p.kind, locked: p.locked, ep: p.ep)));
}

/// Rubrik + undertext för ett kort i "Fortsätt titta".
(String, String) progressLabels(Progress p) {
  final ep = p.ep;
  if (ep != null) return (ep.series, '${ep.short}${ep.title.isNotEmpty && ep.title != ep.series ? ' · ${ep.title}' : ''}');
  return (p.title, '');
}
