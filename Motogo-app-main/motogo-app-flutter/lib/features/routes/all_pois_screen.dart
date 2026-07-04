import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_image.dart';
import 'route_poi_sheet.dart';

/// Katalog VŠECH bodů zájmu napříč trasami. Trasa je jen doporučení — tady si
/// zákazník vybere zastávky z různých tras (i ze dvou tras najednou) a sestaví
/// si vlastní vyjížďku, kterou pak naviguje přímo v appce.
class AllPoisScreen extends ConsumerStatefulWidget {
  /// Předvybrané body (klíče `routeId:poiId`) — např. „uprav tuto trasu".
  final Set<String>? initialSelected;
  /// Režim výběru pro editor trasy: spodní tlačítko vrátí vybrané body
  /// (Navigator.pop) místo přechodu na sestavení/navigaci.
  final bool pickMode;
  const AllPoisScreen({super.key, this.initialSelected, this.pickMode = false});

  @override
  ConsumerState<AllPoisScreen> createState() => _AllPoisScreenState();
}

class _AllPoisScreenState extends ConsumerState<AllPoisScreen> {
  final Set<String> _selected = {};
  String _query = '';
  String? _routeFilter; // null = vše, _kCommunity = komunitní body, jinak id trasy
  final Set<String> _cats = {}; // aktivní kategorie (prázdné = všechny)

  /// Sentinel filtru pro komunitní (uživatelské) body zájmu.
  static const _kCommunity = '__community__';

  /// Kategorie bodů zájmu — odvozují se heuristicky z názvu/popisu.
  static const List<_PoiCat> _catDefs = [
    _PoiCat('food', '🍽️', 'poiCatFood'),
    _PoiCat('castle', '🏰', 'poiCatCastle'),
    _PoiCat('lookout', '🗼', 'poiCatLookout'),
    _PoiCat('water', '🌊', 'poiCatWater'),
    _PoiCat('sights', '⛪', 'poiCatSights'),
    _PoiCat('nature', '🌳', 'poiCatNature'),
    _PoiCat('other', '📍', 'poiCatOther'),
  ];

  // „hrad" jen na začátku slova — jinak chytá „zahrada" i „přehrada".
  static final RegExp _reHrad = RegExp(r'\bhrad');

  /// Známé klíče kategorií (pro validaci explicitní hodnoty z backendu).
  static const Set<String> _catKeys = {
    'food', 'castle', 'lookout', 'water', 'sights', 'nature', 'other'
  };

  // Klíčová slova (bez diakritiky, malá písmena). Kryjí i SK/PL/DE/AT varianty.
  static const List<String> _kwFood = [
    'restaur', 'hospod', 'hostin', 'pivovar', 'kavar', 'cafe', 'cukrar',
    'obcerstv', 'bistro', 'motorest', 'vinar', 'grill', 'pizz', 'krcma',
    'koliba', 'salas', 'bufet', 'gostiln', 'gasthof', 'gasthaus', 'brauhaus'
  ];
  static const List<String> _kwCastle = [
    'zamek', 'zamec', 'zamok', 'zricen', 'tvrz', 'palac', 'castle', 'schloss',
    'pevnost', 'hradisk', 'hradisc', 'burg', 'chateau', 'castel', 'citadel'
  ];
  static const List<String> _kwLookout = [
    'rozhled', 'vyhlid', 'vyhled', 'vez', 'aussicht', 'panorama'
  ];
  static const List<String> _kwWater = [
    'prehrad', 'priehrad', 'rybnik', 'jezer', 'jazer', 'vodopad', 'nadrz',
    'plaz', 'splav', 'soutok', 'see', 'loch', 'fjord', 'lago', 'jazior'
  ];
  static const List<String> _kwSights = [
    'kostel', 'klaster', 'klastor', 'kaple', 'kaplnk', 'katedral', 'bazilik',
    'poutni', 'pamatnik', 'pamatn', 'muzeum', 'muzej', 'museum', 'synagog',
    'mohyla', 'pomnik', 'betlem', 'krizov', 'rotund', 'namesti', 'namest',
    'hrobka', 'skanzen', 'radnice', 'chram', 'opatstv', 'sgrafit'
  ];
  static const List<String> _kwNature = [
    'jeskyn', 'jaskyn', 'propast', 'skal', 'prales', 'park', 'vrch', 'hora',
    'sedlo', 'prusmyk', 'priesmyk', 'soutesk', 'udol', 'dolin', 'pramen',
    'zahrad', 'steny', 'stena', 'kamen', 'ostrov', 'pleso', 'plesa', 'kopec',
    'klamm', 'kanon', 'rezerv', 'jezirk', 'diery'
  ];

  /// Odstranění diakritiky pro porovnávání klíčových slov.
  static String _fold(String s) {
    const from = 'áäàâčćďéěèêíìîïľĺňñóöòôřšśťúůüýžźż';
    const to = 'aaaaccdeeeeiiiillnnoooorsstuuuyzzz';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  /// Kategorie bodu zájmu. Přednost má explicitní `category` z backendu; jinak
  /// se odvodí z NÁZVU (spolehlivé — „Zámek …", „Rozhledna …", „Restaurace …")
  /// a teprve když název mlčí, z popisu. „Jídlo a pití" se z popisu NEODVOZUJE:
  /// skoro každý popis zmiňuje kavárnu/restauraci poblíž, což dřív házelo hrady
  /// a rozhledny do kategorie jídla (např. zámek Jindřichův Hradec).
  static String _catOf(RoutePoi p) {
    final explicit = p.category?.toLowerCase();
    if (explicit != null && _catKeys.contains(explicit)) return explicit;
    final byName = _catByText(_fold(p.name), allowFood: true);
    if (byName != 'other') return byName;
    return _catByText(_fold(p.description ?? ''), allowFood: false);
  }

  static String _catByText(String n, {required bool allowFood}) {
    bool has(List<String> ks) => ks.any(n.contains);
    if (allowFood && has(_kwFood)) return 'food';
    if (_reHrad.hasMatch(n) || has(_kwCastle)) return 'castle';
    if (has(_kwLookout)) return 'lookout';
    if (has(_kwWater)) return 'water';
    if (has(_kwSights)) return 'sights';
    if (has(_kwNature)) return 'nature';
    return 'other';
  }

  // Náhodné pořadí bodů — nové při každém otevření (i po startu appky). Použije
  // se, když není známá poloha; se známou polohou vyhrává řazení dle vzdálenosti.
  late final int _shuffleSeed;

  @override
  void initState() {
    super.initState();
    _shuffleSeed = Random().nextInt(0x7fffffff);
    if (widget.initialSelected != null) _selected.addAll(widget.initialSelected!);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    // Body z tras + komunitní (uživatelské) body zájmu.
    final routePois = ref.watch(allPoisProvider);
    final userPois = ref.watch(userPoisProvider).valueOrNull ?? const [];
    final all = <PoiEntry>[
      ...routePois,
      ...userPois.map((p) => PoiEntry(p, null, null)),
    ]..shuffle(Random(_shuffleSeed));
    final me = ref.watch(currentLocationProvider).valueOrNull;

    // Filtr + řazení (podle vzdálenosti od jezdce, jinak dle názvu trasy).
    final q = _query.trim().toLowerCase();
    // 1) Zdroj (vše / komunitní / trasa) + hledání — základ pro počty kategorií.
    final sourceFiltered = all.where((e) {
      if (_routeFilter == _kCommunity) {
        if (e.route != null) return false; // jen komunitní body
      } else if (_routeFilter != null && e.route?.id != _routeFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return e.poi.nameFor(lang).toLowerCase().contains(q) ||
          (e.route?.nameFor(lang).toLowerCase().contains(q) ?? false);
    }).toList();
    // 2) Kategorie.
    final list = _cats.isEmpty
        ? sourceFiltered
        : sourceFiltered.where((e) => _cats.contains(_catOf(e.poi))).toList();
    if (me != null) {
      const d = Distance();
      list.sort((a, b) => d
          .as(LengthUnit.Meter, me, a.latLng!)
          .compareTo(d.as(LengthUnit.Meter, me, b.latLng!)));
    }

    // Trasy, které mají aspoň jeden POI (pro filtr).
    final routesWithPois = <String, RouteItem>{};
    for (final e in routePois) {
      if (e.route != null) routesWithPois[e.route!.id] = e.route!;
    }

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            _filters(context, lang, routesWithPois.values.toList(), all, sourceFiltered),
            Expanded(
              child: list.isEmpty
                  ? _empty(context)
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, _selected.isEmpty ? 24 : 110),
                      itemCount: list.length,
                      itemBuilder: (context, i) =>
                          _poiCard(context, list[i], lang, me),
                    ),
            ),
          ],
        ),
      ),
      bottomSheet: _selected.isEmpty ? null : _navBar(context, all, me),
    );
  }

  // ── Header ──
  Widget _header(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
      decoration: const BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(MotoGoRadius.hdr)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => widget.pickMode
                    ? Navigator.of(context).pop()
                    : context.backOr('/routes'),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 4),
              const Text('📍', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(context).tr('poiBrowseAll'),
                  style: const TextStyle(
                    fontSize: MotoGoTypo.sizeH1,
                    fontWeight: MotoGoTypo.w900,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 2),
            child: Text(
              t(context).tr('poiBrowseSub'),
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: MotoGoTypo.w600,
                color: Color(0xFF8AAB99),
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Hledání
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.search, size: 18, color: MotoGoColors.g400),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: t(context).tr('poiSearch'),
                      hintStyle: const TextStyle(color: MotoGoColors.g400, fontSize: MotoGoTypo.sizeBase),
                    ),
                    style: const TextStyle(fontSize: MotoGoTypo.sizeLg, color: MotoGoColors.black),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filtry: řádek zdroje (vše / komunitní / trasa) + řádek kategorií ──
  Widget _filters(BuildContext context, String lang, List<RouteItem> routes,
      List<PoiEntry> all, List<PoiEntry> sourceFiltered) {
    final communityCount = all.where((e) => e.route == null).length;
    if (routes.length < 2 && communityCount == 0) return const SizedBox(height: 8);

    // Počty kategorií z aktuálního zdroje (bez zapnutých kategorií).
    final catCounts = <String, int>{};
    for (final e in sourceFiltered) {
      final c = _catOf(e.poi);
      catCounts[c] = (catCounts[c] ?? 0) + 1;
    }

    RouteItem? selRoute;
    if (_routeFilter != null && _routeFilter != _kCommunity) {
      for (final r in routes) {
        if (r.id == _routeFilter) {
          selRoute = r;
          break;
        }
      }
    }

    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            children: [
              _srcChip(t(context).tr('poiAllRoutes'), Icons.apps, _routeFilter == null,
                  all.length, () => setState(() => _routeFilter = null)),
              if (communityCount > 0)
                _srcChip(t(context).tr('poiCommunity'), Icons.groups, _routeFilter == _kCommunity,
                    communityCount, () => setState(() => _routeFilter = _kCommunity)),
              // Výběr konkrétní trasy — otevře sheet s hledáním (923 bodů ≠ řada chipů).
              _srcChip(
                selRoute != null ? selRoute.nameFor(lang) : t(context).tr('poiRoutePick'),
                Icons.route,
                selRoute != null,
                selRoute != null
                    ? all.where((e) => e.route?.id == selRoute!.id).length
                    : null,
                () => _openRoutePicker(context, lang, routes, all),
                trailing: Icons.arrow_drop_down,
              ),
            ],
          ),
        ),
        // Kategorie (jen ty, co mají v aktuálním zdroji aspoň 1 bod).
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            children: [
              for (final c in _catDefs)
                if ((catCounts[c.key] ?? 0) > 0 || _cats.contains(c.key))
                  _catChip(context, c, catCounts[c.key] ?? 0),
            ],
          ),
        ),
      ],
    );
  }

  Widget _srcChip(String label, IconData icon, bool active, int? count, VoidCallback onTap,
      {IconData? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        pressedScale: 0.94,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? MotoGoColors.greenDark : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            border: Border.all(color: active ? MotoGoColors.greenDark : MotoGoColors.g200, width: 1.5),
            boxShadow: active ? MotoGoShadows.cardSmall : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : MotoGoColors.greenDark),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: MotoGoTypo.sizeBase,
                    fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
                    color: active ? Colors.white : MotoGoColors.black,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: active ? Colors.white.withValues(alpha: 0.22) : MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: MotoGoTypo.sizeSm,
                      fontWeight: MotoGoTypo.w800,
                      color: active ? Colors.white : MotoGoColors.greenDark,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
              if (trailing != null)
                Icon(trailing, size: 18, color: active ? Colors.white : MotoGoColors.g500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _catChip(BuildContext context, _PoiCat c, int count) {
    final active = _cats.contains(c.key);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        pressedScale: 0.94,
        onTap: () => setState(() => active ? _cats.remove(c.key) : _cats.add(c.key)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: active ? MotoGoColors.greenPale : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            border: Border.all(
                color: active ? MotoGoColors.greenDark : MotoGoColors.g200,
                width: active ? 1.6 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(
                t(context).tr(c.i18nKey),
                style: TextStyle(
                  fontSize: MotoGoTypo.sizeBase,
                  fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
                  color: active ? MotoGoColors.greenDarker : MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: MotoGoTypo.sizeSm,
                  fontWeight: MotoGoTypo.w800,
                  color: active ? MotoGoColors.greenDarker : MotoGoColors.g400,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sheet s výběrem trasy (hledání + počty bodů) ──
  void _openRoutePicker(
      BuildContext context, String lang, List<RouteItem> routes, List<PoiEntry> all) {
    final sorted = List<RouteItem>.from(routes)
      ..sort((a, b) => a.nameFor(lang).compareTo(b.nameFor(lang)));
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) {
        var q = '';
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final qq = q.trim().toLowerCase();
            final filtered = qq.isEmpty
                ? sorted
                : sorted.where((r) => r.nameFor(lang).toLowerCase().contains(qq)).toList();
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            t(sheetCtx).tr('poiRoutePickTitle'),
                            style: const TextStyle(
                              fontSize: MotoGoTypo.sizeH2,
                              fontWeight: MotoGoTypo.w900,
                              color: MotoGoColors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: MotoGoColors.g100,
                          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 18, color: MotoGoColors.g400),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                autofocus: false,
                                onChanged: (v) => setSheet(() => q = v),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: t(sheetCtx).tr('poiRouteSearch'),
                                  hintStyle: const TextStyle(
                                      color: MotoGoColors.g400, fontSize: MotoGoTypo.sizeBase),
                                ),
                                style: const TextStyle(
                                    fontSize: MotoGoTypo.sizeLg, color: MotoGoColors.black),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        children: [
                          _routePickTile(sheetCtx, Icons.apps, t(sheetCtx).tr('poiAllRoutes'),
                              all.length, _routeFilter == null, () {
                            setState(() => _routeFilter = null);
                            Navigator.of(sheetCtx).pop();
                          }),
                          for (final r in filtered)
                            _routePickTile(
                              sheetCtx,
                              Icons.route,
                              r.nameFor(lang),
                              all.where((e) => e.route?.id == r.id).length,
                              _routeFilter == r.id,
                              () {
                                setState(() => _routeFilter = r.id);
                                Navigator.of(sheetCtx).pop();
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _routePickTile(BuildContext context, IconData icon, String label, int count,
      bool active, VoidCallback onTap) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(icon, size: 20, color: active ? MotoGoColors.greenDark : MotoGoColors.g500),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: MotoGoTypo.sizeLg,
          fontWeight: active ? MotoGoTypo.w900 : MotoGoTypo.w600,
          color: MotoGoColors.black,
          decoration: TextDecoration.none,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: MotoGoColors.greenPale,
              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeSm,
                fontWeight: MotoGoTypo.w800,
                color: MotoGoColors.greenDark,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check, size: 18, color: MotoGoColors.greenDark),
          ],
        ],
      ),
    );
  }

  // ── Karta POI ──
  Widget _poiCard(BuildContext context, PoiEntry e, String lang, LatLng? me) {
    final selected = _selected.contains(e.key);
    String? distTxt;
    if (me != null && e.latLng != null) {
      final m = const Distance().as(LengthUnit.Meter, me, e.latLng!);
      distTxt = m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        pressedScale: 0.98,
        onTap: () => setState(() {
          if (selected) {
            _selected.remove(e.key);
          } else {
            _selected.add(e.key);
          }
        }),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            border: Border.all(
              color: selected ? MotoGoColors.greenDark : MotoGoColors.g200,
              width: selected ? 2 : 1,
            ),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Náhled
              SizedBox(
                width: 84,
                height: 84,
                child: e.poi.cover != null
                    ? RouteImage(
                        url: e.poi.cover!,
                        targetWidth: 300,
                        placeholder: (_) => _thumbFallback(),
                        error: (_) => _thumbFallback(),
                      )
                    : _thumbFallback(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.poi.nameFor(lang),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeLg,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(e.route != null ? Icons.route : Icons.groups, size: 12, color: MotoGoColors.greenDark),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              e.route?.nameFor(lang) ?? 'Komunitní bod',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: MotoGoTypo.w600,
                                color: MotoGoColors.g500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          if (e.poi.ratingCount > 0) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.star, size: 12, color: Color(0xFFF5B301)),
                            const SizedBox(width: 2),
                            Text(
                              (e.poi.avgRating ?? 0).toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: MotoGoTypo.w700,
                                color: MotoGoColors.g500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                          if (distTxt != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.near_me, size: 12, color: MotoGoColors.g400),
                            const SizedBox(width: 2),
                            Text(
                              distTxt,
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: MotoGoTypo.w700,
                                color: MotoGoColors.g500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Detail (i) + výběr
              GestureDetector(
                onTap: () => showRoutePoiSheet(context, e.poi, lang),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.info_outline, size: 20, color: MotoGoColors.g400),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10, left: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: selected ? MotoGoColors.greenDark : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? MotoGoColors.greenDark : MotoGoColors.g200,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback() => Container(
        color: MotoGoColors.greenPale,
        child: const Center(child: Text('📍', style: TextStyle(fontSize: 26))),
      );

  // ── Spodní lišta „Navigovat přes vybrané" ──
  Widget _navBar(BuildContext context, List<PoiEntry> all, LatLng? me) {
    final n = _selected.length;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: MotoGoShadows.stickyBar),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(_selected.clear),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Text(
                '$n ${t(context).tr('poiSelectedSuffix')}  ✕',
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PressableScale(
              pressedScale: 0.97,
              onTap: () => _navigate(context, all, me),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: MotoGoColors.green,
                  borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  boxShadow: [
                    BoxShadow(color: MotoGoColors.green.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.pickMode ? Icons.add : Icons.navigation, size: 18, color: MotoGoColors.black),
                      const SizedBox(width: 8),
                      Text(
                        t(context).tr(widget.pickMode ? 'poiAddToRoute' : 'poiContinue'),
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeXl,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, List<PoiEntry> all, LatLng? me) {
    final pois = all.where((e) => _selected.contains(e.key)).map((e) => e.poi).toList();
    if (pois.isEmpty) return;
    // Režim výběru → vrať body do editoru trasy.
    if (widget.pickMode) {
      Navigator.of(context).pop(pois);
      return;
    }
    // Jinak sestav trasu (greedy od polohy) a otevři editor pro doladění.
    final route = buildCustomRoute(pois, from: me, name: t(context).tr('poiCustomRouteTitle'));
    context.push('/route-build', extra: route);
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🗺️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            t(context).tr('poiEmpty'),
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeXl,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// Definice kategorie bodů zájmu (klíč + emoji + i18n klíč popisku).
class _PoiCat {
  final String key;
  final String emoji;
  final String i18nKey;
  const _PoiCat(this.key, this.emoji, this.i18nKey);
}
