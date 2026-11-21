import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Account {
  final String url;
  final String user;
  final String pass;
  const Account(this.url, this.user, this.pass);

  Map<String, dynamic> toJson() => {'url': url, 'user': user, 'pass': pass};
  factory Account.fromJson(Map<String, dynamic> j) => Account(j['url'] as String, j['user'] as String, j['pass'] as String);
}

/// En post i "fortsätt titta".
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
  });

  Map<String, dynamic> toJson() => {
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
      );
}

class Store {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static Account? get account {
    final s = _p.getString('account');
    if (s == null) return null;
    try {
      return Account.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAccount(Account a) => _p.setString('account', jsonEncode(a.toJson()));
  static Future<void> clearAccount() => _p.remove('account');


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
