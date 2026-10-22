import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../home/v2/home_sketch.dart';
import '../route_image.dart';
import '../routes_model.dart';
import 'rt_v2_text.dart';

/// Route type pill on photos / dark cards ("Okruh" / "Za místy").
class RouteTypePillV2 extends StatelessWidget {
  final bool loop;

  /// The label may wrap at a space (the pill sits in a bounded row).
  final bool wrap;
  const RouteTypePillV2({super.key, required this.loop, this.wrap = false});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final label = Text(tr.tr(loop ? 'routeTypeLoop' : 'routeTypePoi'),
        style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.onNeon));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: MgColors.neon, borderRadius: BorderRadius.circular(wrap ? 14 : 999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        MgIcon(loop ? MgIcons.loop : MgIcons.pin, size: 14, color: MgColors.onNeon),
        const SizedBox(width: 5),
        if (wrap) Flexible(child: MgWordFit(minScale: 0.7, child: label)) else label,
      ]),
    );
  }
}

/// Difficulty pill (easy = ✓ tint, medium = amber, hard = red tint).
class RouteDiffPillV2 extends StatelessWidget {
  final String difficulty;
  const RouteDiffPillV2({super.key, required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (difficulty) {
      'easy' => (MgColors.tintOk, MgColors.onTintOk),
      'hard' => (MgColors.errBg, MgColors.err),
      _ => (MgColors.warnBg, MgColors.warn),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(rtDifficulty(t(context), difficulty), style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/// Route card of the Trasy list (board TrasyHub): 16:9 cover + type pill
/// + waypoint sketch (drawn once) + name / start branch on the photo; white
/// body with km · time · places · difficulty, "Od tebe" and the ★ that
/// opens the existing reviews sheet. Same tap as the old card.
class RouteCardV2 extends StatelessWidget {
  final RouteItem route;
  final RouteBranch? branch;
  final String lang;
  final ({double km, int min})? approach;
  final VoidCallback onTap;
  final VoidCallback onReviews;

  const RouteCardV2({
    super.key,
    required this.route,
    required this.branch,
    required this.lang,
    required this.approach,
    required this.onTap,
    required this.onReviews,
  });

  Widget _fallback() => const ColoredBox(
        color: MgColors.panel,
        child: Center(child: MgIcon(MgIcons.route, size: 40, color: MgColors.neon)),
      );

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final cover = route.cover;
    final sketch = route.geometry.length >= 2 ? route.geometry : route.waypoints;
    final name = route.nameFor(lang);
    final meta = <(String, String)>[
      if (route.distanceKm != null) (MgIcons.ruler, '${route.distanceKm!.toStringAsFixed(0)} km'),
      if (route.durationMin != null) (MgIcons.clock, rtDur(route.durationMin!)),
      if (route.pois.isNotEmpty) (MgIcons.pin, '${route.pois.length} ${tr.tr('routePoiShort')}'),
    ];
    final fromMe = approach == null
        ? null
        : '${tr.tr('routeFromMe')} ~${approach!.km.round()} km · ~${rtDur(approach!.min)}';
    final rating = route.reviewCount > 0
        ? '${(route.reviewAvg ?? 0).toStringAsFixed(1)} (${route.reviewCount})'
        : '(0)';
    return Container(
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: [name, if (branch != null) branch!.name, ...meta.map((m) => m.$2), if (fromMe != null) fromMe].join(', '),
          excludeSemantics: true,
          child: MgPress(
            scale: 0.98,
            onTap: onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  if (cover != null)
                    RouteImage(url: cover, targetWidth: 800, placeholder: (_) => _fallback(), error: (_) => _fallback())
                  else
                    _fallback(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.35, 1],
                        colors: [MgColors.nightA(0), MgColors.nightA(0.85)],
                      ),
                    ),
                  ),
                  Positioned(top: 10, left: 10, child: RouteTypePillV2(loop: route.isLoop)),
                  if (sketch.length >= 2)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: MgColors.white(0.25)),
                        ),
                        child: HomeSketch(points: sketch, width: 104, height: 76),
                      ),
                    ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MgType.h3.copyWith(color: MgColors.onDark, height: 1.2)),
                      if (branch != null) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const MgIcon(MgIcons.flag, size: 14, color: MgColors.neon),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(branch!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
                          ),
                        ]),
                      ],
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final m in meta)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      MgIcon(m.$1, size: 16, color: MgColors.link),
                      const SizedBox(width: 5),
                      Text(m.$2, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
                    ]),
                  if (route.difficulty != null) RouteDiffPillV2(difficulty: route.difficulty!),
                ]),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 6),
          child: Row(children: [
            Expanded(
              child: fromMe == null
                  ? const SizedBox(height: 8)
                  : Row(children: [
                      const MgIcon(MgIcons.navigate, size: 15, color: MgColors.link),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(fromMe,
                            style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link))),
                      ),
                    ]),
            ),
            Semantics(
              button: true,
              label: '${tr.tr('routeReviewsHeader')}: $rating',
              excludeSemantics: true,
              child: MgPress(
                onTap: onReviews,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
                      MgIcon(route.reviewCount > 0 ? MgIcons.starFilled : MgIcons.star, size: 17, color: MgColors.star),
                      const SizedBox(width: 4),
                      Text(rating, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
