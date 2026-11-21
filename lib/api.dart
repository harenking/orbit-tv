import 'dart:convert';
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
  const Item(this.kind, this.id, this.name, this.poster, this.ext);
}

class Episode {
  final String id;
  final String title;
  final int season;
  final int number;
  final String ext;
  final String? image;
  const Episode(this.id, this.title, this.season, this.number, this.ext, this.image);
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

/// Klient för Xtream Codes (player_api.php).
class Xtream {
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
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Kastar fel om inloggningen inte stämmer.
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

  Future<List<Cat>> categories(Kind k) async {
    final j = await _get({'action': 'get_${_action(k)}_categories'});
    if (j is! List) return [];
    return [for (final c in j) Cat(_s(c['category_id']) ?? '', _s(c['category_name']) ?? 'Okänd')];
  }

  Future<List<Item>> items(Kind k, String catId) async {
    final act = switch (k) {
      Kind.movie => 'get_vod_streams',
      Kind.series => 'get_series',
      Kind.live => 'get_live_streams',
    };
    final j = await _get({'action': act, 'category_id': catId});
    if (j is! List) return [];
    return [
      for (final m in j)
        if (k == Kind.series)
          Item(k, _s(m['series_id']) ?? '', _s(m['name']) ?? '', _s(m['cover']), 'mkv')
        else
          Item(k, _s(m['stream_id']) ?? '', _s(m['name']) ?? '', _s(m['stream_icon']), _s(m['container_extension']) ?? (k == Kind.live ? 'm3u8' : 'mp4')),
    ];
  }

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
            info is Map ? _s(info['movie_image']) : null,
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

  String movieUrl(String id, String ext) => '$base/movie/${a.user}/${a.pass}/$id.$ext';
  String episodeUrl(String id, String ext) => '$base/series/${a.user}/${a.pass}/$id.$ext';
  String liveUrl(String id) => '$base/live/${a.user}/${a.pass}/$id.m3u8';
}
