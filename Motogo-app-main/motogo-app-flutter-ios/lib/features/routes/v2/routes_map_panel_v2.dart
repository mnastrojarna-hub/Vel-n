import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/gestures/mg_snap_physics.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Height of the v2 point panel (the map moves its round buttons above it):
/// 196 at text scale 1, growing with large text so nothing is cut.
double routesMapPanelV2Height(BuildContext context) =>
    196 + 140 * (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0.0, 1.0);

/// Card extent of the v2 panel (card 240 + gap 10) — snap + scroll-to.
const double kRoutesMapCardV2Extent = 250;

/// One card of the panel — values the old card computes (km from the road
/// line, time, difficulty, or "Počítám…" / "nepodařilo se").
class RtMapCardDataV2 {
  final String name;
  final String meta;
  /// The route's start branch name (old card: under the meta line).
  final String? sub;
  final Color color;
  final bool active;
  final VoidCallback onPick;
  final VoidCallback onOpen;
  const RtMapCardDataV2({
    required this.name,
    required this.meta,
    this.sub,
    required this.color,
    required this.active,
    required this.onPick,
    required this.onOpen,
  });
}

/// "Trasy přes vybraný bod · 3" (board TrasyHub "Mapa tras"): white sheet
/// r22 over the map, title 17/800 + "Klepni na trasu, kterou pojedeš",
/// horizontal 240 cards with the route's 4 px colour bar, name 15/800 (2
/// lines), meta 12.5/700, "Detail ›"; cards snap to whole cards. Tap =
/// the old pick (highlight on the map), "Detail ›" = the old open.
class RoutesMapPanelV2 extends StatelessWidget {
  final String title;
  final String hint;
  final List<RtMapCardDataV2> cards;
  final ScrollController controller;
  const RoutesMapPanelV2({super.key, required this.title, required this.hint, required this.cards, required this.controller});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: routesMapPanelV2Height(context),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: MgShadows.sheet,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    header: true,
                    child: Builder(builder: (context) {
                      // The route count after the last " · " never gets cut:
                      // only the words before it scale (≤ 75 %) / ellipsize.
                      final st = MgType.tab(MgType.section.copyWith(color: MgColors.ink));
                      final cut = title.lastIndexOf(' · ');
                      if (cut < 0) return MgWordFit(child: Text(title, maxLines: 1, style: st));
                      return Row(children: [
                        Flexible(
                          child: MgWordFit(
                            minScale: 0.75,
                            child: Text(title.substring(0, cut), maxLines: 1, overflow: TextOverflow.ellipsis, style: st),
                          ),
                        ),
                        Text(title.substring(cut).replaceAll(' ', '\u00A0'), maxLines: 1, softWrap: false, style: st),
                      ]);
                    }),
                  ),
                  Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.small.copyWith(color: MgColors.meta)),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  physics: const MgSnapScrollPhysics(itemExtent: kRoutesMapCardV2Extent),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _Card(cards[i]),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  final RtMapCardDataV2 d;
  const _Card(this.d);

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: d.active,
        label: d.sub == null ? '${d.name}, ${d.meta}' : '${d.name}, ${d.meta}, ${d.sub}',
        child: MgPress(
          onTap: d.onPick,
          child: Container(
            width: kRoutesMapCardV2Extent - 10,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: d.active ? d.color : MgColors.line, width: d.active ? 2 : 1),
              boxShadow: MgShadows.card,
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: d.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                    const SizedBox(height: 4),
                    // Whole meta line (km · time · difficulty): scales ≤ 80 %
                    // before an ellipsis would cut the difficulty.
                    MgWordFit(
                      minScale: 0.8,
                      child: Text(d.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta))),
                    ),
                    const Spacer(),
                    // Start branch (old card) beside "Detail ›" (board:
                    // chevron after the word, 44 px hit) — no extra height.
                    Row(children: [
                      Expanded(
                        child: d.sub == null
                            ? const SizedBox.shrink()
                            : Text(d.sub!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MgType.meta.copyWith(color: MgColors.meta)),
                      ),
                      Semantics(
                        button: true,
                        label: t(context).tr('routesMapDetail'),
                        excludeSemantics: true,
                        child: MgPress(
                          onTap: d.onOpen,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(t(context).tr('routesMapDetail'),
                                  style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                              const SizedBox(width: 2),
                              const MgIcon(MgIcons.chevronRight, size: 16, color: MgColors.link),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Dark glass tool chip of the map header (board "↝ Další trasa", "+
/// ostatní místa"): line icon neon, label 12.5/800 white, 44 px tall hit.
class MapToolChipV2 extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const MapToolChipV2({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: MgColors.white(0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.white(0.22)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MgIcon(icon, size: 16, color: MgColors.neon),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark))),
            ]),
          ),
        ),
      );
}
