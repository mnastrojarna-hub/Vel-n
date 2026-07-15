import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/moto_fx.dart';
import 'routes_model.dart';
import 'routes_provider.dart' show CustomNavArgs;
import 'route_image.dart';
import 'my_experiences_provider.dart';

/// „Moje zážitky" — osobní cestovní deník jezdce: vlastní uložené trasy
/// (Moje trasy) a místa objevená navigací (Moje místa) + statistiky.
class MyExperiencesScreen extends ConsumerStatefulWidget {
  const MyExperiencesScreen({super.key});

  @override
  ConsumerState<MyExperiencesScreen> createState() => _MyExperiencesScreenState();
}

class _MyExperiencesScreenState extends ConsumerState<MyExperiencesScreen> {
  int _tab = 0; // 0 = Moje trasy, 1 = Moje místa

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
            if (!loggedIn)
              Expanded(child: _loginPrompt(context))
            else ...[
              _tabBar(context),
              Expanded(
                child: RefreshIndicator(
                  color: MotoGoColors.greenDark,
                  onRefresh: () async {
                    ref.invalidate(mySavedRoutesProvider);
                    ref.invalidate(myPlacesProvider);
                  },
                  child: _tab == 0
                      ? _routesList(context, routes)
                      : _placesList(context, places),
                ),
              ),
            ],
          ],
        ),
      ),
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
                _statChip('📍', '${placeCount ?? 0}', t(context).tr('myExpStatsPlaces')),
                const SizedBox(width: 10),
                _statChip('🗺️', '${routeCount ?? 0}', t(context).tr('myExpStatsRoutes')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String emoji, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
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
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: MotoGoTypo.w600,
                            color: Color(0xFF8AAB99),
                            decoration: TextDecoration.none)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _tabBar(BuildContext context) {
    Widget tabBtn(int i, String emoji, String label) {
      final active = _tab == i;
      return Expanded(
        child: PressableScale(
          pressedScale: 0.96,
          onTap: () => setState(() => _tab = i),
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
            child: Text(
              '$emoji $label',
              style: TextStyle(
                fontSize: MotoGoTypo.sizeLg,
                fontWeight: MotoGoTypo.w800,
                color: active ? Colors.white : MotoGoColors.black,
                decoration: TextDecoration.none,
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
          const SizedBox(width: 10),
          tabBtn(1, '📍', t(context).tr('myExpPlacesTab')),
        ],
      ),
    );
  }

  // ── Moje trasy ──
  Widget _routesList(BuildContext context, AsyncValue<List<SavedRoute>> async) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.greenDark)),
      error: (_, __) => _empty(context, '🗺️', 'myExpEmptyRoutes', 'myExpEmptyRoutesSub'),
      data: (routes) {
        if (routes.isEmpty) {
          return _empty(context, '🗺️', 'myExpEmptyRoutes', 'myExpEmptyRoutesSub');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          itemCount: routes.length,
          itemBuilder: (c, i) => _routeCard(context, routes[i]),
        );
      },
    );
  }

  Widget _routeCard(BuildContext context, SavedRoute r) {
    return Container(
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

  Widget _placeCard(BuildContext context, VisitedPlace p) {
    return Container(
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
    );
  }

  void _navigateToPlace(BuildContext context, VisitedPlace p) {
    final ll = p.latLng;
    if (ll == null) return;
    final poi = RoutePoi(
      id: p.routePoiId ?? p.userPoiId ?? p.poiId ?? '',
      name: p.name,
      lat: p.lat,
      lng: p.lng,
      imageUrl: p.imageUrl,
      isUserPoi: p.userPoiId != null,
      isCatalogPoi: p.poiId != null,
    );
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
    return ListView(
      children: [
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
      ],
    );
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
