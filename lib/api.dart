import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'storage.dart';

enum Kind { movie, series, live }

class Cat {
  final String id;
  final String name;
  const Cat(this.id, this.name);
}

class Item {
  final Kind kind;
  final String id;
  final String name;
  final String? poster;
  final String ext;
  final String catId;
  final int added;
  const Item(this.kind, this.id, this.name, this.poster, this.ext, {this.catId = '', this.added = 0});
}

class Episode {
  final String id;
  final String title;
  final int season;
  final int number;
  final String ext;
  final String? image;
  final String plot;
  final String duration; // t.ex. "00:42:10"
  const Episode(this.id, this.title, this.season, this.number, this.ext, this.image, {this.plot = '', this.duration = ''});
}

class SeriesInfo {
  final Map<int, List<Episode>> seasons;
  const SeriesInfo(this.seasons);
}

String? _s(dynamic v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

int _i(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

dynamic _decode(String s) => jsonDecode(s);

/// Gemensamt gränssnitt för Xtream-konton och M3U-spellistor.
abstract class Source {
  Account get a;
  Future<void> login();
  Future<List<Cat>> categories(Kind k);
  Future<List<Item>> items(Kind k, String catId);
  Future<SeriesInfo> series(String id);
  Future<List<Item>> recent(Kind k);
  @override
  String movieUrl(String id, String ext);
  @override
  String episodeUrl(String id, String ext);
  @override
  String liveUrl(String id);

  static Source of(Account a) => a.isM3u ? M3uSource(a) : Xtream(a);
}

/// Klient för Xtream Codes (player_api.php).
class Xtream implements Source {
  @override
  final Account a;
  Xtream(this.a);

  String get base {
    var u = a.url.trim().replaceAll(RegExp(r'/+$'), '');
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    return u;
  }

  Future<dynamic> _get(Map<String, String> q) async {
    final uri = Uri.parse('$base/player_api.php').replace(queryParameters: {'username': a.user, 'password': a.pass, ...q});
    final r = await http.get(uri, headers: {'User-Agent': 'OrbitTV/0.1'}).timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) throw Exception('Servern svarade ${r.statusCode}');
    final body = utf8.decode(r.bodyBytes);
    // Stora svar tolkas i en egen tråd så att bilden inte hackar
    return body.length > 200000 ? await compute(_decode, body) : jsonDecode(body);
  }

  /// Kastar fel om inloggningen inte stämmer.
  @override
  Future<void> login() async {
    final j = await _get({});
    if (j is! Map || j['user_info'] is! Map) throw Exception('Fel adress eller svar från servern');
    final ui = j['user_info'] as Map;
    if (_i(ui['auth']) != 1) throw Exception('Fel användarnamn eller lösenord');
    final st = _s(ui['status']);
    if (st != null && st.toLowerCase() != 'active') throw Exception('Kontot är inte aktivt ($st)');
  }

  String _action(Kind k) => switch (k) {
        Kind.movie => 'vod',
        Kind.series => 'series',
        Kind.live => 'live',
      };

  @override
  Future<List<Cat>> categories(Kind k) async {
    final j = await _get({'action': 'get_${_action(k)}_categories'});
    if (j is! List) return [];
    return [for (final c in j) Cat(_s(c['category_id']) ?? '', _s(c['category_name']) ?? 'Okänd')];
  }

  @override
  Future<List<Item>> items(Kind k, String catId) async {
    final act = switch (k) {
      Kind.movie => 'get_vod_streams',
      Kind.series => 'get_series',
      Kind.live => 'get_live_streams',
    };
    final j = await _get({'action': act, if (catId.isNotEmpty) 'category_id': catId});
    if (j is! List) return [];
    return [
      for (final m in j)
        if (k == Kind.series)
          Item(k, _s(m['series_id']) ?? '', _s(m['name']) ?? '', _s(m['cover']), 'mkv', catId: _s(m['category_id']) ?? catId, added: _i(m['last_modified']))
        else
          Item(k, _s(m['stream_id']) ?? '', _s(m['name']) ?? '', _s(m['stream_icon']), _s(m['container_extension']) ?? (k == Kind.live ? 'm3u8' : 'mp4'), catId: _s(m['category_id']) ?? catId, added: _i(m['added'])),
    ];
  }

  /// Senast tillagda, nyast först (hela listan hämtas en gång och sorteras).
  @override
  Future<List<Item>> recent(Kind k) async {
    final all = await items(k, '');
    all.sort((x, y) => y.added.compareTo(x.added));
    return all.take(300).toList();
  }

  @override
  Future<SeriesInfo> series(String id) async {
    final j = await _get({'action': 'get_series_info', 'series_id': id});
    final out = <int, List<Episode>>{};
    final eps = (j is Map) ? j['episodes'] : null;
    void add(int season, dynamic e) {
      if (e is! Map) return;
      final info = e['info'];
      out.putIfAbsent(season, () => []).add(Episode(
            _s(e['id']) ?? '',
            _s(e['title']) ?? 'Avsnitt ${_i(e['episode_num'])}',
            season,
            _i(e['episode_num']),
            _s(e['container_extension']) ?? 'mkv',
            info is Map ? (_s(info['movie_image']) ?? _s(info['cover_big'])) : null,
            plot: info is Map ? (_s(info['plot']) ?? _s(info['description']) ?? '') : '',
            duration: info is Map ? (_s(info['duration']) ?? '') : '',
          ));
    }

    if (eps is Map) {
      eps.forEach((k, v) {
        if (v is List) {
          for (final e in v) {
            add(_i(k), e);
          }
        }
      });
    } else if (eps is List) {
      for (final v in eps) {
        if (v is List) {
          for (final e in v) {
            add(_i(e is Map ? e['season'] : 1), e);
          }
        }
      }
    }
    for (final l in out.values) {
      l.sort((x, y) => x.number.compareTo(y.number));
    }
    return SeriesInfo(out);
  }

  @override
  String movieUrl(String id, String ext) => '$base/movie/${a.user}/${a.pass}/$id.$ext';
  @override
  String episodeUrl(String id, String ext) => '$base/series/${a.user}/${a.pass}/$id.$ext';
  @override
  String liveUrl(String id) => '$base/live/${a.user}/${a.pass}/$id.m3u8';
}


/// Läser en M3U-lista (körs i egen tråd). Returnerar [namn, logga, grupp, url].
List<List<String>> parseM3u(String body) {
  final out = <List<String>>[];
  String? name, logo, group;
  final attr = RegExp(r'([\w-]+)="([^"]*)"');
  for (final raw in const LineSplitter().convert(body)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final comma = line.lastIndexOf(',');
      name = comma >= 0 ? line.substring(comma + 1).trim() : '';
      logo = null;
      group = null;
      for (final m in attr.allMatches(line)) {
        final k = m.group(1)!.toLowerCase();
        if (k == 'tvg-logo') logo = m.group(2);
        if (k == 'group-title') group = m.group(2);
      }
    } else if (line.startsWith('#')) {
      continue;
    } else if (name != null) {
      out.add([name.isEmpty ? line : name, logo ?? '', (group ?? '').trim().isEmpty ? 'Övrigt' : group!.trim(), line]);
      name = null;
    }
  }
  return out;
}

/// M3U-spellista: filmer och kanaler (serier i listan visas som filmer).
class M3uSource implements Source {
  @override
  final Account a;
  M3uSource(this.a);

  static final Map<String, List<List<String>>> _cache = {};

  Future<List<List<String>>> _load() async {
    final hit = _cache[a.id];
    if (hit != null) return hit;
    var u = a.url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    final r = await http.get(Uri.parse(u), headers: {'User-Agent': 'OrbitTV/0.1'}).timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw Exception('Servern svarade ${r.statusCode}');
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (!body.contains('#EXTINF')) throw Exception('Det här ser inte ut som en M3U-lista');
    final l = await compute(parseM3u, body);
    _cache[a.id] = l;
    return l;
  }

  static void forget(String accId) => _cache.remove(accId);

  bool _isMovie(List<String> e) {
    final u = e[3].toLowerCase();
    return u.contains('/movie/') || u.contains('/series/') || RegExp(r'\.(mp4|mkv|avi|mov)(\?|$)').hasMatch(u);
  }

  bool _fits(Kind k, List<String> e) => k == Kind.movie ? _isMovie(e) : (k == Kind.live && !_isMovie(e));

  @override
  Future<void> login() async {
    final l = await _load();
    if (l.isEmpty) throw Exception('Listan är tom');
  }

  @override
  Future<List<Cat>> categories(Kind k) async {
    if (k == Kind.series) return [];
    final l = await _load();
    final seen = <String>{};
    return [for (final e in l) if (_fits(k, e) && seen.add(e[2])) Cat(e[2], e[2])];
  }

  @override
  Future<List<Item>> items(Kind k, String catId) async {
    if (k == Kind.series) return [];
    final l = await _load();
    return [
      for (final e in l)
        if (_fits(k, e) && (catId.isEmpty || e[2] == catId)) Item(k, e[3], e[0], e[1].isEmpty ? null : e[1], '', catId: e[2]),
    ];
  }

  @override
  Future<List<Item>> recent(Kind k) async {
    final all = await items(k, '');
    return all.reversed.take(300).toList();
  }

  @override
  Future<SeriesInfo> series(String id) async => const SeriesInfo({});
  @override
  String movieUrl(String id, String ext) => id;
  @override
  String episodeUrl(String id, String ext) => id;
  @override
  String liveUrl(String id) => id;
}
