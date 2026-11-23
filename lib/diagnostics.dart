import 'package:flutter/services.dart';

/// Androids egen förklaring till varför appen stängdes senast (Android 11+).
class ExitInfo {
  final int reason;
  final int status;
  final String desc;
  final DateTime time;
  final int pssKb;
  final int rssKb;
  final String? trace;
  const ExitInfo(this.reason, this.status, this.desc, this.time, this.pssKb, this.rssKb, this.trace);

  /// Avslut som räknas som problem (inte att användaren själv stängde eller uppdaterade appen).
  bool get isProblem => const {2, 3, 4, 5, 6, 7, 9}.contains(reason) && !(reason == 2 && status != 9);

  String get label {
    switch (reason) {
      case 1:
        return 'Appen stängde sig själv';
      case 2:
        return status == 9 ? 'Stoppad av systemet (signal 9 – oftast slut på minne)' : 'Stoppad av signal $status';
      case 3:
        return 'Slut på minne';
      case 4:
        return 'Krasch (Java/Kotlin)';
      case 5:
        return 'Krasch i inbyggd kod (t.ex. videospelaren)';
      case 6:
        return 'Appen svarade inte (ANR)';
      case 7:
        return 'Kunde inte starta';
      case 9:
        return 'Använde för mycket resurser';
      case 10:
        return 'Stängd av användaren';
      case 11:
        return 'Tvångsstoppad av användaren';
      case 16:
        return 'Uppdaterad';
      default:
        return 'Annat (kod $reason)';
    }
  }
}

class Diagnostics {
  static const _ch = MethodChannel('orbit/exit');

  static Future<List<ExitInfo>> lastExits() async {
    try {
      final l = await _ch.invokeListMethod<Map<Object?, Object?>>('lastExits') ?? const [];
      return [
        for (final m in l)
          ExitInfo(
            (m['reason'] as num?)?.toInt() ?? 0,
            (m['status'] as num?)?.toInt() ?? 0,
            (m['desc'] as String?) ?? '',
            DateTime.fromMillisecondsSinceEpoch((m['time'] as num?)?.toInt() ?? 0),
            (m['pss'] as num?)?.toInt() ?? 0,
            (m['rss'] as num?)?.toInt() ?? 0,
            m['trace'] as String?,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
