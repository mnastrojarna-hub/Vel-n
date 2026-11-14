import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../home/v2/home_sketch.dart';
import '../routes_model.dart';
import 'route_card_photos_v2.dart';
import 'route_road_sketch_v2.dart' show routeRoadLine;

/// Night panel with the route glyph (no photo / photo failed).
Widget rtCardFallback(BuildContext _) => Container(
      color: MgColors.panel,
      alignment: const Alignment(0, -0.3),
      child: const MgIcon(MgIcons.route, size: 56, color: MgColors.neon),
    );

/// "2 / 6" on a dark pill (the bikes' detail pill), the camera glyph.
class RtCountPill extends StatelessWidget {
  final int index;
  final int total;
  const RtCountPill({super.key, required this.index, required this.total});

  @override
  Widget build(BuildContext context) => Semantics(
        label: t(context).trArgs('rtListPhotoOf', {'n': index + 1, 'total': total}),
        excludeSemantics: true,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: MgColors.nightA(0.78),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.white(0.18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const MgIcon(MgIcons.camera, size: 15, color: MgColors.neon),
            const SizedBox(width: 6),
            Text('${index + 1} / $total',
                style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark, height: 1))),
          ]),
        ),
      );
}

/// The place of the photo on screen: a dark pill with the pin.
class RtPlacePill extends StatelessWidget {
  final String name;
  final double maxWidth;
  const RtPlacePill({super.key, required this.name, required this.maxWidth});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: MgColors.nightA(0.78), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const MgIcon(MgIcons.pin, size: 14, color: MgColors.neon),
            const SizedBox(width: 5),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDark, height: 1.2)),
            ),
          ]),
        ),
      );
}

/// The small road sketch on the cover (the owner's favourite): shown once
/// the road line exists; a tap opens the large preview page.
class RtSmallSketch extends ConsumerWidget {
  final RouteItem route;
  final VoidCallback onTap;

  /// Short phone: a smaller thumbnail (more of the photo stays visible).
  final bool compact;
  const RtSmallSketch({super.key, required this.route, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = routeRoadLine(ref, route);
    if (line.length < 2) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: t(context).tr('rtListPreview'),
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MgColors.white(0.3)),
            boxShadow: [BoxShadow(color: MgColors.black(0.35), blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: HomeSketch(points: line, width: compact ? 64 : 104, height: compact ? 52 : 76),
        ),
      ),
    );
  }
}

/// Page 2 of the pager: the LARGE road preview on the night panel.
class RtSketchPage extends ConsumerWidget {
  final RouteItem route;
  final double topInset;

  /// The label's distance under the status bar (below the "1 / n" pill).
  final double labelTop;

  /// The lower part covered by the caption: the sketch stays above it.
  final double bottom;
  const RtSketchPage(
      {super.key, required this.route, required this.topInset, required this.bottom, this.labelTop = 56});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = routeRoadLine(ref, route);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.6, -0.6),
          radius: 1.3,
          colors: [MgColors.glow, MgColors.panel, MgColors.night],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(28, topInset + labelTop, 28, bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t(context).tr('rtListPreview').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.neonText)),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => HomeSketch(
                key: ValueKey('rt-sketch-${route.id}-${line.length}'),
                points: line,
                width: c.maxWidth,
                height: c.maxHeight,
                tile: false,
                stroke: 3.4,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One of the two place tiles under the media: the photo, the place name;
/// [on] = that photo is on screen in the pager. A tap shows it there.
class RtPlaceTile extends StatelessWidget {
  final RtCardPhoto photo;
  final bool on;
  final VoidCallback onTap;
  const RtPlaceTile({super.key, required this.photo, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = photo.place?.name ?? '';
    return Semantics(
      button: true,
      selected: on,
      label: name,
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? MgColors.neon : MgColors.white(0.22), width: on ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            RtCardImage(url: photo.url, targetWidth: kRtCardTileWidth, fallback: rtCardFallback),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.3, 1],
                  colors: [MgColors.nightA(0), MgColors.nightA(0.9)],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MgType.micro.copyWith(color: MgColors.onDark, height: 1.2)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// km · time · places on the night card (neon glyphs).
class RtCardMeta extends StatelessWidget {
  final List<(String, String)> items;
  final Widget? trailing;
  const RtCardMeta({super.key, required this.items, this.trailing});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final m in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            MgIcon(m.$1, size: 16, color: MgColors.neon),
            const SizedBox(width: 5),
            Text(m.$2, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark))),
          ]),
        if (trailing != null) trailing!,
      ]);
}

/// "Detail trasy ›": the card's explicit open (the whole card opens too).
class RtOpenButton extends StatelessWidget {
  final String label;
  final String semantic;
  final VoidCallback onTap;
  const RtOpenButton({super.key, required this.label, required this.semantic, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
            decoration: BoxDecoration(
              color: MgColors.neon,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [BoxShadow(color: MgColors.neonA(0.3), blurRadius: 14, offset: const Offset(0, 3))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: MgWordFit(
                  child: Text(label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.onNeon, height: 1.15)),
                ),
              ),
              const SizedBox(width: 4),
              const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.onNeon),
            ]),
          ),
        ),
      );
}
