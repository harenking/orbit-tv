import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Lokal "strömväxel" mellan spelaren och IPTV-leverantören (samma idé som i Nova).
/// Många leverantörer svarar 502/403/429 om spelaren öppnar flera anslutningar samtidigt eller
/// har fel User-Agent. Här gäller i stället:
///  1. EN uppströmsanslutning åt gången – den gamla stängs innan en ny öppnas.
///  2. Nekas anslutningen (401/403/429/458/5xx) väntas en stund och det prövas igen (och med annan User-Agent).
///  3. Servrar som ignorerar spolning (svarar 200 på Range) emuleras: vi hoppar över bytes åt spelaren.
///  4. User-Agent VLC först, därefter en webbläsare.
class StreamProxy {
  static const _vlc = 'VLC/3.0.20 LibVLC/3.0.20';
  static const _browser = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  static const _maxAttempts = 7;
  static const _busy = {401, 403, 429, 458, 500, 502, 503, 504, 509};

  static HttpServer? _server;
  static final Map<String, _Session> _sessions = {};
  static final _rnd = Random();

  static Future<void> _start() async {
    if (_server != null) return;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen((req) {
      _handle(req).catchError((Object _) {
        try {
          req.response.close();
        } catch (_) {}
      });
    });
  }

  /// Registrerar en ström och returnerar lokal adress som spelaren ska använda.
  static Future<String> open(String url, {String ext = 'mp4'}) async {
    await _start();
    final id = List.generate(10, (_) => _rnd.nextInt(16).toRadixString(16)).join();
    _sessions[id] = _Session(url);
    final safe = RegExp(r'^[a-z0-9]{2,5}$', caseSensitive: false).hasMatch(ext) ? ext : 'mp4';
    return 'http://127.0.0.1:${_server!.port}/s/$id/video.$safe';
  }

  static Future<void> close(String localUrl) async {
    final m = RegExp(r'/s/([0-9a-f]+)/').firstMatch(localUrl);
    if (m == null) return;
    final s = _sessions.remove(m.group(1));
    await s?.closeUpstream();
  }

  static Future<void> _handle(HttpRequest req) async {
    final m = RegExp(r'^/s/([0-9a-f]+)/').firstMatch(req.uri.path);
    final s = m == null ? null : _sessions[m.group(1)];
    if (s == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final gen = ++s.gen;
    final isHead = req.method == 'HEAD';
    var start = 0;
    int? end;
    var hasRange = false;
    final rh = req.headers.value('range');
    if (rh != null) {
      final r = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rh);
      if (r != null) {
        hasRange = true;
        start = int.tryParse(r.group(1) ?? '') ?? 0;
        end = int.tryParse(r.group(2) ?? '');
      }
    }
    var disconnected = false;
    // Hämtar ur anslutningen när spelaren avbryter (t.ex. vid spolning)
    req.response.done.catchError((Object _) {}).whenComplete(() {
      disconnected = true;
      if (s.gen == gen) s.closeUpstream();
    });

    final reqRange = isHead ? 'bytes=0-0' : (hasRange ? 'bytes=$start-${end ?? ''}' : null);
    final up = await s.openWithRetry(reqRange, () => disconnected || s.gen != gen);
    if (up == null) {
      if (!disconnected) {
        try {
          req.response.statusCode = 502;
          await req.response.close();
        } catch (_) {}
      }
      return;
    }
    if (disconnected || s.gen != gen) {
      await s.closeUpstream();
      return;
    }
    final res = req.response;
    final code = up.statusCode;
    final type = up.headers.value('content-type') ?? 'video/x-matroska';
    int? total;
    var skip = 0;
    if (code == 206) {
      final cr = RegExp(r'/(\d+)\s*$').firstMatch(up.headers.value('content-range') ?? '');
      total = int.tryParse(cr?.group(1) ?? '');
    } else {
      total = up.contentLength >= 0 ? up.contentLength : null;
      if (hasRange && start > 0) skip = start; // servern ignorerade Range: hoppa över bytes själva
    }
    res.headers.set('accept-ranges', 'bytes');
    res.headers.set('content-type', type);
    if (isHead) {
      res.statusCode = 200;
      if (total != null) res.headers.set('content-length', total.toString());
      await s.closeUpstream();
      await res.close();
      return;
    }
    if (code == 206 || (hasRange && total != null)) {
      final last = min(end ?? (total ?? 0) - 1, (total ?? 1 << 40) - 1);
      res.statusCode = 206;
      if (total != null) {
        res.headers.set('content-range', 'bytes $start-$last/$total');
        res.headers.set('content-length', (last - start + 1).toString());
      }
    } else {
      res.statusCode = 200;
      if (total != null) res.headers.set('content-length', total.toString());
    }
    var remaining = (code != 206 && hasRange && total != null) ? (min(end ?? total - 1, total - 1) - start + 1) : -1;
    try {
      var toSkip = skip;
      await for (final chunk in up) {
        if (disconnected || s.gen != gen) break;
        var data = chunk;
        if (toSkip > 0) {
          if (data.length <= toSkip) {
            toSkip -= data.length;
            continue;
          }
          data = data.sublist(toSkip);
          toSkip = 0;
        }
        if (remaining >= 0) {
          if (data.length >= remaining) {
            res.add(data.sublist(0, remaining));
            remaining = 0;
            break;
          }
          remaining -= data.length;
        }
        res.add(data);
        // Vänta tills spelaren hunnit ta emot, så att minnet inte växer
        await res.flush();
      }
    } catch (_) {
      // Anslutningen bröts – spelaren öppnar en ny vid behov
    }
    if (s.gen == gen) await s.closeUpstream();
    try {
      await res.close();
    } catch (_) {}
  }
}

class _Session {
  final String url;
  final List<String> uas = [StreamProxy._vlc, StreamProxy._browser];
  int uaIdx = 0;
  String? resolved;
  DateTime? resolvedAt;
  int gen = 0;
  HttpClient? _client;

  _Session(this.url);

  Future<void> closeUpstream() async {
    final c = _client;
    _client = null;
    if (c != null) {
      try {
        c.close(force: true);
      } catch (_) {}
      // Leverantörer med få tillåtna anslutningar behöver en stund på sig att släppa den gamla
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<HttpClientResponse?> openWithRetry(String? range, bool Function() cancelled) async {
    for (var attempt = 0; attempt < StreamProxy._maxAttempts; attempt++) {
      if (cancelled()) return null;
      await closeUpstream();
      try {
        final r = await _openOnce(range);
        final code = r.statusCode;
        if (code >= 200 && code < 300) return r;
        await r.drain<void>().catchError((Object _) {});
        await closeUpstream();
        if (code == 401 || code == 403) uaIdx = (uaIdx + 1) % uas.length;
        if (!StreamProxy._busy.contains(code) && code < 500) return null; // t.ex. 404: ge upp
      } catch (_) {
        await closeUpstream();
      }
      await Future.delayed(Duration(milliseconds: min(1000 * (attempt + 1), 5000)));
    }
    return null;
  }

  Future<HttpClientResponse> _openOnce(String? range) async {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 1);
    _client = client;
    var target = (resolved != null && DateTime.now().difference(resolvedAt!) < const Duration(minutes: 5)) ? resolved! : url;
    for (var hop = 0; hop < 6; hop++) {
      final rq = await client.getUrl(Uri.parse(target));
      rq.followRedirects = false;
      rq.persistentConnection = false;
      rq.headers.set('user-agent', uas[uaIdx]);
      rq.headers.set('accept', '*/*');
      if (range != null) rq.headers.set('range', range);
      final rs = await rq.close().timeout(const Duration(seconds: 25));
      if ([301, 302, 303, 307, 308].contains(rs.statusCode) && rs.headers.value('location') != null) {
        await rs.drain<void>().catchError((Object _) {});
        target = Uri.parse(target).resolve(rs.headers.value('location')!).toString();
        resolved = target;
        resolvedAt = DateTime.now();
        continue;
      }
      return rs;
    }
    throw Exception('För många omdirigeringar');
  }
}
