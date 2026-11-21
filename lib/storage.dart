import 'dart:convert';
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
  const Progress({
    required this.key,
    required this.title,
    required this.poster,
    required this.url,
    required this.posSec,
    required this.durSec,
    required this.updated,
    required this.kind,
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
