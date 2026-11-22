import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Account {
  final String id;
  final String name;
  final String type; // xtream | m3u
  final String url;
  final String user;
  final String pass;
  const Account({required this.id, required this.name, required this.type, required this.url, this.user = '', this.pass = ''});

  bool get isM3u => type == 'm3u';

  static String makeId(String url, String user) => sha256.convert(utf8.encode('$url|$user|${DateTime.now().microsecondsSinceEpoch}')).toString().substring(0, 12);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type, 'url': url, 'user': user, 'pass': pass};

  factory Account.fromJson(Map<String, dynamic> j) {
    final url = j['url'] as String;
    final user = (j['user'] as String?) ?? '';
    final host = Uri.tryParse(url.contains('://') ? url : 'http://$url')?.host ?? url;
    return Account(
      id: (j['id'] as String?) ?? sha256.convert(utf8.encode('$url|$user')).toString().substring(0, 12),
      name: (j['name'] as String?) ?? (user.isEmpty ? host : '$user @ $host'),
      type: (j['type'] as String?) ?? 'xtream',
      url: url,
      user: user,
      pass: (j['pass'] as String?) ?? '',
    );
  }
}

/// En favorit (film, serie eller kanal) för ett visst konto.
class Fav {
  final String accId;
  final String kind; // movie | series | live
  final String id;
  final String name;
  final String? poster;
  final String ext;
  final bool locked;
  const Fav({required this.accId, required this.kind, required this.id, required this.name, this.poster, this.ext = '', this.locked = false});

  String get key => '$accId|$kind:$id';

  Map<String, dynamic> toJson() => {'acc': accId, 'kind': kind, 'id': id, 'name': name, 'poster': poster, 'ext': ext, 'locked': locked};
  factory Fav.fromJson(Map<String, dynamic> j) => Fav(
        accId: j['acc'] as String,
        kind: j['kind'] as String,
        id: j['id'] as String,
        name: j['name'] as String,
        poster: j['poster'] as String?,
        ext: (j['ext'] as String?) ?? '',
        locked: (j['locked'] as bool?) ?? false,
      );
}

/// En post i "fortsätt titta".
/// Vilket avsnitt en post gäller (för serier).
class EpMeta {
  final String seriesId;
  final String series;
  final String? poster; // seriens affisch
  final int season;
  final int number;
  final String title;
  const EpMeta({required this.seriesId, required this.series, this.poster, required this.season, required this.number, required this.title});

  String get short => 'S$season · Avsnitt $number';

  Map<String, dynamic> toJson() => {'sid': seriesId, 'series': series, 'poster': poster, 's': season, 'n': number, 't': title};
  static EpMeta? fromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      return EpMeta(
        seriesId: j['sid'] as String,
        series: j['series'] as String,
        poster: j['poster'] as String?,
        season: (j['s'] as num).toInt(),
        number: (j['n'] as num).toInt(),
        title: (j['t'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

class Progress {
  final String key;
  final String title;
  final String? poster;
  final String url;
  final int posSec;
  final int durSec;
  final int updated;
  final String kind; // movie | episode
  final bool locked;
  final EpMeta? ep;
  const Progress({
    required this.key,
    required this.title,
    required this.poster,
    required this.url,
    required this.posSec,
    required this.durSec,
    required this.updated,
    required this.kind,
    this.locked = false,
    this.ep,
  });

  Map<String, dynamic> toJson() => {
        if (ep != null) 'ep': ep!.toJson(),
        'key': key,
        'title': title,
        'poster': poster,
        'url': url,
        'pos': posSec,
        'dur': durSec,
        'updated': updated,
        'kind': kind,
        'locked': locked,
      };

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        key: j['key'] as String,
        title: j['title'] as String,
        poster: j['poster'] as String?,
        url: j['url'] as String,
        posSec: (j['pos'] as num).toInt(),
        durSec: (j['dur'] as num).toInt(),
        updated: (j['updated'] as num).toInt(),
        kind: (j['kind'] as String?) ?? 'movie',
        locked: (j['locked'] as bool?) ?? false,
        ep: EpMeta.fromJson(j['ep']),
      );
}

class Store {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static List<Account> get accounts {
    final s = _p.getString('accounts');
    if (s != null) {
      try {
        return [for (final j in jsonDecode(s) as List) Account.fromJson(j as Map<String, dynamic>)];
      } catch (_) {
        return [];
      }
    }
    // Äldre version: ett enda konto
    final old = _p.getString('account');
    if (old != null) {
      try {
        return [Account.fromJson(jsonDecode(old) as Map<String, dynamic>)];
      } catch (_) {}
    }
    return [];
  }

  static Future<void> _writeAccounts(List<Account> l) async {
    await _p.setString('accounts', jsonEncode([for (final a in l) a.toJson()]));
    await _p.remove('account');
  }

  /// Det konto som används just nu.
  static Account? get account {
    final l = accounts;
    if (l.isEmpty) return null;
    final id = _p.getString('activeAcc');
    return l.firstWhere((a) => a.id == id, orElse: () => l.first);
  }

  static Future<void> addAccount(Account a) async {
    final l = accounts..add(a);
    await _writeAccounts(l);
    await _p.setString('activeAcc', a.id);
  }

  static Future<void> setActive(String id) => _p.setString('activeAcc', id);

  static Future<void> removeAccount(String id) async {
    final l = accounts..removeWhere((a) => a.id == id);
    await _writeAccounts(l);
    if (_p.getString('activeAcc') == id) await _p.remove('activeAcc');
    final f = _favAll()..removeWhere((k, v) => v.accId == id);
    await _favWrite(f);
  }

  // ---------- Favoriter ----------
  static Map<String, Fav> _favAll() {
    final s = _p.getString('favs');
    if (s == null) return {};
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, Fav.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _favWrite(Map<String, Fav> m) => _p.setString('favs', jsonEncode(m.map((k, v) => MapEntry(k, v.toJson()))));

  static List<Fav> favs(String accId, {String? kind}) => _favAll().values.where((f) => f.accId == accId && (kind == null || f.kind == kind)).toList();
  static bool isFav(Fav f) => _favAll().containsKey(f.key);

  /// Returnerar true om den nu är favorit.
  static Future<bool> toggleFav(Fav f) async {
    final m = _favAll();
    final on = !m.containsKey(f.key);
    if (on) {
      m[f.key] = f;
    } else {
      m.remove(f.key);
    }
    await _favWrite(m);
    return on;
  }

  // ---------- Undertexter ----------
  static bool get autoSubs => _p.getBool('autoSubs') ?? false;
  static Future<void> setAutoSubs(bool v) => _p.setBool('autoSubs', v);
  static String get subLang => _p.getString('subLang') ?? 'sv';
  static Future<void> setSubLang(String v) => _p.setString('subLang', v);
  static int get subSize => _p.getInt('subSize') ?? 42;
  static Future<void> setSubSize(int v) => _p.setInt('subSize', v);
  static bool get subYellow => _p.getBool('subYellow') ?? false;
  static Future<void> setSubYellow(bool v) => _p.setBool('subYellow', v);
  static bool get subBg => _p.getBool('subBg') ?? true;
  static Future<void> setSubBg(bool v) => _p.setBool('subBg', v);
  static double get defaultSpeed => _p.getDouble('defaultSpeed') ?? 1.0;
  static Future<void> setDefaultSpeed(double v) => _p.setDouble('defaultSpeed', v);


  // ---------- Inställningar ----------
  static int get seekStep => _p.getInt('seekStep') ?? 10;
  static Future<void> setSeekStep(int v) => _p.setInt('seekStep', v);
  static bool get autoResume => _p.getBool('autoResume') ?? true;
  static Future<void> setAutoResume(bool v) => _p.setBool('autoResume', v);

  static Future<void> clearProgress() => _p.remove('progress');

  // ---------- Föräldralås ----------
  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool get hasPin => _p.getString('pin') != null;

  static Future<void> setPin(String pin) {
    final r = Random.secure();
    final salt = List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
    return _p.setString('pin', '$salt:${_hash(salt, pin)}');
  }

  static bool verifyPin(String pin) {
    final v = _p.getString('pin');
    if (v == null) return true;
    final i = v.indexOf(':');
    if (i < 0) return false;
    return _hash(v.substring(0, i), pin) == v.substring(i + 1);
  }

  static Future<void> removePin() => _p.remove('pin');

  static List<String> get lockedCats => _p.getStringList('lockedCats') ?? const [];
  static Future<void> setLockedCats(List<String> v) => _p.setStringList('lockedCats', v);
  static String get keywords => _p.getString('keywords') ?? 'adult,xxx,18+,erotik,porr';
  static Future<void> setKeywords(String v) => _p.setString('keywords', v);
  static int get unlockMinutes => _p.getInt('unlockMinutes') ?? 15;
  static Future<void> setUnlockMinutes(int v) => _p.setInt('unlockMinutes', v);

  static Map<String, Progress> _all() {
    final s = _p.getString('progress');
    if (s == null) return {};
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, Progress.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _write(Map<String, Progress> m) => _p.setString('progress', jsonEncode(m.map((k, v) => MapEntry(k, v.toJson()))));

  static Progress? progress(String key) => _all()[key];

  /// Senast tittade först. Färdigtittade (över 95 %) tas inte med.
  // ---------- Fellogg ----------
  static List<String> get errors => _p.getStringList('errors') ?? const [];
  static void logError(String e) {
    final l = [...errors, '${DateTime.now().toIso8601String().substring(0, 19)}  ${e.length > 300 ? e.substring(0, 300) : e}'];
    if (l.length > 20) l.removeRange(0, l.length - 20);
    _p.setStringList('errors', l);
  }

  static Future<void> clearErrors() => _p.remove('errors');

  // ---------- Sedda avsnitt/filmer ----------
  static List<String> _watched() => _p.getStringList('watched') ?? const [];
  static bool isWatched(String key) => _watched().contains(key);
  static Future<void> markWatched(String key) async {
    final l = [..._watched()]..remove(key);
    l.add(key);
    if (l.length > 3000) l.removeRange(0, l.length - 3000);
    await _p.setStringList('watched', l);
  }

  /// Senast spelade avsnitt (nyckel e:<id>) per serie.
  static String? lastEp(String seriesId) => _p.getString('lastEp:$seriesId');
  static Future<void> setLastEp(String seriesId, String key) => _p.setString('lastEp:$seriesId', key);

  /// Senaste påbörjade avsnitt i en serie (för att visa var man är).
  static Progress? lastInSeries(String seriesId) {
    final l = _all().values.where((p) => p.ep?.seriesId == seriesId).toList()..sort((a, b) => b.updated.compareTo(a.updated));
    return l.isEmpty ? null : l.first;
  }

  static List<Progress> continueList() {
    final l = _all().values.where((p) => p.durSec > 0 && p.posSec > 10 && p.posSec < p.durSec * 0.95).toList();
    l.sort((a, b) => b.updated.compareTo(a.updated));
    return l;
  }

  static Future<void> saveProgress(Progress p) async {
    final m = _all();
    m[p.key] = p;
    // Håll listan rimlig
    if (m.length > 300) {
      final old = m.values.toList()..sort((a, b) => a.updated.compareTo(b.updated));
      for (final o in old.take(m.length - 300)) {
        m.remove(o.key);
      }
    }
    await _write(m);
  }

  static Future<void> removeProgress(String key) async {
    final m = _all();
    m.remove(key);
    await _write(m);
  }
}
