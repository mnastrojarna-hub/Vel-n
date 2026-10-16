import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show Distance, LengthUnit;

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/shell/shell_nav_map.dart' show V2TabOrigin, v2SetTabOrigin;
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_section.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../routes/routes_model.dart';
import '../../routes/routes_provider.dart';
import 'home_sketch.dart';
import 'home_ticket_parts.dart';
import 'home_reveal.dart';

const _dist = Distance();

/// "Vybrali jsme ti" (V22 §2.4 #10): 3 published routes, nearest to the
/// branch of the next / running booking (`pickupOriginProvider`) first —
/// photo + waypoint sketch, km · time · difficulty → route detail.
class HomeRoutesV2 extends ConsumerWidget {
  const HomeRoutesV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final async = ref.watch(routesDataProvider);
    final origin = ref.watch(pickupOriginProvider);
    final all = async.valueOrNull?.routes ?? const <RouteItem>[];
    double? away(RouteItem r) =>
        origin == null || r.waypoints.isEmpty ? null : _dist.as(LengthUnit.Kilometer, origin, r.waypoints.first);
    final sorted = [...all.where((r) => r.waypoints.length >= 2)];
    if (origin != null) {
      sorted.sort((a, b) => (away(a) ?? 1e9).compareTo(away(b) ?? 1e9));
    }
    final pick = sorted.take(3).toList();
    if (!async.isLoading && !async.hasError && pick.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgSectionHeader(
          eyebrow: tr.tr('v2HomeRoutesEyebrow'),
          title: tr.tr(origin == null ? 'v2HomeRoutesPopular' : 'v2HomeRoutesNear'),
          trailingLabel: tr.tr('v2HomeRoutesAll'),
          onTrailing: () {
            // Trasy ukážou „‹ Domů" (V22 §6.2).
            v2SetTabOrigin(ref, const V2TabOrigin(tab: 3, route: Routes.home, labelKey: 'v2TabHome'));
            GoRouter.maybeOf(context)?.push(Routes.routesList);
          },
        ),
        if (async.hasError && !async.hasValue)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MgErrorView(
              error: async.error,
              what: tr.tr('v2HomeRoutesFail'),
              compact: true,
              onRetry: () => ref.invalidate(routesDataProvider),
            ),
          )
        else
          SizedBox(
            height: 272,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: pick.isEmpty ? 3 : pick.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => pick.isEmpty
                  ? const _RouteSkeleton()
                  : HomeReveal(
                      index: i,
                      sessionKey: 'home-routes',
                      child: _RouteCard(
                        route: pick[i],
                        km: away(pick[i]),
                        onTap: () => homePushRoute(context, pick[i].id, [for (final r in pick) r.id]),
                      ),
                    ),
            ),
          ),
      ]),
    );
  }
}

String homeDuration(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

class _RouteCard extends StatelessWidget {
  final RouteItem route;
  final double? km;
  final VoidCallback onTap;
  const _RouteCard({required this.route, required this.km, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final name = route.nameFor(tr.lang);
    final chips = <(String, Color, Color)>[
      if (route.distanceKm != null) ('${route.distanceKm!.round()} km', MgColors.well, MgColors.body2),
      if (route.durationMin != null) (homeDuration(route.durationMin!), MgColors.well, MgColors.body2),
      if (route.difficulty == 'easy') (tr.tr('routeDiffEasy'), MgColors.tintOk, MgColors.link),
      if (route.difficulty == 'medium') (tr.tr('routeDiffMedium'), MgColors.warnBg, MgColors.warn),
      if (route.difficulty == 'hard') (tr.tr('routeDiffHard'), MgColors.errBg, MgColors.err),
    ];
    return Semantics(
      button: true,
      label: '$name, ${chips.map((c) => c.$1).join(', ')}',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: onTap,
        child: Container(
          width: 296,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
            boxShadow: MgShadows.card,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 120,
              child: Stack(fit: StackFit.expand, children: [
                HomePhoto(url: route.coverImage ?? (route.images.isEmpty ? null : route.images.first), thumbWidth: 600, glyph: false),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MgColors.nightA(0.2), MgColors.nightA(0.62)],
                    ),
                  ),
                ),
                HomeSketch(points: route.waypoints, width: 296, height: 120, tile: false, stroke: 3),
                if (km != null)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: MgColors.nightA(0.8), borderRadius: BorderRadius.circular(999)),
                      child: Center(
                        widthFactor: 1,
                        child: Text(tr.trArgs('v2HomeRouteDist', {'km': NumberFormat(km! < 10 ? '0.0' : '0', tr.lang).format(km)}),
                            style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 40,
                  child: Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.title.copyWith(height: 1.3, color: MgColors.ink)),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in chips)
                    Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: c.$2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: MgColors.line),
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Text(c.$1, style: MgType.micro.copyWith(color: c.$3)),
                      ),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RouteSkeleton extends StatelessWidget {
  const _RouteSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        width: 296,
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgSkeleton(height: 120, radius: 0),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgSkeleton(width: 200, height: 14),
              SizedBox(height: 8),
              MgSkeleton(width: 140, height: 14),
            ]),
          ),
        ]),
      );
}
