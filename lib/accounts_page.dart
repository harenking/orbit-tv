import 'package:flutter/material.dart';
import 'api.dart';
import 'storage.dart';
import 'tv.dart';

/// Formulär för att lägga till Xtream-konto eller M3U-spellista.
class AddAccountForm extends StatefulWidget {
  final void Function(Account) onAdded;
  final bool autofocus;
  const AddAccountForm({super.key, required this.onAdded, this.autofocus = false});

  @override
  State<AddAccountForm> createState() => _AddAccountFormState();
}

class _AddAccountFormState extends State<AddAccountForm> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _m3u = false;
  bool _busy = false;
  bool _agreed = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final url = _url.text.trim();
    if (url.isEmpty || (!_m3u && (_user.text.trim().isEmpty || _pass.text.isEmpty))) {
      setState(() => _error = 'Fyll i alla fält');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final host = Uri.tryParse(url.contains('://') ? url : 'http://$url')?.host ?? url;
    final acc = Account(
      id: Account.makeId(url, _user.text.trim()),
      name: _name.text.trim().isNotEmpty ? _name.text.trim() : (_m3u ? 'Spellista @ $host' : '${_user.text.trim()} @ $host'),
      type: _m3u ? 'm3u' : 'xtream',
      url: url,
      user: _m3u ? '' : _user.text.trim(),
      pass: _m3u ? '' : _pass.text,
    );
    try {
      await Source.of(acc).login();
      widget.onAdded(acc);
      if (mounted) {
        setState(() => _busy = false);
        _name.clear();
        _url.clear();
        _user.clear();
        _pass.clear();
      }
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        TvButton(label: 'Xtream-konto', selected: !_m3u, onTap: () => setState(() => _m3u = false), autofocus: widget.autofocus),
        const SizedBox(width: 8),
        TvButton(label: 'M3U-spellista', selected: _m3u, onTap: () => setState(() => _m3u = true)),
      ]),
      const SizedBox(height: 12),
      TvField(controller: _name, label: 'Namn (valfritt)', action: TextInputAction.next),
      const SizedBox(height: 12),
      TvField(controller: _url, label: _m3u ? 'Adress till M3U-listan' : 'Serveradress (t.ex. http://server.se:8080)', keyboardType: TextInputType.url, action: TextInputAction.next),
      if (!_m3u) ...[
        const SizedBox(height: 12),
        TvField(controller: _user, label: 'Användarnamn', action: TextInputAction.next),
        const SizedBox(height: 12),
        TvField(controller: _pass, label: 'Lösenord', obscure: true),
      ],
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
    ]);
  }
}

/// Fliken "Konton": byt, ta bort och lägg till konton och spellistor.
class AccountsPage extends StatefulWidget {
  final Source api;
  final void Function(Account) onUse; // byt konto
  final VoidCallback onChanged; // kontolistan ändrades
  const AccountsPage({super.key, required this.api, required this.onUse, required this.onChanged});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  String? _confirmDelete;

  @override
  Widget build(BuildContext context) {
    final list = Store.accounts;
    final activeId = widget.api.a.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
      children: [
        const Padding(padding: EdgeInsets.only(top: 16, bottom: 8), child: Text('Konton och spellistor', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
        for (final a in list)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(a.isM3u ? 'M3U-spellista' : 'Xtream', style: const TextStyle(fontSize: 14, color: Colors.white60)),
                ]),
              ),
              if (a.id == activeId)
                const Padding(padding: EdgeInsets.only(right: 12), child: Text('Används nu', style: TextStyle(color: kAccent, fontSize: 16, fontWeight: FontWeight.w700)))
              else
                Padding(padding: const EdgeInsets.only(right: 8), child: TvButton(label: 'Använd', icon: Icons.swap_horiz, onTap: () => widget.onUse(a))),
              if (a.isM3u)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TvButton(
                    label: 'Uppdatera',
                    icon: Icons.refresh,
                    onTap: () {
                      M3uSource.forget(a.id);
                      if (a.id == activeId) widget.onUse(a);
                    },
                  ),
                ),
              _confirmDelete == a.id
                  ? TvButton(
                      label: 'Bekräfta borttagning',
                      icon: Icons.delete,
                      selected: true,
                      onTap: () async {
                        await Store.removeAccount(a.id);
                        setState(() => _confirmDelete = null);
                        widget.onChanged();
                      },
                    )
                  : TvButton(label: 'Ta bort', icon: Icons.delete_outline, onTap: () => setState(() => _confirmDelete = a.id)),
            ]),
          ),
        const Padding(padding: EdgeInsets.only(top: 28, bottom: 8), child: Text('Lägg till', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
        AddAccountForm(onAdded: (a) async {
          await Store.addAccount(a);
          widget.onUse(a);
        }),
      ],
    );
  }
}
