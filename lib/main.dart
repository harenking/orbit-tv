import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'api.dart';
import 'browse.dart';
import 'player_page.dart';
import 'storage.dart';
import 'tv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.init();
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
      home: Store.account == null ? const LoginPage() : HomePage(api: Xtream(Store.account!)),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _agreed = false;

  Future<void> _go() async {
    if (_url.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Fyll i alla fält');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final acc = Account(_url.text.trim(), _user.text.trim(), _pass.text);
    try {
      await Xtream(acc).login();
      await Store.saveAccount(acc);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomePage(api: Xtream(acc))));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

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
            TvField(autofocus: true, controller: _url, label: 'Serveradress (t.ex. http://server.se:8080)', keyboardType: TextInputType.url, action: TextInputAction.next),
            const SizedBox(height: 12),
            TvField(controller: _user, label: 'Användarnamn', action: TextInputAction.next),
            const SizedBox(height: 12),
            TvField(controller: _pass, label: 'Lösenord', obscure: true, onSubmitted: (_) => _go()),
            const SizedBox(height: 12),
            Tv(
              onTap: () => setState(() => _agreed = !_agreed),
              builder: (c, f) => Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Icon(_agreed ? Icons.check_box : Icons.check_box_outline_blank, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Jag har laglig rätt att använda den här tjänsten.', style: TextStyle(fontSize: 17))),
                ]),
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 18))),
            const SizedBox(height: 16),
            Center(
              child: _busy
                  ? const CircularProgressIndicator()
                  : Opacity(opacity: _agreed ? 1 : 0.4, child: TvButton(label: 'Anslut', icon: Icons.login, onTap: _agreed ? _go : () {})),
            ),
          ]),
        ),
      ),
    );
  }
}

enum Section { cont, movies, series, live }

class HomePage extends StatefulWidget {
  final Xtream api;
  const HomePage({super.key, required this.api});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Section _tab = Section.cont;

  Future<void> _logout() async {
    await Store.clearAccount();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_tab) {
      case Section.cont:
        body = ContinuePage(api: widget.api, onChanged: () => setState(() {}));
      case Section.movies:
        body = BrowsePage(key: const ValueKey('m'), api: widget.api, kind: Kind.movie);
      case Section.series:
        body = BrowsePage(key: const ValueKey('s'), api: widget.api, kind: Kind.series);
      case Section.live:
        body = BrowsePage(key: const ValueKey('l'), api: widget.api, kind: Kind.live);
    }
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
            child: Row(children: [
              const Icon(Icons.public, color: kAccent, size: 32),
              const SizedBox(width: 10),
              const Text('Orbit', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(width: 32),
              TvButton(label: 'Fortsätt titta', selected: _tab == Section.cont, autofocus: true, onTap: () => setState(() => _tab = Section.cont)),
              const SizedBox(width: 10),
              TvButton(label: 'Filmer', selected: _tab == Section.movies, onTap: () => setState(() => _tab = Section.movies)),
              const SizedBox(width: 10),
              TvButton(label: 'Serier', selected: _tab == Section.series, onTap: () => setState(() => _tab = Section.series)),
              const SizedBox(width: 10),
              TvButton(label: 'Live', selected: _tab == Section.live, onTap: () => setState(() => _tab = Section.live)),
              const Spacer(),
              TvButton(label: 'Logga ut', icon: Icons.logout, onTap: _logout),
            ]),
          ),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

class ContinuePage extends StatefulWidget {
  final Xtream api;
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
        return Tv(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(url: p.url, title: p.title, key2: p.key, poster: p.poster, kind: p.kind)));
            if (mounted) setState(() {});
          },
          builder: (c, f) => ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              color: kPanel,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Stack(fit: StackFit.expand, children: [
                  posterImage(p.poster),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(value: (p.posSec / p.durSec).clamp(0.0, 1.0), minHeight: 6, color: kAccent, backgroundColor: Colors.black54),
                  ),
                ])),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${p.title}\n${fmtTime(p.posSec)} av ${fmtTime(p.durSec)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.white)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
