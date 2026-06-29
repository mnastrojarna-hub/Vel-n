import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'community_submit.dart';

/// Obrazovka „Trasy" — doporučené motorkářské trasy od poboček.
/// Nahrazuje tab E-shop ve spodní liště.
class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  String? _branchId; // null = vše

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
        ],
      ),
    );
  }

  Widget _body(BuildContext context, RoutesData data, String lang) {
    if (data.routes.isEmpty) return _emptyState(context);

    final branches = data.branchesWithRoutes;
    final routes = _branchId == null
        ? data.routes
        : data.routes.where((r) => r.branchId == _branchId).toList();

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
          // Filtr poboček
          if (branches.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  children: [
                    _branchChip(t(context).tr('routesAllBranches'), null),
                    ...branches.map((b) => _branchChip(b.name, b.id)),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
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

  Widget _branchChip(String label, String? id) {
    final active = _branchId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        pressedScale: 0.94,
        onTap: () => setState(() => _branchId = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
              fontSize: MotoGoTypo.sizeLg,
              fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
              color: active ? Colors.white : MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
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
                    Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _coverFallback(),
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
