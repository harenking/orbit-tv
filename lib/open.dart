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
