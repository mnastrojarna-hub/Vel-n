import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_anim_loops.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_buttons.dart';
import 'trip_day_state.dart';

/// Month title 17/800 with ‹ › 44 px discs.
class TripCalendarHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final TripSkin skin;
  const TripCalendarHeader({super.key, required this.month, this.onPrev, this.onNext, this.skin = TripSkin.light});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dark = skin == TripSkin.dark;
    final style = dark ? MgIconButtonStyle.dark : MgIconButtonStyle.light;
    return Row(children: [
      Opacity(
        opacity: onPrev == null ? 0.35 : 1,
        child: MgIconButton(icon: MgIcons.chevronLeft, onTap: onPrev, semanticLabel: tr.tr('v2CalPrev'), style: style),
      ),
      Expanded(
        child: Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            tripMonthTitle(tr, month),
            textAlign: TextAlign.center,
            style: MgType.section.copyWith(color: dark ? MgColors.onDark : MgColors.ink),
          ),
        ),
      ),
      Opacity(
        opacity: onNext == null ? 0.35 : 1,
        child: MgIconButton(icon: MgIcons.chevronRight, onTap: onNext, semanticLabel: tr.tr('v2CalNext'), style: style),
      ),
    ]);
  }
}

/// Weekday header (Monday first): 11.5/800 caps, weekend green.
class TripWeekdays extends StatelessWidget {
  final TripSkin skin;
  const TripWeekdays({super.key, this.skin = TripSkin.light});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dark = skin == TripSkin.dark;
    return ExcludeSemantics(
      child: Row(children: [
        for (var i = 1; i <= 7; i++)
          Expanded(
            child: Center(
              child: Text(
                tr.tr('v2CalWd$i').toUpperCase(),
                style: MgType.eyebrow.copyWith(
                  letterSpacing: 0.3,
                  color: i >= 6
                      ? (dark ? MgColors.neonText : MgColors.link)
                      : (dark ? MgColors.onDarkMeta : MgColors.meta),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Legend entry kinds.
enum TripLegendKind { free, yours, busy, pending, other, added, removed }

/// Legend under the grid (12.5/600, 14 px swatches). Pass only the kinds
/// that occur.
class TripLegend extends StatelessWidget {
  final List<TripLegendKind> items;
  final TripSkin skin;
  const TripLegend({
    super.key,
    this.items = const [TripLegendKind.free, TripLegendKind.yours, TripLegendKind.busy, TripLegendKind.pending],
    this.skin = TripSkin.light,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dark = skin == TripSkin.dark;
    String label(TripLegendKind k) => tr.tr(switch (k) {
          TripLegendKind.free => 'v2CalLegFree',
          TripLegendKind.yours => 'v2CalLegYours',
          TripLegendKind.busy => 'v2CalLegBusy',
          TripLegendKind.pending => 'v2CalLegPending',
          TripLegendKind.other => 'v2CalLegOther',
          TripLegendKind.added => 'v2CalLegAdded',
          TripLegendKind.removed => 'v2CalLegRemoved',
        });
    Widget swatch(TripLegendKind k) {
      final (Color fill, Color border) = switch (k) {
        TripLegendKind.free => (dark ? MgColors.white(0.08) : MgColors.surface, dark ? MgColors.white(0.2) : MgColors.line),
        TripLegendKind.yours => (MgColors.calBand, dark ? MgColors.calBand : MgColors.calContour),
        TripLegendKind.busy => (dark ? MgColors.white(0.10) : MgColors.hatchA, dark ? MgColors.white(0.2) : MgColors.line),
        TripLegendKind.pending => (const Color(0x00000000), dark ? MgColors.warnDark : MgColors.pending),
        TripLegendKind.other => (dark ? MgColors.warnDarkBg : MgColors.warnBg, MgColors.warnBorder),
        TripLegendKind.added => (MgColors.calBand, MgColors.calContour),
        TripLegendKind.removed => (const Color(0x00000000), MgColors.err),
      };
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border, width: 1.5),
        ),
        child: k == TripLegendKind.added
            ? Center(child: Text('+', style: MgType.micro.copyWith(fontSize: 10, height: 1, color: MgColors.onNeon)))
            : null,
      );
    }

    return Wrap(spacing: 14, runSpacing: 8, children: [
      for (final k in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          swatch(k),
          const SizedBox(width: 6),
          Text(label(k), style: MgType.small.copyWith(color: dark ? MgColors.onDarkLead : MgColors.lead)),
        ]),
    ]);
  }
}

/// "Vyzvednutí pá 23. 10. → Vrácení ne 25. 10. · 3 dny" (the days chip in
/// btnInk style; bumps on change). [end] null = start only.
class TripSummaryRow extends StatelessWidget {
  final DateTime start;
  final DateTime? end;
  final int? days;
  final TripSkin skin;
  const TripSummaryRow({super.key, required this.start, this.end, this.days, this.skin = TripSkin.light});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dark = skin == TripSkin.dark;
    final lead = MgType.small.copyWith(color: dark ? MgColors.onDarkLead : MgColors.lead);
    final strong = MgType.small.copyWith(fontWeight: FontWeight.w800, color: dark ? MgColors.onDark : MgColors.ink);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: '${tr.tr('v2CalPickup')} ', style: lead),
          TextSpan(text: tripShortDate(tr, start), style: strong),
          if (end != null) ...[
            TextSpan(text: '  →  ${tr.tr('v2CalReturn')} ', style: lead),
            TextSpan(text: tripShortDate(tr, end!), style: strong),
          ],
        ])),
        if (days != null)
          MgBump(
            trigger: days,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: dark ? MgColors.neon : MgColors.ink,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${days!} ${tr.daysWord(days!)}',
                  style: MgType.tab(MgType.meta.copyWith(
                      fontWeight: FontWeight.w800, color: dark ? MgColors.onNeon : MgColors.onDark))),
            ),
          ),
      ],
    );
  }
}

/// Small note line (12.5/600 lead), e.g. `v2CalNote` or `v2CalPickEnd`.
class TripCalendarNote extends StatelessWidget {
  final String text;
  final TripSkin skin;
  final String? icon;
  const TripCalendarNote(this.text, {super.key, this.skin = TripSkin.light, this.icon});

  @override
  Widget build(BuildContext context) {
    final dark = skin == TripSkin.dark;
    final c = dark ? MgColors.onDarkLead : MgColors.lead;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[MgIcon(icon!, size: 16, color: c), const SizedBox(width: 6)],
      Expanded(child: Text(text, style: MgType.small.copyWith(color: c))),
    ]);
  }
}

/// Availability loading pill / error banner with a working retry. While
/// loading or failed the owner keeps the confirm disabled (never "all free").
class TripAvailabilityBanner extends StatelessWidget {
  final bool loading;
  final bool error;
  final VoidCallback? onRetry;
  final TripSkin skin;
  const TripAvailabilityBanner({
    super.key,
    this.loading = false,
    this.error = false,
    this.onRetry,
    this.skin = TripSkin.light,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dark = skin == TripSkin.dark;
    if (loading) {
      return Semantics(
        liveRegion: true,
        child: MgShimmer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: dark ? MgColors.white(0.08) : MgColors.well,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: dark ? MgColors.white(0.12) : MgColors.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: dark ? MgColors.neon : MgColors.link),
              ),
              const SizedBox(width: 8),
              Text(tr.tr('v2CalLoading'),
                  style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: dark ? MgColors.onDark : MgColors.ink)),
            ]),
          ),
        ),
      );
    }
    if (!error) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: dark ? MgColors.errDarkBg : MgColors.errBg,
          borderRadius: BorderRadius.circular(MgRadius.action),
          border: Border.all(color: dark ? MgColors.errDark : MgColors.errBorder),
        ),
        child: Row(children: [
          MgIcon(MgIcons.xCircle, size: 20, color: dark ? MgColors.errDark : MgColors.err),
          const SizedBox(width: MgSpace.s8),
          Expanded(
            child: Text(tr.tr('v2CalError'),
                style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: dark ? MgColors.onDark : MgColors.ink)),
          ),
          if (onRetry != null) MgBtnText(label: tr.tr('retry'), onTap: onRetry, dark: dark),
        ]),
      ),
    );
  }
}
