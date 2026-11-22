import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'accounts_page.dart';
import 'api.dart';
import 'home.dart';
import 'browse.dart';
import 'parental.dart';
import 'open.dart';
import 'settings_page.dart';
import 'storage.dart';
import 'tv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.init();
  // Begränsa bildcachen – TV-boxar har lite minne och Android stänger appen när det tar slut
  PaintingBinding.instance.imageCache
    ..maximumSize = 150
    ..maximumSizeBytes = 40 * 1024 * 1024;
  // Oväntade fel loggas och visas i Inställningar i stället för att krascha appen
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    Store.logError(d.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (e, st) {
    Store.logError(e.toString());
    return true;
  };
  runApp(const OrbitApp());
}

class OrbitApp extends StatelessWidget {
  const OrbitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbit IPTV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kAccent),
        useMaterial3: true,
      ),
      home: Store.account == null ? const LoginPage() : HomePage(api: Source.of(Store.account!)),
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 560,
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
            const Text('Orbit IPTV', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Använd bara lagliga tjänster. Orbit är en spelare och levererar inget innehåll.',
              style: TextStyle(fontSize: 16, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AddAccountForm(
              autofocus: true,
              onAdded: (acc) async {
                await Store.addAccount(acc);
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomePage(api: Source.of(acc))));
              },
            ),
          ]),
        ),
      ),
    );
  }
}

enum Section { home, cont, movies, series, live, favs, accounts, settings }

class HomePage extends StatefulWidget {
  final Source api;
  const HomePage({super.key, required this.api});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Section _tab = Section.home;
  final FocusNode _homeBtn = FocusNode();
  DateTime? _lastBack;

  @override
  void dispose() {
    _homeBtn.dispose();
    super.dispose();
  }

  /// Tillbaka på fjärrkontrollen: först till Hem, sedan krävs två tryck för att stänga appen.
  void _onBack() {
    if (_tab != Section.home) {
      setState(() => _tab = Section.home);
      WidgetsBinding.instance.addPostFrameCallback((_) => _homeBtn.requestFocus());
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    _homeBtn.requestFocus();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(duration: Duration(seconds: 2), content: Text('Tryck Tillbaka igen för att stänga Orbit', style: TextStyle(fontSize: 18))));
  }

  /// Byter aktivt konto och bygger om hela appen för det.
  Future<void> _use(Account a) async {
    await Store.setActive(a.id);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomePage(api: Source.of(a))));
  }

  /// Kontolistan ändrades (borttagning): byt till ett kvar, eller visa inloggning.
  void _accountsChanged() {
    final a = Store.account;
    if (a == null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
    } else if (a.id != widget.api.a.id) {
      _use(a);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_tab) {
      case Section.home:
        body = HomeTab(key: ValueKey('h${widget.api.a.id}'), api: widget.api);
      case Section.favs:
        body = FavoritesTab(key: const ValueKey('f'), api: widget.api);
      case Section.accounts:
        body = AccountsPage(api: widget.api, onUse: _use, onChanged: _accountsChanged);
      case Section.cont:
        body = ContinuePage(api: widget.api, onChanged: () => setState(() {}));
      case Section.movies:
        body = BrowsePage(key: const ValueKey('m'), api: widget.api, kind: Kind.movie);
      case Section.series:
        body = BrowsePage(key: const ValueKey('s'), api: widget.api, kind: Kind.series);
      case Section.live:
        body = BrowsePage(key: const ValueKey('l'), api: widget.api, kind: Kind.live);
      case Section.settings:
        body = SettingsPage(api: widget.api);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                const Icon(Icons.public, color: kAccent, size: 32),
                const SizedBox(width: 10),
                const Text('Orbit', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(width: 24),
                TvButton(label: 'Hem', icon: Icons.home, selected: _tab == Section.home, autofocus: true, focusNode: _homeBtn, onTap: () => setState(() => _tab = Section.home)),
                const SizedBox(width: 8),
                TvButton(label: 'Fortsätt titta', selected: _tab == Section.cont, onTap: () => setState(() => _tab = Section.cont)),
                const SizedBox(width: 8),
                TvButton(label: 'Filmer', selected: _tab == Section.movies, onTap: () => setState(() => _tab = Section.movies)),
                const SizedBox(width: 8),
                TvButton(label: 'Serier', selected: _tab == Section.series, onTap: () => setState(() => _tab = Section.series)),
                const SizedBox(width: 8),
                TvButton(label: 'Live', selected: _tab == Section.live, onTap: () => setState(() => _tab = Section.live)),
                const SizedBox(width: 8),
                TvButton(label: 'Favoriter', icon: Icons.favorite, selected: _tab == Section.favs, onTap: () => setState(() => _tab = Section.favs)),
                const SizedBox(width: 8),
                TvButton(label: 'Konton', icon: Icons.people, selected: _tab == Section.accounts, onTap: () => setState(() => _tab = Section.accounts)),
                const SizedBox(width: 8),
                TvButton(label: 'Inställningar', icon: Icons.settings, selected: _tab == Section.settings, onTap: () => setState(() => _tab = Section.settings)),
              ]),
            ),
          ),
          Expanded(child: body),
        ]),
      ),
    ));
  }
}

class ContinuePage extends StatefulWidget {
  final Source api;
  final VoidCallback onChanged;
  const ContinuePage({super.key, required this.api, required this.onChanged});

  @override
  State<ContinuePage> createState() => _ContinuePageState();
}

class _ContinuePageState extends State<ContinuePage> {
  @override
  Widget build(BuildContext context) {
    final list = Store.continueList();
    if (list.isEmpty) {
      return const Center(child: Text('Inget att fortsätta på än.\nVälj en film eller serie.', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, color: Colors.white70)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 280, childAspectRatio: 1.35, crossAxisSpacing: 16, mainAxisSpacing: 16),
      itemCount: list.length,
      itemBuilder: (c, i) {
        final p = list[i];
        final hide = p.locked && Guard.active && !Guard.unlocked;
        return Tv(
          onTap: () async {
            if (hide && !await Guard.ensure(context)) return;
            if (!context.mounted) return;
            await openProgress(context, widget.api, p);
            if (mounted) setState(() {});
          },
          builder: (c, f) => ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              color: kPanel,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Stack(fit: StackFit.expand, children: [
                  posterImage(hide ? null : (p.ep?.poster ?? p.poster)),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(value: (p.posSec / p.durSec).clamp(0.0, 1.0), minHeight: 6, color: kAccent, backgroundColor: Colors.black54),
                  ),
                ])),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(hide ? Guard.mask(progressLabels(p).$1) : progressLabels(p).$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
                    Text('${p.ep != null && !hide ? '${p.ep!.short} · ' : ''}${fmtTime(p.posSec)} av ${fmtTime(p.durSec)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kAccent)),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
