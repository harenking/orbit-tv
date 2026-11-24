import 'package:flutter/material.dart';
import 'api.dart';
import 'parental.dart';
import 'open.dart';
import 'storage.dart';
import 'tv.dart';

/// Kategorier till vänster, innehåll i ett rutnät till höger.
class BrowsePage extends StatefulWidget {
  final Source api;
  final Kind kind;
  const BrowsePage({super.key, required this.api, required this.kind});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  static const _allId = '__all__';
  static const _recentId = '__recent__';
  Set<String> _recentLocked = const {};
  List<Cat>? _cats;
  Cat? _cat;
  List<Item>? _items;
  String? _error;
  String _filter = '';
  int _loadToken = 0;
  final TextEditingController _searchCtl = TextEditingController();
  List<Cat> _vault = const [];
  bool get _inVault => _cat?.id == Guard.vaultId;

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    try {
      final all = await widget.api.categories(widget.kind);
      if (!mounted) return;
      // Kategorier som föräldralåset gäller samlas i en enda mapp
      final vault = all.where((c) => Guard.matches(c.name)).toList();
      final c = all.where((x) => !vault.contains(x)).toList();
      if (vault.isNotEmpty) c.add(const Cat(Guard.vaultId, Guard.vaultName));
      c.insert(0, const Cat(_allId, 'Alla'));
      // Serier: snabbval till de man tittat på nyligen (öppnas direkt om det finns några)
      final hasRecent = widget.kind == Kind.series && _recentFavs().isNotEmpty;
      if (widget.kind == Kind.series) c.insert(0, const Cat(_recentId, 'Senast kollade'));
      setState(() {
        _vault = vault;
        _cats = c;
      });
      if (hasRecent) {
        _pick(c.first);
      } else if (c.length > 2 && widget.kind == Kind.series) {
        _pick(c[2]);
      } else if (c.length > 1 && widget.kind != Kind.series) {
        _pick(c[1]);
      } else {
        _pick(c.firstWhere((x) => x.id == _allId));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pick(Cat c) async {
    if (c.id == Guard.vaultId && !await Guard.ensure(context, title: 'Ange PIN-kod')) return;
    final token = ++_loadToken;
    _searchCtl.clear();
    setState(() {
      _cat = c;
      _items = null;
      _filter = '';
    });
    try {
      final List<Item> it;
      if (c.id == _recentId) {
        final favs = _recentFavs();
        _recentLocked = {for (final f in favs) if (f.locked) f.id};
        it = favs.map(itemOf).toList();
      } else if (c.id == Guard.vaultId) {
        final lists = await Future.wait(_vault.map((v) => widget.api.items(widget.kind, v.id)));
        it = [for (final l in lists) ...l];
        it.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (c.id == _allId) {
        // Allt utom föräldralåsets kategorier (de finns bara i mappen med PIN)
        final hidden = {for (final v in _vault) v.id};
        final all = await widget.api.items(widget.kind, '');
        it = all.where((i) => !hidden.contains(i.catId)).toList();
      } else {
        it = await widget.api.items(widget.kind, c.id);
      }
      if (!mounted || token != _loadToken) return;
      setState(() => _items = it);
    } catch (e) {
      if (mounted && token == _loadToken) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Senast kollade serier. Låsta (föräldralås) visas bara när låset är upplåst.
  List<Fav> _recentFavs() => Store.recentSeries(widget.api.a.id).where((f) => !f.locked || !Guard.active || Guard.unlocked).take(40).toList();

  Future<void> _open(Item it) async {
    final locked = _inVault || (_cat?.id == _recentId && _recentLocked.contains(it.id));
    await openItem(context, widget.api, it, locked: locked);
    if (!mounted) return;
    // Uppdatera ordningen så att serien man just tittade på hamnar först
    if (_cat?.id == _recentId) {
      final favs = _recentFavs();
      setState(() {
        _recentLocked = {for (final f in favs) if (f.locked) f.id};
        _items = favs.map(itemOf).toList();
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _toggleFav(Item it) async {
    final on = await Store.toggleFav(favOf(widget.api, it, locked: _inVault));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(on ? 'Tillagd i favoriter' : 'Borttagen från favoriter', style: const TextStyle(fontSize: 18))));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(fontSize: 20, color: Colors.redAccent)));
    }
    if (_cats == null) return const Center(child: CircularProgressIndicator());
    final q = _filter.trim().toLowerCase();
    final items = (_items ?? const <Item>[]).where((i) => q.isEmpty || i.name.toLowerCase().contains(q)).toList();
    final live = widget.kind == Kind.live;

    return Row(children: [
      SizedBox(
        width: 320,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 24),
          itemCount: _cats!.length,
          itemBuilder: (c, i) {
            final cat = _cats![i];
            final sel = cat == _cat;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Tv(
                onTap: () => _pick(cat),
                builder: (c, f) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: sel ? kAccent : (f ? Colors.white24 : kPanel), borderRadius: BorderRadius.circular(9)),
                  child: Text(cat.id == Guard.vaultId ? '🔒 ${cat.name}' : cat.id == _recentId ? '🕘 ${cat.name}' : cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ),
            );
          },
        ),
      ),
      Expanded(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
            child: TvField(controller: _searchCtl, label: _cat?.id == _allId ? 'Sök bland alla titlar… (håll in OK på en titel = favorit)' : 'Sök i kategorin… (håll in OK på en titel = favorit)', icon: Icons.search, onChanged: (v) => setState(() => _filter = v)),
          ),
          Expanded(
            child: _items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(child: Text(_cat?.id == _recentId ? 'Inga serier än.
Serier du tittar på hamnar här.' : 'Inget hittades', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, color: Colors.white70)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 24, 32),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: live ? 220 : 190,
                          childAspectRatio: live ? 1.15 : 0.6,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: items.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        cacheExtent: 400,
                        itemBuilder: (c, i) => _tile(items[i], live),
                      ),
          ),
        ]),
      ),
    ]);
  }

  Widget _tile(Item it, bool live) {
    final prog = it.kind == Kind.movie ? Store.progress('m:${it.id}') : null;
    final isFav = Store.isFav(favOf(widget.api, it));
    return Tv(
      onTap: () => _open(it),
      onLongPress: () => _toggleFav(it),
      builder: (c, f) => ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Container(
          color: kPanel,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                posterImage(it.poster, fit: live ? BoxFit.contain : BoxFit.cover),
                if (isFav) const Positioned(top: 6, right: 6, child: Icon(Icons.favorite, color: Colors.pinkAccent, size: 22)),
                if (prog != null && prog.durSec > 0)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(value: (prog.posSec / prog.durSec).clamp(0.0, 1.0), minHeight: 5, color: kAccent, backgroundColor: Colors.black54),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }
}
