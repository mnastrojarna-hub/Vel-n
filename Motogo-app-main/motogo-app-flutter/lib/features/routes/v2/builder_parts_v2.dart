import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_segmented.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../routes_provider.dart' show RouteProfile;

/// Dark gradient band over the top of the planner map: back + eyebrow +
/// route name (board TrasaDetail "Plánovač").
class BuilderTopBarV2 extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final bool computing;
  const BuilderTopBarV2({super.key, required this.title, required this.onBack, required this.computing});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(12, top + 8, 12, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MgColors.nightA(0.92), MgColors.nightA(0.55), MgColors.nightA(0)],
          stops: const [0, 0.65, 1],
        ),
      ),
      child: Row(children: [
        MgV2Back(onTap: onBack, style: MgBackStyle.photo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr.tr('v2RtBuilderEyebrow').toUpperCase(),
                style: MgType.eyebrow.copyWith(color: MgColors.neon)),
            const SizedBox(height: 2),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.onDark)),
          ]),
        ),
        if (computing)
          Semantics(
            label: tr.tr('routeNavComputing'),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: MgColors.nightA(0.8), shape: BoxShape.circle, border: Border.all(color: MgColors.white(0.25))),
              child: const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.neon),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Gesture hint pill over the bottom of a planner / submit map. The whole
/// hint is shown (wraps onto more lines on a narrow phone / large text; a
/// one-line hint stays a pill, more lines a rounded card).
class BuilderHintV2 extends StatelessWidget {
  final String text;
  const BuilderHintV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: MgShadows.icon,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const MgIcon(MgIcons.finger, size: 16, color: MgColors.link),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: MgType.meta.copyWith(color: MgColors.ink))),
        ]),
      );
}

/// Numbered stop pin (map marker and list badge).
class BuilderPinV2 extends StatelessWidget {
  final int n;
  final double size;
  const BuilderPinV2(this.n, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: MgColors.panel,
          shape: BoxShape.circle,
          border: Border.all(color: MgColors.neon, width: 2),
          boxShadow: [BoxShadow(color: MgColors.black(0.3), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Center(
          child: Text('$n', style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon, height: 1))),
        ),
      );
}

/// Stats card of the planner: km, time, stop count, profile segments.
class BuilderStatsV2 extends StatelessWidget {
  final String km;
  final String time;
  final String stops;
  final RouteProfile profile;
  final ValueChanged<RouteProfile> onProfile;
  const BuilderStatsV2({super.key, required this.km, required this.time, required this.stops, required this.profile, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget stat(String icon, String v) => Row(mainAxisSize: MainAxisSize.min, children: [
          MgIcon(icon, size: 18, color: MgColors.link),
          const SizedBox(width: 6),
          Text(v, style: MgType.tab(MgType.section.copyWith(color: MgColors.ink))),
        ]);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          stat(MgIcons.ruler, km),
          stat(MgIcons.clock, time),
          Text(stops, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
        ]),
        const SizedBox(height: 10),
        MgSegmented<RouteProfile>(
          value: profile,
          onChanged: onProfile,
          segments: [
            MgSegment(value: RouteProfile.recommended, label: tr.tr('routeProfileRecommended')),
            MgSegment(value: RouteProfile.fastest, label: tr.tr('routeProfileFastest')),
            MgSegment(value: RouteProfile.shortest, label: tr.tr('routeProfileShortest')),
          ],
        ),
      ]),
    );
  }
}

/// Header of the stop list: icon tile + title + count + "Přidat z bodů zájmu".
class BuilderStopsHeaderV2 extends StatelessWidget {
  final int count;
  final VoidCallback onAdd;
  const BuilderStopsHeaderV2({super.key, required this.count, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    // Title and button share a row while both fit; else the button goes on
    // its own line under the title (320 dp, large text, long languages).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
        Text('${tr.tr('routePoisHeader')} · $count', style: MgType.tab(MgType.section.copyWith(color: MgColors.ink))),
        Semantics(
          button: true,
          label: tr.tr('routeBuilderAddPoi'),
          excludeSemantics: true,
          child: MgPress(
            onTap: onAdd,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: MgColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MgColors.link, width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const MgIcon(MgIcons.pinPlus, size: 18, color: MgColors.link),
                const SizedBox(width: 6),
                // „Uit bezienswaardigheden“: wraps at the space; a word wider
                // than the button shrinks a little instead of splitting.
                Flexible(
                  child: MgWordFit(
                    minScale: 0.75,
                    child: Text(tr.tr('routeBuilderAddPoi'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// One stop row (white card): number, name, coordinates (as today), remove,
/// drag handle (the caller's `ReorderableDragStartListener`).
class BuilderStopTileV2 extends StatelessWidget {
  final int number;
  final String label;
  final String? sub;
  final VoidCallback onRemove;
  final Widget Function(Widget handle) wrapHandle;
  const BuilderStopTileV2({
    super.key,
    required this.number,
    required this.label,
    required this.sub,
    required this.onRemove,
    required this.wrapHandle,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Row(children: [
        BuilderPinV2(number, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
            if (sub != null) Text(sub!, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
          ]),
        ),
        Semantics(
          button: true,
          label: '${tr.tr('v2RtRemoveStop')}: $label',
          excludeSemantics: true,
          child: MgPress(
            onTap: onRemove,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(child: MgIcon(MgIcons.trash, size: 22, color: MgColors.err)),
            ),
          ),
        ),
        wrapHandle(Semantics(
          label: tr.tr('v2RtDragStop'),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: MgColors.well, borderRadius: BorderRadius.circular(12), border: Border.all(color: MgColors.line)),
            child: const Center(child: MgIcon(MgIcons.selector, size: 22, color: MgColors.lead)),
          ),
        )),
      ]),
    );
  }
}

/// Planner dock: Uložit (bookmark) · Navrhnout · NAVIGOVAT (rank CTA).
class BuilderDockV2 extends StatelessWidget {
  final bool canNav;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onSuggest;
  final VoidCallback onNavigate;
  const BuilderDockV2({
    super.key,
    required this.canNav,
    required this.canSave,
    required this.onSave,
    required this.onSuggest,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget ghost({required String icon, String? label, required String sem, required VoidCallback onTap}) => Semantics(
          button: true,
          enabled: canSave,
          label: sem,
          excludeSemantics: true,
          child: Tooltip(
            message: sem,
            triggerMode: TooltipTriggerMode.longPress,
            excludeFromSemantics: true,
            child: MgPress(
            onTap: onTap,
            child: Opacity(
              opacity: canSave ? 1 : 0.45,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56, minWidth: 52),
                padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
                decoration: BoxDecoration(
                  color: MgColors.white(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: MgColors.white(0.25)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  MgIcon(icon, size: 22, color: MgColors.onDark),
                  if (label != null) ...[
                    const SizedBox(width: 6),
                    Text(label, style: MgType.ctaCompact.copyWith(color: MgColors.onDark, letterSpacing: 0)),
                  ],
                ]),
              ),
            ),
          ),
          ),
        );
    return MgDock(
      child: Row(children: [
        ghost(icon: MgIcons.bookmark, sem: tr.tr('routeSaveTitle'), onTap: onSave),
        const SizedBox(width: 8),
        ghost(icon: MgIcons.send, sem: tr.tr('routeSuggestBtn'), onTap: onSuggest),
        const SizedBox(width: 8),
        Expanded(
          child: MgFabAvoid(
            child: MgCta(label: tr.tr('routeBuilderNavigate'), loop: true, enabled: canNav, onTap: onNavigate),
          ),
        ),
      ]),
    );
  }
}
