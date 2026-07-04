import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_image.dart';
import 'community_submit.dart';

/// Obrazovka „Trasy" — doporučené motorkářské trasy od poboček.
/// Nahrazuje tab E-shop ve spodní liště.
class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  // Hloubkové vyhledávání — název, popis, města na cestě i body zájmu trasy.
  String _query = '';
  final TextEditingController _searchCtl = TextEditingController();

  // Rozšířené filtry (prázdné = bez omezení).
  final Set<String> _fType = {}; // 'loop' | 'poi'
  final Set<String> _fDiff = {}; // 'easy' | 'medium' | 'hard'
  final Set<String> _fCountry = {}; // ISO kódy + sentinel '__abroad__'
  RangeValues? _fDist; // km
  RangeValues? _fDur; // minuty

  static const _kAbroad = '__abroad__';

  // Náhodné pořadí tras — nové při každém otevření obrazovky (i po startu appky),
  // aby nahoře nebyla pokaždé stejná trasa. Seed je stálý po dobu života State,
  // takže se pořadí nemíchá při scrollování/filtrování.
  late final int _shuffleSeed;

  @override
  void initState() {
    super.initState();
    _shuffleSeed = Random().nextInt(0x7fffffff);
  }

  int get _activeFilterCount =>
      (_fType.isEmpty ? 0 : 1) +
      (_fDiff.isEmpty ? 0 : 1) +
      (_fCountry.isEmpty ? 0 : 1) +
      (_fDist == null ? 0 : 1) +
      (_fDur == null ? 0 : 1);

  void _clearFilters() => setState(() {
        _fType.clear();
        _fDiff.clear();
        _fCountry.clear();
        _fDist = null;
        _fDur = null;
        _query = '';
        _searchCtl.clear();
      });

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// Vyhovuje trasa zadané kombinaci filtrů? (statické parametry — sdílí seznam i náhled v sheetu)
  static bool _routeMatches(
    RouteItem r,
    Set<String> types,
    Set<String> diffs,
    Set<String> countries,
    RangeValues? dist,
    RangeValues? dur,
  ) {
    if (types.isNotEmpty && !types.contains(r.routeType)) return false;
    if (diffs.isNotEmpty && (r.difficulty == null || !diffs.contains(r.difficulty))) return false;
    // Vzdálenost/čas filtrujeme jen u tras, které hodnotu mají (neznámé nevyřazujeme).
    if (dist != null && r.distanceKm != null &&
        (r.distanceKm! < dist.start - 0.5 || r.distanceKm! > dist.end + 0.5)) return false;
    if (dur != null && r.durationMin != null &&
        (r.durationMin! < dur.start - 0.5 || r.durationMin! > dur.end + 0.5)) return false;
    if (countries.isNotEmpty) {
      final wantAbroad = countries.contains(_kAbroad);
      final specific = countries.where((c) => c != _kAbroad).toSet();
      var ok = false;
      if (wantAbroad && r.isAbroad) ok = true;
      if (!ok && specific.isNotEmpty && r.countries.any(specific.contains)) ok = true;
      if (!ok) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final dataAsync = ref.watch(routesDataProvider);

    return Material(
      color: MotoGoColors.bg,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _header(context),
                Expanded(
                  child: dataAsync.when(
                    data: (data) => _body(context, data, lang),
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: MotoGoColors.greenDark),
                    ),
                    error: (e, _) => _errorState(context, e),
                  ),
                ),
              ],
            ),
            // „+" — navrhnout trasu / bod zájmu (komunitní obsah)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'routes-add',
                backgroundColor: MotoGoColors.green,
                foregroundColor: MotoGoColors.black,
                onPressed: () => showCommunityAddMenu(context),
                child: const Icon(Icons.add, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: const BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(MotoGoRadius.hdr)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🛣️', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Text(
                t(context).tr('routesTitle'),
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeH1,
                  fontWeight: MotoGoTypo.w900,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t(context).tr('routesSubtitle'),
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeBase,
              fontWeight: MotoGoTypo.w600,
              color: Color(0xFF8AAB99),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),
          // Hloubkové hledání — trasa, místo, město na cestě, bod zájmu…
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
                    controller: _searchCtl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: t(context).tr('routesSearch'),
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

  Widget _body(BuildContext context, RoutesData data, String lang) {
    if (data.routes.isEmpty) return _emptyState(context);

    final branches = data.branchesWithRoutes;
    // Filtr poboček zrušen — trasy se neváží na pobočku, poloha jezdce je GPS.
    final byBranch = data.routes;
    // Náhodné pořadí (stálé po dobu života obrazovky) → hledání → filtr.
    final shuffled = List<RouteItem>.from(byBranch)..shuffle(Random(_shuffleSeed));
    final q = _query.trim();
    final routes = shuffled
        .where((r) => (q.isEmpty || searchMatches(r.searchBlob, q)) &&
            _routeMatches(r, _fType, _fDiff, _fCountry, _fDist, _fDur))
        .toList();

    return RefreshIndicator(
      color: MotoGoColors.greenDark,
      onRefresh: () async => ref.invalidate(routesDataProvider),
      child: CustomScrollView(
        slivers: [
          // CTA: katalog všech bodů zájmu — vlastní vyjížďka
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: PressableScale(
                pressedScale: 0.98,
                onTap: () => context.push('/pois'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(MotoGoRadius.card),
                    border: Border.all(color: MotoGoColors.green, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Text('📍', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t(context).tr('poiBrowseAll'),
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeLg,
                                fontWeight: MotoGoTypo.w900,
                                color: MotoGoColors.black,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t(context).tr('poiBrowseSub'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: MotoGoTypo.w600,
                                color: MotoGoColors.g600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: MotoGoColors.greenDark),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Rozšířené filtry (typ, obtížnost, délka, čas, země)
          SliverToBoxAdapter(child: _filterBar(context, data)),
          if (routes.isEmpty)
            SliverToBoxAdapter(child: _filterEmpty(context))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList.builder(
                itemCount: routes.length,
                itemBuilder: (context, i) {
                  final r = routes[i];
                  return StaggeredReveal(
                    index: i,
                    baseDelay: const Duration(milliseconds: 60),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _RouteCard(
                        route: r,
                        branch: r.branchId != null ? data.branches[r.branchId] : null,
                        lang: lang,
                        onTap: () => context.push('/routes/${r.id}'),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }


  // ── Lišta rozšířených filtrů (tlačítko + rychlé zrušení) ──
  Widget _filterBar(BuildContext context, RoutesData data) {
    final n = _activeFilterCount;
    final active = n > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          PressableScale(
            pressedScale: 0.96,
            onTap: () => _openFilterSheet(context, data),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: active ? MotoGoColors.greenDark : Colors.white,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                border: Border.all(
                  color: active ? MotoGoColors.greenDark : MotoGoColors.g200,
                  width: 1.5,
                ),
                boxShadow: active ? MotoGoShadows.cardSmall : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 16, color: active ? Colors.white : MotoGoColors.greenDark),
                  const SizedBox(width: 7),
                  Text(
                    t(context).tr('routesFilter'),
                    style: TextStyle(
                      fontSize: MotoGoTypo.sizeLg,
                      fontWeight: MotoGoTypo.w800,
                      color: active ? Colors.white : MotoGoColors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                      ),
                      child: Text(
                        '$n',
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeSm,
                          fontWeight: MotoGoTypo.w800,
                          color: Colors.white,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),
          if (active)
            GestureDetector(
              onTap: _clearFilters,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close, size: 15, color: MotoGoColors.g500),
                    const SizedBox(width: 3),
                    Text(
                      t(context).tr('routesFilterClear'),
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeBase,
                        fontWeight: MotoGoTypo.w700,
                        color: MotoGoColors.g500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          const Text('🔍', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
            t(context).tr('routesFilterEmpty'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeLg,
              fontWeight: MotoGoTypo.w700,
              color: MotoGoColors.g500,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 14),
          PressableScale(
            pressedScale: 0.96,
            onTap: _clearFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              ),
              child: Text(
                t(context).tr('routesFilterClear'),
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w800,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom sheet se všemi filtry ──
  void _openFilterSheet(BuildContext context, RoutesData data) {
    // Základ pro náhled počtu = trasy aktuálně zvolené pobočky.
    final base = data.routes;

    // Meze posuvníků z dat.
    final dists = base.map((r) => r.distanceKm).whereType<double>().toList()..sort();
    final hasDist = dists.length >= 2 && dists.first < dists.last;
    final dMin = hasDist ? dists.first.floorToDouble() : 0.0;
    final dMax = hasDist ? dists.last.ceilToDouble() : 0.0;

    final durs = base.map((r) => r.durationMin).whereType<int>().toList()..sort();
    final hasDur = durs.length >= 2 && durs.first < durs.last;
    final tMin = hasDur ? durs.first.toDouble() : 0.0;
    final tMax = hasDur ? durs.last.toDouble() : 0.0;

    // Země přítomné v datech.
    final countryCodes = <String>{for (final r in base) ...r.countries}.toList()..sort();
    final anyAbroad = base.any((r) => r.isAbroad);

    // Pracovní kopie (potvrdí se tlačítkem).
    final tType = {..._fType};
    final tDiff = {..._fDiff};
    final tCountry = {..._fCountry};
    var tDist = _fDist;
    var tDur = _fDur;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final count = base
                .where((r) => _routeMatches(r, tType, tDiff, tCountry, tDist, tDur))
                .length;
            void toggle(Set<String> s, String v) =>
                setSheet(() => s.contains(v) ? s.remove(v) : s.add(v));

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Držadlo
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: MotoGoColors.g200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            t(sheetCtx).tr('routesFilterTitle'),
                            style: const TextStyle(
                              fontSize: MotoGoTypo.sizeH2,
                              fontWeight: MotoGoTypo.w900,
                              color: MotoGoColors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setSheet(() {
                              tType.clear();
                              tDiff.clear();
                              tCountry.clear();
                              tDist = null;
                              tDur = null;
                            }),
                            child: Text(
                              t(sheetCtx).tr('routesFilterClear'),
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeBase,
                                fontWeight: MotoGoTypo.w700,
                                color: MotoGoColors.greenDark,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                        children: [
                          // Typ trasy
                          _sheetSection(t(sheetCtx).tr('routesFilterType')),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _selChip('🔄 ${t(sheetCtx).tr('routeTypeLoop')}', tType.contains('loop'),
                                () => toggle(tType, 'loop')),
                            _selChip('📍 ${t(sheetCtx).tr('routeTypePoi')}', tType.contains('poi'),
                                () => toggle(tType, 'poi')),
                          ]),
                          const SizedBox(height: 18),
                          // Obtížnost
                          _sheetSection(t(sheetCtx).tr('routesFilterDifficulty')),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _selChip('🟢 ${t(sheetCtx).tr('routeDiffEasy')}', tDiff.contains('easy'),
                                () => toggle(tDiff, 'easy')),
                            _selChip('🟠 ${t(sheetCtx).tr('routeDiffMedium')}', tDiff.contains('medium'),
                                () => toggle(tDiff, 'medium')),
                            _selChip('🔴 ${t(sheetCtx).tr('routeDiffHard')}', tDiff.contains('hard'),
                                () => toggle(tDiff, 'hard')),
                          ]),
                          // Délka
                          if (hasDist) ...[
                            const SizedBox(height: 18),
                            _sheetSection(
                                '${t(sheetCtx).tr('routesFilterDistance')}  ·  ${(tDist?.start ?? dMin).round()}–${(tDist?.end ?? dMax).round()} km'),
                            RangeSlider(
                              min: dMin,
                              max: dMax,
                              values: tDist ?? RangeValues(dMin, dMax),
                              activeColor: MotoGoColors.greenDark,
                              inactiveColor: MotoGoColors.g200,
                              labels: RangeLabels(
                                '${(tDist?.start ?? dMin).round()}',
                                '${(tDist?.end ?? dMax).round()}',
                              ),
                              onChanged: (v) => setSheet(() => tDist = v),
                            ),
                          ],
                          // Čas jízdy
                          if (hasDur) ...[
                            const SizedBox(height: 6),
                            _sheetSection(
                                '${t(sheetCtx).tr('routesFilterDuration')}  ·  ${_fmtDur((tDur?.start ?? tMin).round())}–${_fmtDur((tDur?.end ?? tMax).round())}'),
                            RangeSlider(
                              min: tMin,
                              max: tMax,
                              values: tDur ?? RangeValues(tMin, tMax),
                              activeColor: MotoGoColors.greenDark,
                              inactiveColor: MotoGoColors.g200,
                              labels: RangeLabels(
                                _fmtDur((tDur?.start ?? tMin).round()),
                                _fmtDur((tDur?.end ?? tMax).round()),
                              ),
                              onChanged: (v) => setSheet(() => tDur = v),
                            ),
                          ],
                          // Země
                          if (countryCodes.isNotEmpty || anyAbroad) ...[
                            const SizedBox(height: 18),
                            _sheetSection(t(sheetCtx).tr('routesFilterCountry')),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              if (anyAbroad)
                                _selChip('✈️ ${t(sheetCtx).tr('routesFilterAbroad')}',
                                    tCountry.contains(_kAbroad), () => toggle(tCountry, _kAbroad)),
                              ...countryCodes.map((c) =>
                                  _selChip(_countryLabel(c), tCountry.contains(c), () => toggle(tCountry, c))),
                            ]),
                          ],
                        ],
                      ),
                    ),
                    // Potvrzení
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                      child: PressableScale(
                        pressedScale: 0.98,
                        onTap: () {
                          setState(() {
                            _fType
                              ..clear()
                              ..addAll(tType);
                            _fDiff
                              ..clear()
                              ..addAll(tDiff);
                            _fCountry
                              ..clear()
                              ..addAll(tCountry);
                            // Plný rozsah = žádný filtr.
                            _fDist = (tDist == null || (tDist!.start <= dMin && tDist!.end >= dMax))
                                ? null
                                : tDist;
                            _fDur = (tDur == null || (tDur!.start <= tMin && tDur!.end >= tMax))
                                ? null
                                : tDur;
                          });
                          Navigator.of(sheetCtx).pop();
                        },
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: MotoGoColors.green,
                            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                            boxShadow: [
                              BoxShadow(
                                  color: MotoGoColors.green.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${t(sheetCtx).tr('routesFilterApply')} ($count)',
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeXl,
                                fontWeight: MotoGoTypo.w800,
                                color: MotoGoColors.black,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
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

  Widget _sheetSection(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: MotoGoTypo.sizeLg,
            fontWeight: MotoGoTypo.w900,
            color: MotoGoColors.black,
            decoration: TextDecoration.none,
          ),
        ),
      );

  Widget _selChip(String label, bool active, VoidCallback onTap) {
    return PressableScale(
      pressedScale: 0.94,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? MotoGoColors.greenDark : Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
          border: Border.all(
            color: active ? MotoGoColors.greenDark : MotoGoColors.g200,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: MotoGoTypo.sizeBase,
            fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
            color: active ? Colors.white : MotoGoColors.black,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  /// Vlaječka + kód země (jazykově neutrální).
  String _countryLabel(String code) {
    const flags = {
      'CZ': '🇨🇿', 'DE': '🇩🇪', 'AT': '🇦🇹', 'PL': '🇵🇱', 'SK': '🇸🇰',
      'HU': '🇭🇺', 'IT': '🇮🇹', 'CH': '🇨🇭', 'SI': '🇸🇮', 'HR': '🇭🇷',
      'FR': '🇫🇷', 'ES': '🇪🇸', 'PT': '🇵🇹', 'NL': '🇳🇱', 'BE': '🇧🇪',
      'LU': '🇱🇺', 'DK': '🇩🇰', 'SE': '🇸🇪', 'NO': '🇳🇴', 'FI': '🇫🇮',
      'GB': '🇬🇧', 'IE': '🇮🇪', 'RO': '🇷🇴', 'BG': '🇧🇬', 'RS': '🇷🇸',
      'GR': '🇬🇷', 'ME': '🇲🇪', 'BA': '🇧🇦', 'MK': '🇲🇰', 'AL': '🇦🇱',
      'AD': '🇦🇩', 'LI': '🇱🇮', 'IS': '🇮🇸', 'MD': '🇲🇩', 'LT': '🇱🇹',
      'LV': '🇱🇻', 'EE': '🇪🇪',
    };
    return '${flags[code] ?? '🏳️'} $code';
  }

  String _fmtDur(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Widget _emptyState(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Center(child: Text('🗺️', style: TextStyle(fontSize: 52))),
        const SizedBox(height: 14),
        Center(
          child: Text(
            t(context).tr('routesEmptyTitle'),
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeXl,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            t(context).tr('routesEmptySub'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeBase,
              color: MotoGoColors.g400,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState(BuildContext context, Object e) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Center(child: Icon(Icons.cloud_off, size: 48, color: MotoGoColors.g400)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            t(context).tr('routesError'),
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeXl,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: PressableScale(
            onTap: () => ref.invalidate(routesDataProvider),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              ),
              child: Text(
                t(context).tr('routesRetry'),
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w800,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Karta trasy — cover s gradientem, název, badge délka/čas/typ + počet POI.
class _RouteCard extends StatelessWidget {
  final RouteItem route;
  final RouteBranch? branch;
  final String lang;
  final VoidCallback onTap;

  const _RouteCard({
    required this.route,
    required this.branch,
    required this.lang,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cover = route.cover;
    return PressableScale(
      pressedScale: 0.97,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
          boxShadow: MotoGoShadows.motoCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    RouteImage(
                      url: cover,
                      targetWidth: 800,
                      placeholder: (_) => _coverFallback(),
                      error: (_) => _coverFallback(),
                    )
                  else
                    _coverFallback(),
                  // Gradient
                  DecoratedBox(
                    decoration: BoxDecoration(gradient: MotoGoGradients.imageOverlay),
                  ),
                  // Typ trasy badge
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _pill(
                      route.isLoop
                          ? '🔄 ${t(context).tr('routeTypeLoop')}'
                          : '📍 ${t(context).tr('routeTypePoi')}',
                      MotoGoColors.green,
                      MotoGoColors.black,
                    ),
                  ),
                  // Název + pobočka dole
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.nameFor(lang),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: MotoGoTypo.sizeH2,
                            fontWeight: MotoGoTypo.w900,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (branch != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.flag, size: 13, color: MotoGoColors.green),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    branch!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: MotoGoTypo.sizeMd,
                                      fontWeight: MotoGoTypo.w600,
                                      color: Colors.white70,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Meta řádek
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                children: [
                  if (route.distanceKm != null)
                    _meta(Icons.straighten, '${route.distanceKm!.toStringAsFixed(0)} km'),
                  if (route.durationMin != null)
                    _meta(Icons.schedule, _dur(route.durationMin!)),
                  if (route.pois.isNotEmpty)
                    _meta(Icons.place, '${route.pois.length} ${t(context).tr('routePoiShort')}'),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: MotoGoColors.greenDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dur(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  Widget _coverFallback() => Container(
        color: MotoGoColors.greenPale,
        child: const Center(child: Text('🛣️', style: TextStyle(fontSize: 40))),
      );

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
        child: Text(
          text,
          style: TextStyle(
            fontSize: MotoGoTypo.sizeMd,
            fontWeight: MotoGoTypo.w800,
            color: fg,
            decoration: TextDecoration.none,
          ),
        ),
      );

  Widget _meta(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: MotoGoColors.g400),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: MotoGoTypo.w700,
                color: MotoGoColors.g600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
}
