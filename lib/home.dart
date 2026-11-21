import 'package:flutter/material.dart';
import 'api.dart';
import 'open.dart';
import 'parental.dart';
import 'player_page.dart';
import 'storage.dart';
import 'tv.dart';

/// Liten affisch/kanalruta som används i rader och rutnät.
class PosterCard extends StatelessWidget {
  final String title;
  final String? poster;
  final double width;
  final double aspect; // höjd/bredd för bilden
  final double? progress;
  final bool fav;
  final BoxFit fit;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const PosterCard({
    super.key,
    required this.title,
    required this.poster,
    required this.onTap,
    this.onLongPress,
    this.width = 150,
    this.aspect = 1.45,
    this.progress,
    this.fav = false,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Tv(
        onTap: onTap,
        onLongPress: onLongPress,
        builder: (c, f) => ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Container(
            color: kPanel,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(
                aspectRatio: 1 / aspect,
                child: Stack(fit: StackFit.expand, children: [
                  posterImage(poster, fit: fit),
                  if (fav) const Positioned(top: 6, right: 6, child: Icon(Icons.favorite, color: Colors.pinkAccent, size: 22)),
                  if (progress != null)
                    Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: progress!.clamp(0.0, 1.0), minHeight: 5, color: kAccent, backgroundColor: Colors.black54)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final List<Widget> cards;
  final Widget? empty;
  const _Row({required this.title, required this.cards, this.empty});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(32, 0, 32, 8), child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        if (cards.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: empty ?? const SizedBox.shrink())
        else
          SizedBox(
            height: 290,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) => cards[i],
            ),
          ),
      ]),
    );
  }
}

/// Startsidan: fortsätt titta, favoriter och nyligen tillagt.
class HomeTab extends StatefulWidget {
  final Source api;
  const HomeTab({super.key, required this.api});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static final Map<String, List<Item>> _recentCache = {};
  List<Item>? _movies;
  List<Item>? _series;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  /// Utan föräldralåsets kategorier: de visas aldrig på startsidan.
  Future<List<Item>> _recent(Kind k) async {
    final key = '${widget.api.a.id}:${k.name}';
    final hit = _recentCache[key];
    if (hit != null) return hit;
    final cats = await widget.api.categories(k);
    final hidden = {for (final c in cats) if (Guard.matches(c.name)) c.id};
    final all = await widget.api.recent(k);
    final l = all.where((i) => !hidden.contains(i.catId)).take(30).toList();
    _recentCache[key] = l;
    return l;
  }

  Future<void> _loadRecent() async {
    try {
      final m = await _recent(Kind.movie);
      if (mounted) setState(() => _movies = m);
      final s = await _recent(Kind.series);
      if (mounted) setState(() => _series = s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _open(Item it) async {
    await openItem(context, widget.api, it);
    if (mounted) setState(() {});
  }

  List<Widget> _items(List<Item>? l) => [
        for (final it in l ?? const <Item>[])
          PosterCard(
            title: it.name,
            poster: it.poster,
            onTap: () => _open(it),
            onLongPress: () async {
              await Store.toggleFav(favOf(widget.api, it));
              if (mounted) setState(() {});
            },
            fav: Store.isFav(favOf(widget.api, it)),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final cont = Store.continueList().where((p) => !(p.locked && Guard.active)).take(20).toList();
    final favs = Store.favs(widget.api.a.id).where((f) => !(f.locked && Guard.active)).toList();
    final loading = _movies == null && _series == null && _error == null;
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        if (cont.isNotEmpty)
          _Row(title: 'Fortsätt titta', cards: [
            for (final p in cont)
              PosterCard(
                title: p.title,
                poster: p.poster,
                progress: p.durSec > 0 ? p.posSec / p.durSec : null,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(url: p.url, title: p.title, key2: p.key, poster: p.poster, kind: p.kind, locked: p.locked)));
                  if (mounted) setState(() {});
                },
              ),
          ]),
        if (favs.isNotEmpty)
          _Row(title: 'Mina favoriter', cards: [
            for (final f in favs)
              PosterCard(
                title: f.name,
                poster: f.poster,
                fav: true,
                fit: f.kind == 'live' ? BoxFit.contain : BoxFit.cover,
                onTap: () => _open(itemOf(f)),
                onLongPress: () async {
                  await Store.toggleFav(f);
                  if (mounted) setState(() {});
                },
              ),
          ]),
        if (_error != null) Padding(padding: const EdgeInsets.all(32), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 18))),
        if (loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (_movies != null) _Row(title: 'Nyligen tillagda filmer', cards: _items(_movies), empty: const Text('Inget hittades.')),
        if (_series != null && _series!.isNotEmpty) _Row(title: 'Nyligen tillagda serier', cards: _items(_series)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 32), child: Text('Tips: håll in OK på en titel för att lägga till eller ta bort favorit.', style: TextStyle(color: Colors.white54, fontSize: 15))),
      ],
    );
  }
}

/// Favoritsidan: filmer, serier och kanaler i var sin rad.
class FavoritesTab extends StatefulWidget {
  final Source api;
  const FavoritesTab({super.key, required this.api});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  Future<void> _open(Fav f) async {
    if (f.locked && Guard.active && !Guard.unlocked) {
      if (!await Guard.ensure(context)) return;
    }
    if (!mounted) return;
    await openItem(context, widget.api, itemOf(f), locked: f.locked);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = Store.favs(widget.api.a.id);
    if (all.isEmpty) {
      return const Center(child: Text('Inga favoriter än.\nHåll in OK på en film, serie eller kanal för att lägga till.', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, color: Colors.white70)));
    }
    Widget row(String title, String kind) {
      final l = all.where((f) => f.kind == kind).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (l.isEmpty) return const SizedBox.shrink();
      return _Row(title: title, cards: [
        for (final f in l)
          PosterCard(
            title: (f.locked && Guard.active && !Guard.unlocked) ? Guard.mask(f.name) : f.name,
            poster: (f.locked && Guard.active && !Guard.unlocked) ? null : f.poster,
            fav: true,
            fit: kind == 'live' ? BoxFit.contain : BoxFit.cover,
            onTap: () => _open(f),
            onLongPress: () async {
              await Store.toggleFav(f);
              if (mounted) setState(() {});
            },
          ),
      ]);
    }

    return ListView(padding: const EdgeInsets.only(top: 4, bottom: 32), children: [
      row('Filmer', 'movie'),
      row('Serier', 'series'),
      row('Kanaler', 'live'),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 32), child: Text('Håll in OK för att ta bort en favorit.', style: TextStyle(color: Colors.white54, fontSize: 15))),
    ]);
  }
}
