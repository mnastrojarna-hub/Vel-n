import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../route_image.dart';
import '../routes_model.dart';
import 'place_card_v2.dart';
import 'route_card_v2.dart';
import 'rt_v2_text.dart';

/// Section title on light: dark icon tile + title + optional count badge.
class RtSectionV2 extends StatelessWidget {
  final String icon;
  final String title;
  final int? count;
  const RtSectionV2({super.key, required this.icon, required this.title, this.count});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(children: [
          MgIconTileDark(icon, size: 36),
          const SizedBox(width: 12),
          Flexible(child: Semantics(header: true, child: Text(title, style: MgType.section.copyWith(color: MgColors.ink)))),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: MgColors.panel, borderRadius: BorderRadius.circular(999)),
              child: Text('$count', style: MgType.tab(MgType.meta.copyWith(color: MgColors.neon))),
            ),
          ],
        ]),
      );
}

/// The ONE dark block of the detail (board TrasaDetail `.st`): type pill,
/// sibling pager, name, start branch, 2 × 2 stat tiles, "Od tebe" and ★.
class RouteStatsCardV2 extends StatelessWidget {
  final RouteItem route;
  final String name;
  final String? startLine;
  final String? km;
  final String? time;
  final String? fromMe;
  final (int, int)? sibling;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const RouteStatsCardV2({
    super.key,
    required this.route,
    required this.name,
    required this.startLine,
    required this.km,
    required this.time,
    required this.fromMe,
    required this.sibling,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final tiles = <(String, String, String)>[
      if (km != null) (MgIcons.ruler, km!, tr.tr('v2RtStatLength')),
      if (time != null) (MgIcons.clock, time!, tr.tr('v2RtStatTime')),
      if (route.difficulty != null) (MgIcons.mount, rtDifficulty(tr, route.difficulty!), tr.tr('v2RtStatDiff')),
      if (route.pois.isNotEmpty) (MgIcons.pin, '${route.pois.length}', tr.tr('routePoiShort')),
    ];
    final sib = sibling;
    return MgDarkHero(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          RouteTypePillV2(loop: route.isLoop),
          const Spacer(),
          if (sib != null) ...[
            MgIconButton(icon: MgIcons.chevronLeft, onTap: sib.$1 > 1 ? onPrev : null, semanticLabel: tr.tr('v2RtPrev'), size: 40),
            Text('${sib.$1} / ${sib.$2}', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark))),
            MgIconButton(icon: MgIcons.chevronRight, onTap: sib.$1 < sib.$2 ? onNext : null, semanticLabel: tr.tr('v2RtNext'), size: 40),
          ],
        ]),
        const SizedBox(height: 10),
        Semantics(header: true, child: Text(name, style: MgType.h2.copyWith(color: MgColors.onDark))),
        if (startLine != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const MgIcon(MgIcons.flag, size: 15, color: MgColors.neon),
            const SizedBox(width: 6),
            Flexible(child: Text(startLine!, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead))),
          ]),
        ],
        if (tiles.isNotEmpty) ...[
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 8) / 2;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final x in tiles) SizedBox(width: w, child: _StatTile(icon: x.$1, value: x.$2, label: x.$3)),
            ]);
          }),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (fromMe != null) _GlassChip(icon: MgIcons.navigate, label: fromMe!),
          if (route.reviewCount > 0)
            _GlassChip(
              icon: MgIcons.starFilled,
              iconColor: MgColors.star,
              label: '${(route.reviewAvg ?? 0).toStringAsFixed(1)} (${route.reviewCount})',
            ),
        ]),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String icon;
  final String value;
  final String label;
  const _StatTile({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MgColors.white(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MgColors.white(0.10)),
          ),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: MgColors.neonA(0.12), borderRadius: BorderRadius.circular(10)),
              child: Center(child: MgIcon(icon, size: 18, color: MgColors.neon)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: MgType.tab(MgType.title.copyWith(color: MgColors.onDark))),
                Text(label, maxLines: 2, style: MgType.meta.copyWith(color: MgColors.onDarkMeta)),
              ]),
            ),
          ]),
        ),
      );
}

class _GlassChip extends StatelessWidget {
  final String icon;
  final String label;
  final Color? iconColor;
  const _GlassChip({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: MgColors.white(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.white(0.14)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MgIcon(icon, size: 15, color: iconColor ?? MgColors.neon),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)))),
        ]),
      );
}

/// Description with 3 lines + Více / Méně (display only).
class RouteDescV2 extends StatefulWidget {
  final String text;
  const RouteDescV2(this.text, {super.key});

  @override
  State<RouteDescV2> createState() => _RouteDescV2State();
}

class _RouteDescV2State extends State<RouteDescV2> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final style = MgType.body.copyWith(color: MgColors.body2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: LayoutBuilder(builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: DefaultTextStyle.of(context).style.merge(style)),
          maxLines: 3,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: c.maxWidth);
        final long = tp.didExceedMaxLines;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgAnimatedSize(
            duration: MgMotion.sheet,
            alignment: Alignment.topCenter,
            child: Text(widget.text, maxLines: _open ? null : 3, overflow: _open ? null : TextOverflow.ellipsis, style: style),
          ),
          if (long)
            MgBtnText(
              label: tr.tr(_open ? 'v2RtLess' : 'v2RtMore'),
              icon: _open ? MgIcons.chevronUp : MgIcons.chevronDown,
              onTap: () => setState(() => _open = !_open),
            ),
        ]);
      }),
    );
  }
}

/// Card of "Místa na trase" (photo, number, name, 2-line description).
class RoutePoiCardV2 extends StatelessWidget {
  final RoutePoi poi;
  final int number;
  final String lang;
  final bool active;
  final VoidCallback onTap;
  const RoutePoiCardV2({super.key, required this.poi, required this.number, required this.lang, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final desc = poi.descFor(lang) ?? '';
    final name = poi.nameFor(lang);
    return Semantics(
      button: true,
      selected: active,
      label: '$number. $name',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.97,
        onTap: onTap,
        child: AnimatedContainer(
          duration: MgMotion.of(context, MgMotion.color),
          width: 240,
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? MgColors.tintOkBorder : MgColors.line, width: active ? 2 : 1),
            boxShadow: MgShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 112,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (poi.cover != null)
                  RouteImage(
                    url: poi.cover!,
                    targetWidth: 500,
                    placeholder: (_) => PlaceThumbFallbackV2(poi: poi),
                    error: (_) => PlaceThumbFallbackV2(poi: poi),
                  )
                else
                  PlaceThumbFallbackV2(poi: poi),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: MgColors.panel,
                      shape: BoxShape.circle,
                      border: Border.all(color: MgColors.neon, width: 1.5),
                    ),
                    child: Center(
                      child: Text('$number', style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon))),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Flexible(
                      child: Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.small.copyWith(color: MgColors.lead)),
                    ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Gallery thumb (170 × 120) → the existing photo viewer.
class RouteGalleryThumbV2 extends StatelessWidget {
  final String url;
  final VoidCallback onTap;
  const RouteGalleryThumbV2({super.key, required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: t(context).tr('routeGalleryHeader'),
        excludeSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 170,
              height: 120,
              child: Stack(fit: StackFit.expand, children: [
                RouteImage(
                  url: url,
                  targetWidth: 400,
                  placeholder: (_) => const ColoredBox(color: MgColors.tintFeatureA),
                  error: (_) => const ColoredBox(
                    color: MgColors.tintFeatureA,
                    child: Center(child: MgIcon(MgIcons.image, size: 28, color: MgColors.link)),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: MgColors.nightA(0.7), shape: BoxShape.circle),
                    child: const Center(child: MgIcon(MgIcons.full, size: 15, color: MgColors.onDark)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}
