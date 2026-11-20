// Shop "انتخاب محصول ها" (reference recording 2): back / page-view buttons, category tabs with NEW badges, and a grey
// panel with a two-column grid of product cards (name, disc art, power / time / aim bars, select or buy-with-gems).
// Categories map to the engine's real data: national / club / luxury teams, pitches and match balls. "اختصاصی"
// (custom team from a photo) and "بازیکن ها" (players) have no backend yet and show their reference cards disabled.
import 'package:flutter/material.dart';
import 'package:nexora/core/economy/gem_shop.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/bm_data.dart';
import '../core/bm_engine.dart';
import 'fs_intro_data.dart';
import 'fs_intro_ui.dart';

/// Locked team: confirm + buy with gems (server-side deduct and unlock). True when the team is now owned.
Future<bool> fsBuyTeam(BuildContext context, BmTeam t, bool fa) async {
  final GemShop shop = GemShop.instance;
  final int price = shop.teamPrice(t.id);
  final int bal = ProfileService.current?.gems ?? 0;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext c) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: kFsNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kFsNavyEdge)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            FsDisc3D(asset: t.asset, r: 34, depth: 6),
            const SizedBox(height: 8),
            Text(fsTeamName(t, fa), style: fsText(18, weight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('این تیم قفل است. با ${fsFa(price)} الماس بازش کن؟',
                textAlign: TextAlign.center, style: fsText(13, color: const Color(0xFFC9CCE6), weight: FontWeight.w500)),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text('موجودی: ${fsFa(bal)}', style: fsText(12, color: const Color(0xFF9EA3C7), weight: FontWeight.w500)),
              const SizedBox(width: 4),
              const FsGem(size: 13),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              FsPress(
                onTap: bal >= price ? () => Navigator.pop(c, true) : null,
                enabled: bal >= price,
                child: fsBuyButton('خرید', price, 120, 34),
              ),
              const SizedBox(width: 12),
              FsPress(onTap: () => Navigator.pop(c, false), child: fsGreyButton('انصراف', 90, 34)),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (ok != true) return false;
  final GemBuyResult r = await shop.buyTeam(t.id);
  if (!context.mounted) return r.ok;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(r.ok ? '${fsTeamName(t, fa)} باز شد ✓' : gemErrorText(r.error, fa), textDirection: TextDirection.rtl)));
  return r.ok;
}

class FsShop extends StatefulWidget {
  const FsShop({
    super.key,
    required this.fa,
    required this.team,
    required this.onTeam,
    required this.onBack,
    this.tab = 0,
    this.topLane = 0,
  });
  final bool fa;

  /// The player's current team (side one).
  final String team;
  final ValueChanged<String> onTeam;
  final VoidCallback onBack;
  final int tab;
  final double topLane;
  @override
  State<FsShop> createState() => _FsShopState();
}

/// [label, isNew]
const List<(String, bool)> kFsShopTabs = <(String, bool)>[
  ('کشوری', false),
  ('باشگاهی', false),
  ('لاکچری', true),
  ('اختصاصی', true),
  ('بازیکن ها', true),
  ('زمین', false),
  ('افکت‌ها', false),
];

class _FsShopState extends State<FsShop> {
  late int _tab = widget.tab;
  bool _paged = false;
  int _field = 0, _ball = kBmDefaultBall;
  late String _team = widget.team;

  @override
  void initState() {
    super.initState();
    GemShop.instance.addListener(_changed);
    SharedPreferences.getInstance().then((SharedPreferences p) {
      if (!mounted) return;
      setState(() {
        _field = bmFieldIndex(p.getInt('bm.field'));
        _ball = bmBallIndex(p.getInt(kBmBallPref));
      });
    }, onError: (Object _) {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    GemShop.instance.removeListener(_changed);
    super.dispose();
  }

  Future<void> _savePref(String k, int v) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setInt(k, v);
    } catch (_) {}
  }

  Widget _topBtn(String label, double w, VoidCallback onTap) => FsPress(
        onTap: onTap,
        child: FsBevel(
          w: w,
          h: 35,
          radius: 6,
          lipH: 4,
          top: const Color(0xFFF7F7F2),
          bottom: const Color(0xFFD9DCD0),
          lip: const Color(0xFF9A7F95),
          child: Text(label, style: fsText(14, color: const Color(0xFF2A2A2A), weight: FontWeight.w700, height: 1)),
        ),
      );

  Widget _tabBtn(int i, double left) {
    final (String label, bool isNew) = kFsShopTabs[i];
    final bool on = _tab == i;
    return Positioned(
      left: left,
      top: 115,
      width: 44,
      height: 56,
      child: FsPress(
        onTap: () => setState(() => _tab = i),
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: <Widget>[
          Positioned(
            top: 16,
            child: FsBevel(
              w: 44,
              h: 40,
              radius: 5,
              lipH: 4,
              top: on ? const Color(0xFFC8F53A) : const Color(0xFFF4F4F0),
              bottom: on ? const Color(0xFF7DCB12) : const Color(0xFFDCDCD6),
              lip: on ? const Color(0xFF2E8DC9) : const Color(0xFFA77E9E),
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: fsText(on ? 11.5 : 9.5,
                      color: on ? const Color(0xFF173A05) : const Color(0xFF505050), weight: FontWeight.w700, height: 1.05)),
            ),
          ),
          if (isNew)
            Positioned(
              top: 0,
              child: Container(
                width: 31,
                height: 22,
                decoration: BoxDecoration(color: const Color(0xFF0E0E0E), borderRadius: BorderRadius.circular(3)),
                child: Center(child: Text('NEW', style: fsText(10, family: 'ChakraPetch', weight: FontWeight.w700, height: 1))),
              ),
            ),
        ]),
      ),
    );
  }

  List<Widget> _cards() {
    switch (_tab) {
      case 0:
      case 1:
      case 2:
        final String cat = <String>['nat', 'club', 'lux'][_tab];
        return <Widget>[for (final BmTeam t in kBmTeams.where((BmTeam t) => t.cat == cat)) _teamCard(t)];
      case 3:
        return <Widget>[_customCard()];
      case 4:
        return <Widget>[_emptyCard('بازیکن ها به‌زودی')];
      case 5:
        return <Widget>[
          for (int i = 0; i < kBmFieldsRaw.length; i++)
            _artCard(kBmFieldsRaw[i].name, 'assets/games/bermuda/thumbs/${kBmFieldsRaw[i].id}.webp', i == _field, () {
              setState(() => _field = i);
              _savePref('bm.field', i);
            }, square: true),
        ];
      default:
        return <Widget>[
          for (int i = 0; i < NB; i++)
            _artCard(widget.fa ? kBmBallFa[i] : kBmBallN[i], bmBallThumb(i), i == _ball, () {
              setState(() => _ball = i);
              _savePref(kBmBallPref, i);
            }),
        ];
    }
  }

  Widget _cardShell({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF3D3D3D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
          boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x44000000), blurRadius: 3, offset: Offset(0, 2))],
        ),
        child: child,
      );

  Widget _bar(String label, int v) => SizedBox(
        height: 17,
        child: Row(children: <Widget>[
          SizedBox(width: 30, child: Text(label, style: fsText(9.5, weight: FontWeight.w700, height: 1))),
          Container(
            width: 52,
            height: 12,
            decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(2)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(children: <Widget>[
                FractionallySizedBox(
                  widthFactor: (v / 10).clamp(0.0, 1.0),
                  child: Container(decoration: BoxDecoration(color: kFsBarGreen, borderRadius: BorderRadius.circular(2))),
                ),
                Positioned(left: 4, top: 0, bottom: 0, child: Center(child: Text(fsFa(v), style: fsText(9, weight: FontWeight.w900, height: 1)))),
              ]),
            ),
          ),
        ]),
      );

  Widget _teamCard(BmTeam t) {
    final GemShop shop = GemShop.instance;
    final bool owned = shop.ownsTeam(t.id);
    final bool sel = _team == t.id;
    final Widget btn = !owned
        ? fsBuyButton('خرید', shop.teamPrice(t.id), 120, 27, size: 12)
        : sel
            ? fsGreyButton('انتخاب شده', 120, 27, size: 12)
            : fsLimeButton('انتخاب', 120, 27, size: 12);
    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          SizedBox(
            height: 34,
            child: Text(fsTeamName(t, widget.fa),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: fsText(12.5, weight: FontWeight.w900, height: 1.2)),
          ),
          Expanded(
            child: Row(children: <Widget>[
              Expanded(child: Center(child: FsDisc3D(asset: t.asset, r: 30, depth: 5))),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                _bar('قدرت', t.power),
                const SizedBox(height: 4),
                _bar('زمان', fsTimeStat(t)),
                const SizedBox(height: 4),
                _bar('هدف', t.accuracy),
              ]),
            ]),
          ),
          Center(
            child: FsPress(
              onTap: sel && owned
                  ? null
                  : () async {
                      if (!owned) {
                        final bool ok = await fsBuyTeam(context, t, widget.fa);
                        if (!ok || !mounted) return;
                      }
                      setState(() => _team = t.id);
                      widget.onTeam(t.id);
                    },
              child: btn,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _artCard(String name, String asset, bool sel, VoidCallback onTap, {bool square = false}) => _cardShell(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: <Widget>[
            SizedBox(
              height: 34,
              width: double.infinity,
              child: Text(name, maxLines: 2, style: fsText(12.5, weight: FontWeight.w900, height: 1.2)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(square ? 6 : 60),
                child: Image.asset(asset, fit: BoxFit.contain, cacheWidth: 240, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
            const SizedBox(height: 6),
            FsPress(
              onTap: sel ? null : onTap,
              child: sel ? fsGreyButton('انتخاب شده', 120, 27, size: 12) : fsLimeButton('انتخاب', 120, 27, size: 12),
            ),
          ]),
        ),
      );

  Widget _customCard() => _cardShell(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: const Color(0xFF555555), border: Border.all(color: const Color(0xFFBDBDBD), width: 3)),
              child: const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text('با عکس دلخواهت تیم اختصاصی خودت رو بساز',
                textAlign: TextAlign.center, style: fsText(11.5, weight: FontWeight.w700, height: 1.35)),
            const SizedBox(height: 8),
            FsPress(enabled: false, onTap: () {}, child: fsLimeButton('ساخت تیم', 120, 27, size: 12)),
          ]),
        ),
      );

  Widget _emptyCard(String s) => _cardShell(child: Center(child: Text(s, style: fsText(12, color: const Color(0xFFBBBBBB)))));

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = _cards();
    return FsCanvas(dim: .15, topLane: widget.topLane, children: <Widget>[
      Positioned(left: 247, top: 34, child: _topBtn('بازگشت', 102, widget.onBack)),
      Positioned(left: 8, top: 34, child: _topBtn('نمایش صفحه‌ای', 121, () => setState(() => _paged = !_paged))),
      Positioned(
        left: 0,
        right: 0,
        top: 78,
        child: Center(
          child: Text('انتخاب محصول ها',
              style: fsText(22, weight: FontWeight.w700, shadows: const <Shadow>[Shadow(color: Color(0x88000000), blurRadius: 3)])),
        ),
      ),
      for (int i = 0; i < kFsShopTabs.length; i++) _tabBtn(i, 312 - i * 50.8),
      Positioned(
        left: 0,
        right: 0,
        top: 176,
        bottom: 0,
        child: Container(
          color: const Color(0xFFB9B9B9).withValues(alpha: .93),
          child: GridView.count(
            padding: const EdgeInsets.fromLTRB(17, 31, 11, 24),
            crossAxisCount: _paged ? 1 : 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 6,
            childAspectRatio: _paged ? 1.55 : 166 / 196,
            children: cards,
          ),
        ),
      ),
    ]);
  }
}
