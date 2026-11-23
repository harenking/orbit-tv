import 'package:flutter/material.dart';
import 'api.dart';
import 'diagnostics.dart';
import 'parental.dart';
import 'storage.dart';
import 'tv.dart';

const String kLegalShort =
    'Orbit IPTV är en mediaspelare. Den levererar, säljer eller förmedlar inget innehåll och innehåller inga kanaler eller spellistor. '
    'Du får bara ansluta tjänster och spellistor som du har laglig rätt att använda, till exempel en betald prenumeration hos en licensierad leverantör. '
    'Vi tar tydligt avstånd från piratkopiering och olaglig strömning av upphovsrättsskyddat material. '
    'Du ansvarar själv för att din användning följer gällande lagar och din leverantörs villkor.';

class SettingsPage extends StatefulWidget {
  final Source api;
  const SettingsPage({super.key, required this.api});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<String> _allCats = const [];
  bool _catsLoaded = false;
  final TextEditingController _q = TextEditingController();
  final TextEditingController _kw = TextEditingController(text: Store.keywords);
  String _filter = '';

  @override
  void dispose() {
    _q.dispose();
    _kw.dispose();
    super.dispose();
  }

  bool get _canEdit => !Store.hasPin || Guard.unlocked;
  final Future<List<ExitInfo>> _exits = Diagnostics.lastExits();

  Future<void> _loadCats() async {
    if (_catsLoaded) return;
    try {
      final r = await Future.wait([widget.api.categories(Kind.movie), widget.api.categories(Kind.series), widget.api.categories(Kind.live)]);
      final names = <String>{for (final l in r) for (final c in l) c.name}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (mounted) setState(() {
            _allCats = names;
            _catsLoaded = true;
          });
    } catch (_) {
      // Visas som tom lista; användaren kan försöka igen genom att byta flik
    }
  }

  Future<void> _createPin() async {
    final first = await Guard.askPin(context, title: 'Skapa PIN-kod', hint: '4–8 siffror');
    if (first == null || !mounted) return;
    final second = await Guard.askPin(context, title: 'Upprepa PIN-koden', check: (p) => p == first ? null : 'Koderna stämmer inte');
    if (second == null) return;
    await Store.setPin(first);
    Guard.lock();
    if (mounted) setState(() {});
  }

  Future<void> _changePin() async {
    final first = await Guard.askPin(context, title: 'Ny PIN-kod', hint: '4–8 siffror');
    if (first == null || !mounted) return;
    final second = await Guard.askPin(context, title: 'Upprepa PIN-koden', check: (p) => p == first ? null : 'Koderna stämmer inte');
    if (second == null) return;
    await Store.setPin(first);
    if (mounted) setState(() {});
  }

  Future<void> _removePin() async {
    final ok = await Guard.askPin(context, title: 'Ta bort PIN-kod', hint: 'Ange nuvarande PIN', check: (p) => Store.verifyPin(p) ? null : 'Fel PIN');
    if (ok == null) return;
    await Store.removePin();
    Guard.lock();
    if (mounted) setState(() {});
  }

  Future<void> _toggleCat(String name) async {
    final cur = [...Store.lockedCats];
    if (cur.contains(name)) {
      cur.remove(name);
    } else {
      cur.add(name);
    }
    await Store.setLockedCats(cur);
    if (mounted) setState(() {});
  }

  Widget _head(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, 24, 0, 8), child: Text(t, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)));

  Widget _row(String label, {String? hint, required Widget trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 19)),
              if (hint != null) Text(hint, style: const TextStyle(fontSize: 14, color: Colors.white60)),
            ]),
          ),
          trailing,
        ]),
      );

  Widget _choice<T>(List<(String, T)> opts, T current, Future<void> Function(T) onPick) => Wrap(spacing: 8, children: [
        for (final o in opts)
          TvButton(
            label: o.$1,
            selected: o.$2 == current,
            onTap: () async {
              await onPick(o.$2);
              if (mounted) setState(() {});
            },
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final acc = Store.account;
    final hasPin = Store.hasPin;
    final cur = Store.lockedCats;
    final nq = _filter.trim().toLowerCase();
    final shown = _allCats.where((c) => nq.isEmpty || c.toLowerCase().contains(nq)).toList()
      ..sort((a, b) => (cur.contains(b) ? 1 : 0) - (cur.contains(a) ? 1 : 0));

    return ListView(
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
      children: [
        _head('Konto'),
        _row('Aktivt konto', hint: acc?.name ?? '', trailing: const SizedBox.shrink()),
        const Text('Lägg till, byt eller ta bort konton och spellistor under fliken Konton.', style: TextStyle(color: Colors.white60, fontSize: 15)),

        _head('Uppspelning'),
        _row('Spolningssteg', hint: 'Vänster/höger på fjärrkontrollen. Håll in för tre gånger så långt.',
            trailing: _choice<int>(const [('10 s', 10), ('20 s', 20), ('30 s', 30), ('60 s', 60)], Store.seekStep, Store.setSeekStep)),
        _row('Återuppta automatiskt', hint: 'Starta där du slutade när du öppnar en titel.',
            trailing: _choice<bool>(const [('På', true), ('Av', false)], Store.autoResume, Store.setAutoResume)),
        _row('Fortsätt titta-historik', trailing: TvButton(label: 'Rensa', icon: Icons.delete_outline, onTap: () async {
          await Store.clearProgress();
          if (mounted) setState(() {});
        })),

        _row('Videoläge', hint: 'Hårdvara är stabilast på TV. Byt bara om en film visar svart bild eller hackar.',
            trailing: _choice<String>(const [('Hårdvara', 'hw'), ('Grafikkrets', 'gpu'), ('Mjukvara', 'sw')], Store.videoMode, Store.setVideoMode)),

        _row('Standardhastighet', trailing: _choice<double>(const [('0,75×', 0.75), ('1×', 1.0), ('1,25×', 1.25), ('1,5×', 1.5)], Store.defaultSpeed, Store.setDefaultSpeed)),

        _head('Undertexter'),
        _row('Välj automatiskt', hint: 'Slå på önskat språk ur filen när det finns. Du kan alltid byta i spelarens meny (▼).',
            trailing: _choice<bool>(const [('På', true), ('Av', false)], Store.autoSubs, Store.setAutoSubs)),
        _row('Språk', trailing: _choice<String>(const [('Svenska', 'sv'), ('Engelska', 'en'), ('Norska', 'no'), ('Danska', 'da'), ('Finska', 'fi')], Store.subLang, Store.setSubLang)),
        _row('Storlek', trailing: _choice<int>(const [('Liten', 32), ('Mellan', 42), ('Stor', 54), ('Extra stor', 68)], Store.subSize, Store.setSubSize)),
        _row('Färg', trailing: _choice<bool>(const [('Vit', false), ('Gul', true)], Store.subYellow, Store.setSubYellow)),
        _row('Mörk bakgrund', trailing: _choice<bool>(const [('På', true), ('Av', false)], Store.subBg, Store.setSubBg)),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
          child: Center(
            child: Text('Så här ser undertexten ut',
                style: TextStyle(fontSize: Store.subSize * 0.6, fontWeight: FontWeight.w600, color: Store.subYellow ? const Color(0xFFFFE94A) : Colors.white, backgroundColor: Store.subBg ? const Color(0xAA000000) : null)),
          ),
        ),

        _head('Föräldralås'),
        if (!hasPin)
          _row('PIN-kod', hint: 'Skapa en PIN (4–8 siffror) för att låsa kategorier. De samlas i mappen "${Guard.vaultName}" som kräver PIN.',
              trailing: TvButton(label: 'Skapa PIN', icon: Icons.lock_outline, onTap: _createPin))
        else ...[
          _row(Guard.unlocked ? 'Upplåst' : 'Låst',
              hint: Guard.unlocked ? (Store.unlockMinutes > 0 ? 'Låses automatiskt efter ${Store.unlockMinutes} min eller när appen stängs.' : 'Låses när appen stängs.') : 'Lås upp med PIN för att se och ändra reglerna.',
              trailing: Guard.unlocked
                  ? TvButton(label: 'Lås nu', icon: Icons.lock, onTap: () => setState(Guard.lock))
                  : TvButton(label: 'Lås upp', icon: Icons.lock_open, onTap: () async {
                      if (await Guard.ensure(context) && mounted) setState(() {});
                    })),
          if (_canEdit) ...[
            _row('PIN-kod', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TvButton(label: 'Byt PIN', onTap: _changePin),
              const SizedBox(width: 8),
              TvButton(label: 'Ta bort', onTap: _removePin),
            ])),
            _row('Lås upp i', trailing: _choice<int>(const [('5 min', 5), ('15 min', 15), ('1 tim', 60), ('Tills appen stängs', 0)], Store.unlockMinutes, Store.setUnlockMinutes)),
            const SizedBox(height: 8),
            TvField(controller: _kw, label: 'Nyckelord (kommaseparerade)', onChanged: (v) => Store.setKeywords(v)),
            _head('Låsta kategorier (${cur.length} valda)'),
            if (!_catsLoaded)
              Align(alignment: Alignment.centerLeft, child: TvButton(label: 'Visa kategorier', icon: Icons.list, onTap: _loadCats))
            else ...[
              TvField(controller: _q, label: 'Sök bland kategorier…', icon: Icons.search, onChanged: (v) => setState(() => _filter = v)),
              const SizedBox(height: 8),
              if (shown.isEmpty) const Text('Inga kategorier matchar.', style: TextStyle(color: Colors.white70)),
              for (final c in shown.take(60))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Tv(
                    onTap: () => _toggleCat(c),
                    builder: (ctx, f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: f ? Colors.white24 : kPanel, borderRadius: BorderRadius.circular(9)),
                      child: Row(children: [
                        Icon(cur.contains(c) ? Icons.lock : Icons.lock_open, size: 20, color: cur.contains(c) ? kAccent : Colors.white38),
                        const SizedBox(width: 12),
                        Expanded(child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18))),
                      ]),
                    ),
                  ),
                ),
              if (shown.length > 60) Text('Visar 60 av ${shown.length}. Sök för att hitta fler.', style: const TextStyle(color: Colors.white60)),
            ],
          ] else
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Reglerna, nyckelorden och de låsta kategorierna är dolda. Lås upp med PIN för att se och ändra dem.', style: TextStyle(color: Colors.white70, fontSize: 16))),
        ],

        _head('Senaste avslut (felsökning)'),
        FutureBuilder<List<ExitInfo>>(
          future: _exits,
          builder: (c, snap) {
            final l = snap.data ?? const <ExitInfo>[];
            if (snap.connectionState != ConnectionState.done) return const Text('Hämtar…', style: TextStyle(color: Colors.white60));
            if (l.isEmpty) return const Text('Inga avslut registrerade.', style: TextStyle(color: Colors.white60, fontSize: 15));
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in l)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${e.time.toString().substring(0, 16)}  ${e.label}${e.desc.isNotEmpty ? ' – ${e.desc}' : ''}  (minne ${(e.pssKb / 1024).round()} MB)',
                    style: TextStyle(fontSize: 14, color: e.isProblem ? Colors.orangeAccent : Colors.white60),
                  ),
                ),
              // Var den senaste inbyggda kraschen skedde (bibliotek/funktion), för felsökning
              if (l.any((e) => e.reason == 5 && (e.trace ?? '').trim().isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Detaljer om senaste kraschen:\n${l.firstWhere((e) => e.reason == 5 && (e.trace ?? '').trim().isNotEmpty).trace!.split('\n').take(10).join('\n')}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
            ]);
          },
        ),
        if (Store.errors.isNotEmpty) ...[
          _head('Senaste fel (för felsökning)'),
          for (final e in Store.errors.reversed.take(6)) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(e, style: const TextStyle(fontSize: 13, color: Colors.white60))),
          Align(alignment: Alignment.centerLeft, child: TvButton(label: 'Rensa fellogg', icon: Icons.delete_outline, onTap: () async {
            await Store.clearErrors();
            if (mounted) setState(() {});
          })),
        ],

        _head('Om Orbit IPTV'),
        const Text('Version 0.6', style: TextStyle(fontSize: 18, color: Colors.white70)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Använd bara lagliga tjänster', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(kLegalShort, style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.5)),
          ]),
        ),
      ],
    );
  }
}
