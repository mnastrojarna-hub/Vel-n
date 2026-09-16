import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/moto_fx.dart';
import 'active_ride_provider.dart';
import 'ride_card.dart';
import 'ride_model.dart';
import 'ride_provider.dart';
import 'ride_recorder.dart';
import 'routes_model.dart';
import 'routes_provider.dart' show CustomNavArgs;
import 'route_image.dart';
import 'my_experiences_provider.dart';
import 'route_poi_sheet.dart';

/// „Moje zážitky" — osobní cestovní deník jezdce: vlastní vytvořené trasy
/// (Vytvořené trasy), místa objevená navigací (Moje místa) a projeté jízdy
/// (Moje trasy) + statistiky. Záložky se přepínají tapem i swipem do stran,
/// klepnutí na statistiku v hlavičce otevře příslušnou záložku a klepnutí na
/// trasu / místo otevře jeho detail.
class MyExperiencesScreen extends ConsumerStatefulWidget {
  const MyExperiencesScreen({super.key});

  @override
  ConsumerState<MyExperiencesScreen> createState() => _MyExperiencesScreenState();
}

class _MyExperiencesScreenState extends ConsumerState<MyExperiencesScreen> {
  int _tab = 0; // 0 = Vytvořené trasy, 1 = Moje místa, 2 = Moje trasy (jízdy)
  final PageController _page = PageController();

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  /// Přepnutí záložky (tap na záložku / statistiku) — stránka se doanimuje.
  void _goTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    if (_page.hasClients) {
      _page.animateToPage(i,
          duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = MotoGoSupabase.currentUser != null;
    final routes = ref.watch(mySavedRoutesProvider);
    final places = ref.watch(myPlacesProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context, routes.valueOrNull?.length, places.valueOrNull?.length),
            _tabBar(context),
            Expanded(
              // Záložky jdou přepínat i swipem do stran. Historie jízd je
              // lokální (funguje i bez přihlášení); trasy a místa vyžadují účet.
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _tab = i),
                children: [
                  _accountPage(context, loggedIn, _routesList(context, routes)),
                  _accountPage(context, loggedIn, _placesList(context, places)),
                  _historyList(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Stránka vyžadující účet: bez přihlášení výzva k loginu, jinak obsah
  /// s obnovením tažením dolů.
  Widget _accountPage(BuildContext context, bool loggedIn, Widget child) {
    if (!loggedIn) return _loginPrompt(context);
    return RefreshIndicator(
      color: MotoGoColors.greenDark,
      onRefresh: () async {
        ref.invalidate(mySavedRoutesProvider);
        ref.invalidate(myPlacesProvider);
        ref.invalidate(myRidesProvider);
      },
      child: child,
    );
  }

  Widget _header(BuildContext context, int? routeCount, int? placeCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 18),
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
                onTap: () => context.backOr('/routes'),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(MotoGoRadius.lg),
                  ),
                  child: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏍️ ${t(context).tr('myExpTitle')}',
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeH1,
                        fontWeight: MotoGoTypo.w900,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t(context).tr('myExpSubtitle'),
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeBase,
                        fontWeight: MotoGoTypo.w600,
                        color: Color(0xFF8AAB99),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (routeCount != null || placeCount != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                // Statistiky jsou klikací — otevřou příslušnou záložku.
                _statChip('📍', '${placeCount ?? 0}', t(context).tr('myExpStatsPlaces'),
                    active: _tab == 1, onTap: () => _goTab(1)),
                const SizedBox(width: 10),
                _statChip('🗺️', '${routeCount ?? 0}', t(context).tr('myExpStatsRoutes'),
                    active: _tab == 0, onTap: () => _goTab(0)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String emoji, String value, String label,
          {bool active = false, required VoidCallback onTap}) =>
      Expanded(
        child: PressableScale(
          pressedScale: 0.96,
          onTap: onTap,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: active ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            border: Border.all(
                color: active ? MotoGoColors.green : Colors.transparent, width: 1.3),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: MotoGoTypo.sizeH3,
                            fontWeight: MotoGoTypo.w900,
                            color: Colors.white,
                            decoration: TextDecoration.none)),
                    Row(
                      children: [
                        Flexible(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: MotoGoTypo.w600,
                                  color: Color(0xFF8AAB99),
                                  decoration: TextDecoration.none)),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.chevron_right, size: 12, color: Color(0xFF8AAB99)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
      );

  Widget _tabBar(BuildContext context) {
    Widget tabBtn(int i, String emoji, String label) {
      final active = _tab == i;
      return Expanded(
        child: PressableScale(
          pressedScale: 0.96,
          onTap: () => _goTab(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? MotoGoColors.greenDark : Colors.white,
              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              border: Border.all(
                  color: active ? MotoGoColors.greenDark : MotoGoColors.g200, width: 1.5),
              boxShadow: active ? MotoGoShadows.cardSmall : null,
            ),
            // Delší popisek („Vytvořené trasy") se dřív lámal na dva řádky a
            // vylézal z pilulky — FittedBox ho zmenší, aby se vešel na jeden.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$emoji $label',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w800,
                  color: active ? Colors.white : MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          tabBtn(0, '🗺️', t(context).tr('myExpRoutesTab')),
          const SizedBox(width: 8),
          tabBtn(1, '📍', t(context).tr('myExpPlacesTab')),
          const SizedBox(width: 8),
          tabBtn(2, '🕘', t(context).tr('myExpHistoryTab')),
        ],
      ),
    );
  }

  // ── Historie jízd (lokální) — s tlačítkem „Pokračovat v trase" ──
  Widget _historyList(BuildContext context) {
    final st = ref.watch(activeRideProvider);
    final items = <ActiveRide>[if (st.active != null) st.active!, ...st.history];
    if (items.isEmpty) {
      return _empty(context, '🕘', 'myExpHistoryEmpty', 'myExpHistoryEmptySub');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      itemCount: items.length,
      itemBuilder: (c, i) => _historyCard(context, items[i],
          isActive: st.active != null && i == 0),
    );
  }

  /// Detail projeté jízdy: trasa z DB → detail trasy, vlastní trasa →
  /// náhled v editoru (mapa + zastávky).
  void _openRideDetail(BuildContext context, ActiveRide r) {
    final id = r.routeId;
    if (id != null && id.isNotEmpty) {
      context.push('/routes/$id');
      return;
    }
    final item = r.customRouteItem();
    if (item == null) return;
    context.push('/route-build',
        extra: RouteBuilderArgs(item, _stopsFromRoute(item)));
  }

  /// Zastávky pro editor z vlastní trasy — bodům zájmu se přiřadí
  /// odpovídající waypoint (≤ 40 m).
  List<BuilderStopSpec> _stopsFromRoute(RouteItem item) {
    const dist = Distance();
    final out = <BuilderStopSpec>[];
    for (final w in item.waypoints) {
      RoutePoi? best;
      var bd = 40.0;
      for (final p in item.pois) {
        final ll = p.latLng;
        if (ll == null) continue;
        final d = dist.as(LengthUnit.Meter, ll, w);
        if (d < bd) {
          bd = d;
          best = p;
        }
      }
      out.add(BuilderStopSpec(w, name: best?.name, poi: best));
    }
    return out;
  }

  Widget _historyCard(BuildContext context, ActiveRide r,
      {required bool isActive}) {
    final chipLabel = isActive
        ? t(context).tr('myExpRideActive')
        : (r.done ? t(context).tr('myExpRideDone') : null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openRideDetail(context, r),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.name.isNotEmpty ? r.name : t(context).tr('routeNavTitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeXl,
                      fontWeight: MotoGoTypo.w900,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none),
                ),
              ),
              if (chipLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive
                        ? MotoGoColors.green
                        : MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  ),
                  child: Text(
                    chipLabel,
                    style: TextStyle(
                        fontSize: MotoGoTypo.sizeSm,
                        fontWeight: MotoGoTypo.w800,
                        color: isActive
                            ? MotoGoColors.black
                            : MotoGoColors.greenDarker,
                        decoration: TextDecoration.none),
                  ),
                ),
              GestureDetector(
                onTap: () {
                  final n = ref.read(activeRideProvider.notifier);
                  if (isActive) {
                    n.endRide(); // aktivní → ukončit (spadne do historie)
                  } else {
                    n.removeFromHistory(r.id);
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline,
                      size: 20, color: Color(0xFFD93636)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _meta(Icons.event, _date(r.updatedAt)),
              if (r.totalStops > 0)
                _meta(Icons.place, '${r.reached.length}/${r.totalStops}'),
            ],
          ),
          const SizedBox(height: 12),
          _actionBtn(
            context,
            r.done && !isActive ? Icons.replay : Icons.navigation,
            t(context).tr(
                r.done && !isActive ? 'myExpRideAgain' : 'myExpContinueRoute'),
            primary: true,
            onTap: () {
              final n = ref.read(activeRideProvider.notifier);
              // „Jet znovu" = nová jízda od začátku; jinak pokračování.
              if (!isActive) n.resume(r, fresh: r.done);
              openRide(context, r);
            },
          ),
        ],
      ),
      ),
    );
  }

  // ── Moje trasy ──
  Widget _routesList(BuildContext context, AsyncValue<List<SavedRoute>> async) {
    final rides = ref.watch(myRidesProvider).valueOrNull ?? const <UserRide>[];
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.greenDark)),
      error: (_, __) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
        children: [
          _createRouteCard(context),
          ..._ridesSection(context, rides),
          ..._emptyChildren(context, '🗺️', 'myExpEmptyRoutes', 'myExpEmptyRoutesSub'),
        ],
      ),
      data: (routes) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
        children: [
          // Vždy viditelný vstup do editoru — odtud vzniká nová vlastní trasa.
          _createRouteCard(context),
          // Projeté jízdy zaznamenané při výpůjčce (jen s povolenou polohou).
          ..._ridesSection(context, rides),
          if (routes.isEmpty && rides.isEmpty)
            ..._emptyChildren(context, '🗺️', 'myExpEmptyRoutes', 'myExpEmptyRoutesSub')
          else
            ...routes.map((r) => _routeCard(context, r)),
        ],
      ),
    );
  }

  /// Sekce „Projeté jízdy" pod tlačítkem pro novou trasu: karty jízd s mapou
  /// (vznikají automaticky při výpůjčce) + přepínač automatického záznamu.
  /// Bez povolené polohy se místo karet ukáže vysvětlení, proč nic nevzniká.
  List<Widget> _ridesSection(BuildContext context, List<UserRide> rides) {
    final rec = ref.watch(rideRecorderProvider);
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '🛰️ ${t(context).tr('rideRecordTitle')}',
                          style: const TextStyle(
                              fontSize: MotoGoTypo.sizeLg,
                              fontWeight: MotoGoTypo.w800,
                              color: MotoGoColors.black,
                              decoration: TextDecoration.none),
                        ),
                        if (rec.recording) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: MotoGoColors.redBg,
                              borderRadius:
                                  BorderRadius.circular(MotoGoRadius.pill),
                            ),
                            child: Text(
                              '⏺ ${t(context).tr('rideRecording')}',
                              style: const TextStyle(
                                  fontSize: MotoGoTypo.sizeSm,
                                  fontWeight: MotoGoTypo.w800,
                                  color: MotoGoColors.red,
                                  decoration: TextDecoration.none),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t(context).tr('rideRecordHint'),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeMd,
                          fontWeight: MotoGoTypo.w600,
                          color: MotoGoColors.g500,
                          height: 1.35,
                          decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
              Switch(
                value: rec.enabled,
                activeColor: MotoGoColors.greenDark,
                onChanged: (v) =>
                    ref.read(rideRecorderProvider.notifier).setEnabled(v),
              ),
            ],
          ),
        ),
      ),
      for (final r in rides) RideCard(ride: r),
    ];
  }

  /// Výrazné tlačítko „Vytvořit novou trasu" → otevře editor s prázdnou
  /// trasou (klikáním do mapy / přidáním bodů zájmu si jezdec trasu poskládá
  /// a uloží ji záložkou 🔖).
  Widget _createRouteCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableScale(
        pressedScale: 0.97,
        onTap: () => context.push(
          '/route-build',
          extra: const RouteItem(id: 'custom', name: '', routeType: 'poi'),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: MotoGoColors.green,
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            boxShadow: [
              BoxShadow(
                  color: MotoGoColors.green.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: MotoGoColors.black.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_location_alt, size: 22, color: MotoGoColors.black),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(context).tr('myExpCreateRoute'),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeXl,
                          fontWeight: MotoGoTypo.w900,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t(context).tr('myExpCreateRouteSub'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: MotoGoTypo.sizeMd,
                          fontWeight: MotoGoTypo.w600,
                          color: MotoGoColors.black.withValues(alpha: 0.65),
                          decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 15, color: MotoGoColors.black),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeCard(BuildContext context, SavedRoute r) {
    // Tap na kartu = detail trasy (náhled v editoru s mapou a zastávkami).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(
        '/route-build',
        extra: RouteBuilderArgs(r.toRouteItem(), savedRouteStops(r), savedRouteId: r.id),
      ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeXl,
                      fontWeight: MotoGoTypo.w900,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none),
                ),
              ),
              GestureDetector(
                onTap: () => _confirmDelete(context, r),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, size: 20, color: Color(0xFFD93636)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (r.distanceKm != null)
                _meta(Icons.straighten, '${r.distanceKm!.toStringAsFixed(0)} km'),
              if (r.durationMin != null) _meta(Icons.schedule, _dur(r.durationMin!)),
              _meta(Icons.place, '${r.waypoints.length}× ${t(context).tr('routeBuilderStop').toLowerCase()}'),
              if (r.createdAt != null)
                _meta(Icons.event, _date(r.createdAt!)),
            ],
          ),
          if ((r.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeMd,
                  color: MotoGoColors.g500,
                  decoration: TextDecoration.none),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  context,
                  Icons.navigation,
                  t(context).tr('myExpNavigate'),
                  primary: true,
                  onTap: () => context.push(
                    '/route-nav-custom',
                    extra: CustomNavArgs(r.toRouteItem(), r.profile),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionBtn(
                  context,
                  Icons.edit_location_alt,
                  t(context).tr('myExpEdit'),
                  onTap: () => context.push(
                    '/route-build',
                    extra: RouteBuilderArgs(r.toRouteItem(), savedRouteStops(r),
                        savedRouteId: r.id),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SavedRoute r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(t(dc).tr('myExpDeleteConfirm'),
            style: const TextStyle(
                fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900)),
        content: Text(r.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: Text(t(dc).tr('routesFilterClear'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD93636),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dc, true),
            child: Text(t(dc).tr('myExpDelete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await deleteUserRoute(r.id);
    ref.invalidate(mySavedRoutesProvider);
  }

  // ── Moje místa ──
  Widget _placesList(BuildContext context, AsyncValue<List<VisitedPlace>> async) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.greenDark)),
      error: (_, __) => _empty(context, '📍', 'myExpEmptyPlaces', 'myExpEmptyPlacesSub'),
      data: (places) {
        if (places.isEmpty) {
          return _empty(context, '📍', 'myExpEmptyPlaces', 'myExpEmptyPlacesSub');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          itemCount: places.length,
          itemBuilder: (c, i) => _placeCard(context, places[i]),
        );
      },
    );
  }

  /// Bod zájmu z objeveného místa (pro detail i navigaci).
  RoutePoi _placePoi(VisitedPlace p) => RoutePoi(
        id: p.routePoiId ?? p.userPoiId ?? p.poiId ?? '',
        name: p.name,
        lat: p.lat,
        lng: p.lng,
        imageUrl: p.imageUrl,
        isUserPoi: p.userPoiId != null,
        isCatalogPoi: p.poiId != null,
      );

  Widget _placeCard(BuildContext context, VisitedPlace p) {
    final lang = ref.watch(localeProvider).languageCode;
    // Tap na kartu = detail místa (popis, fotky, hodnocení a komentáře).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showRoutePoiSheet(context, _placePoi(p), lang),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: p.imageUrl != null
                ? RouteImage(
                    url: p.imageUrl!,
                    targetWidth: 300,
                    placeholder: (_) => _imgFallback(),
                    error: (_) => _imgFallback(),
                  )
                : _imgFallback(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('✅', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: MotoGoTypo.sizeLg,
                              fontWeight: MotoGoTypo.w900,
                              color: MotoGoColors.black,
                              decoration: TextDecoration.none),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (p.routeName != null)
                    Text(
                      '🗺️ ${p.routeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeMd,
                          fontWeight: MotoGoTypo.w600,
                          color: MotoGoColors.g500,
                          decoration: TextDecoration.none),
                    ),
                  Text(
                    [
                      if (p.firstVisitedAt != null) _date(p.firstVisitedAt!),
                      if (p.visitCount > 1)
                        t(context).tr('myExpVisited').replaceFirst('{n}', '${p.visitCount}'),
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeMd,
                        fontWeight: MotoGoTypo.w600,
                        color: MotoGoColors.g400,
                        decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: p.latLng == null ? null : () => _navigateToPlace(context, p),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  shape: BoxShape.circle,
                  border: Border.all(color: MotoGoColors.green, width: 1.3),
                ),
                child: const Icon(Icons.navigation, size: 20, color: MotoGoColors.greenDarker),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _navigateToPlace(BuildContext context, VisitedPlace p) {
    final ll = p.latLng;
    if (ll == null) return;
    final poi = _placePoi(p);
    final route = RouteItem(
      id: 'custom',
      name: p.name,
      routeType: 'poi',
      waypoints: [LatLng(ll.latitude, ll.longitude)],
      pois: [poi],
    );
    context.push('/route-nav-custom', extra: CustomNavArgs(route, profileFromString(null)));
  }

  // ── Společné ──
  Widget _imgFallback() => Container(
        color: MotoGoColors.greenPale,
        child: const Center(child: Text('📍', style: TextStyle(fontSize: 26))),
      );

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MotoGoColors.g400),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeMd,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g600,
                  decoration: TextDecoration.none)),
        ],
      );

  Widget _actionBtn(BuildContext context, IconData icon, String label,
      {bool primary = false, required VoidCallback onTap}) {
    return PressableScale(
      pressedScale: 0.96,
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: primary ? MotoGoColors.green : MotoGoColors.greenPale,
          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
          border: primary ? null : Border.all(color: MotoGoColors.green, width: 1.3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16,
                color: primary ? MotoGoColors.black : MotoGoColors.greenDarker),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: MotoGoTypo.sizeLg,
                    fontWeight: MotoGoTypo.w800,
                    color: primary ? MotoGoColors.black : MotoGoColors.greenDarker,
                    decoration: TextDecoration.none),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, String emoji, String titleKey, String subKey) {
    return ListView(children: _emptyChildren(context, emoji, titleKey, subKey));
  }

  List<Widget> _emptyChildren(
      BuildContext context, String emoji, String titleKey, String subKey) {
    return [
      const SizedBox(height: 60),
      Center(child: Text(emoji, style: const TextStyle(fontSize: 48))),
      const SizedBox(height: 12),
      Center(
        child: Text(
          t(context).tr(titleKey),
          style: const TextStyle(
              fontSize: MotoGoTypo.sizeXl,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
              decoration: TextDecoration.none),
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          t(context).tr(subKey),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: MotoGoTypo.sizeBase,
              color: MotoGoColors.g400,
              decoration: TextDecoration.none),
        ),
      ),
    ];
  }

  Widget _loginPrompt(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔑', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              t(context).tr('myExpLogin'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeXl,
                  fontWeight: MotoGoTypo.w800,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none),
            ),
          ),
          const SizedBox(height: 16),
          PressableScale(
            onTap: () => context.push('/login'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              ),
              child: Text(
                t(context).tr('loginBtn'),
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeLg,
                    fontWeight: MotoGoTypo.w800,
                    color: MotoGoColors.black,
                    decoration: TextDecoration.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _dur(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  static String _date(DateTime d) => '${d.day}. ${d.month}. ${d.year}';
}
