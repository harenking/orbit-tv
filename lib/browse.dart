import 'package:flutter/material.dart';
import 'api.dart';
import 'player_page.dart';
import 'series_page.dart';
import 'storage.dart';
import 'tv.dart';

/// Kategorier till vänster, innehåll i ett rutnät till höger.
class BrowsePage extends StatefulWidget {
  final Xtream api;
  final Kind kind;
  const BrowsePage({super.key, required this.api, required this.kind});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  List<Cat>? _cats;
  Cat? _cat;
  List<Item>? _items;
  String? _error;
  String _filter = '';
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    try {
      final c = await widget.api.categories(widget.kind);
      if (!mounted) return;
      setState(() => _cats = c);
      if (c.isNotEmpty) _pick(c.first);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pick(Cat c) async {
    final token = ++_loadToken;
    setState(() {
      _cat = c;
      _items = null;
      _filter = '';
    });
    try {
      final it = await widget.api.items(widget.kind, c.id);
      if (!mounted || token != _loadToken) return;
      setState(() => _items = it);
    } catch (e) {
      if (mounted && token == _loadToken) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _open(Item it) {
    final nav = Navigator.of(context);
    switch (it.kind) {
      case Kind.series:
        nav.push(MaterialPageRoute(builder: (_) => SeriesPage(api: widget.api, item: it)));
      case Kind.movie:
        nav.push(MaterialPageRoute(
            builder: (_) => PlayerPage(url: widget.api.movieUrl(it.id, it.ext), title: it.name, key2: 'm:${it.id}', poster: it.poster, kind: 'movie')));
      case Kind.live:
        nav.push(MaterialPageRoute(builder: (_) => PlayerPage(url: widget.api.liveUrl(it.id), title: it.name, key2: 'l:${it.id}', poster: it.poster, live: true)));
    }
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
                  child: Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, color: Colors.white)),
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
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Sök i kategorin…', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
              style: const TextStyle(fontSize: 18),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Expanded(
            child: _items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(child: Text('Inget hittades', style: TextStyle(fontSize: 20, color: Colors.white70)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 24, 32),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: live ? 220 : 190,
                          childAspectRatio: live ? 1.15 : 0.6,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: items.length,
                        itemBuilder: (c, i) => _tile(items[i], live),
                      ),
          ),
        ]),
      ),
    ]);
  }

  Widget _tile(Item it, bool live) {
    final prog = it.kind == Kind.movie ? Store.progress('m:${it.id}') : null;
    return Tv(
      onTap: () => _open(it),
      builder: (c, f) => ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Container(
          color: kPanel,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                posterImage(it.poster, fit: live ? BoxFit.contain : BoxFit.cover),
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
