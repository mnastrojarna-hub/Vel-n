import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/states/mg_tone_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../loyalty/loyalty_provider.dart';
import 'funnel_provider.dart';
import 'home_fit.dart';

export 'funnel_presets_v2.dart' show FunnelPresets;

/// Bike detail from Home (the same `/moto/:id` push the old list used).
void homePushMoto(BuildContext context, String id) => mgPushOrGo(context, '/moto/$id');

/// The Domů filter card (`MotoFilterPanel`), for the offer card's
/// "Filtry zapnuté (n)" pill to scroll to.
final homeFilterCardKey = GlobalKey(debugLabel: 'home-filter-card');

/// Scrolls Domů to its filter card (no-op when it is not built).
void homeShowFilterCard(BuildContext context) {
  final ctx = homeFilterCardKey.currentContext;
  if (ctx == null) return;
  Scrollable.ensureVisible(ctx, alignment: 0.1, duration: MgMotion.of(context, MgMotion.sheet), curve: MgMotion.out);
}

/// Eyebrow "TVOJE PŘÍŠTÍ JÍZDA" + pager ‹ 1 / n › (single-pointer
/// alternative to swiping). The full eyebrow stays beside the pager when
/// its label fits (≥ 85 % size); only on narrow screens / long languages
/// it disappears (never a bare icon pill). With real panel filters on
/// ([filters] > 0) a green "Filtry zapnuté (n)" pill takes its place (a tap
/// = [onFilters], the filter card); too narrow → the filter icon + n.
class FunnelTopRow extends ConsumerWidget {
  final int count;
  final int index;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// More bikes are still being checked: "1 / 6" + a spinning ring.
  final bool more;

  /// Real filters the offer follows (`HomeOffer.filters`).
  final int filters;
  final VoidCallback? onFilters;
  const FunnelTopRow(
      {super.key,
      required this.count,
      required this.index,
      this.onPrev,
      this.onNext,
      this.more = false,
      this.filters = 0,
      this.onFilters});

  /// Pager width (‹ 44 + "n / m" 48 + › 44) and the eyebrow's own chrome
  /// (padding 2 × 10, icon 16, gap 6, border 2).
  static const double _pagerW = 136, _ebChrome = 44, _gap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final pager = count > 1;
    final flt = filters > 0;
    final label = flt ? tr.trArgs('motoFltOn', {'n': filters}) : tr.tr('v2HomeFnEyebrow');
    final labelStyle = MgType.eyebrow.copyWith(height: 1, color: flt ? MgColors.onNeon : rank.accentOnDark);
    Widget eyebrow(bool full) {
      final pill = Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: full || flt ? 10 : 0),
        width: full || flt ? null : 32,
        decoration: BoxDecoration(
          color: flt ? MgColors.neon : MgColors.white(0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: flt ? MgColors.neon : MgColors.white(0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          MgIcon(flt ? MgIcons.filter : MgIcons.route, size: 16, color: flt ? MgColors.onNeon : rank.accentOnDark),
          if (flt && !full) ...[
            const SizedBox(width: 4),
            Text('$filters', style: MgType.tab(labelStyle.copyWith(fontWeight: FontWeight.w800))),
          ],
          if (full) ...[
            const SizedBox(width: 6),
            // „TWÓJ NASTĘPNY PRZEJAZD" celé — raději menší než useknuté.
            Flexible(
              child: MgWordFit(
                minScale: 0.7,
                child: Text(label.toUpperCase(),
                    maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: labelStyle),
              ),
            ),
          ],
        ]),
      );
      if (!flt) return Semantics(label: label, excludeSemantics: true, child: pill);
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onFilters,
        child: MgPress(key: const ValueKey('funnel-filters-on'), onTap: onFilters, child: pill),
      );
    }

    return SizedBox(
      height: 36,
      child: LayoutBuilder(builder: (context, c) {
        if (!pager) return Row(children: [Flexible(child: eyebrow(true))]);
        Widget short() => flt ? eyebrow(false) : const SizedBox.shrink();
        // Eyebrow smí na 70 % (jako jeho MgWordFit), než se schová do ikony (SH-21).
        final need =
            mgLineWidth(context, label.toUpperCase(), labelStyle) * 0.7 + _ebChrome + _gap + _pagerW + (more ? 18 : 0);
        final full = need <= c.maxWidth;
        return Row(children: [
          if (full)
            Flexible(child: Align(alignment: AlignmentDirectional.centerStart, child: eyebrow(true)))
          else
            short(),
          if (full) const SizedBox(width: _gap) else const Spacer(),
          _PagerBtn(icon: MgIcons.chevronLeft, label: tr.tr('v2HomeFnPrev'), onTap: onPrev),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            // Ještě se hledají další (v5.0.1): „1 / 6" + točící se kroužek,
            // ne nejasné „+".
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${index + 1} / $count',
                  key: const ValueKey('funnel-pager-count'),
                  textAlign: TextAlign.center,
                  style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDarkBody))),
              if (more) ...[
                const SizedBox(width: 6),
                MgTonePendingRing(
                  key: const ValueKey('funnel-pager-more'),
                  color: MgColors.neon,
                  size: 12,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, border: Border.all(color: MgColors.white(0.25), width: 2)),
                  ),
                ),
              ],
            ]),
          ),
          _PagerBtn(icon: MgIcons.chevronRight, label: tr.tr('v2HomeFnNext'), onTap: onNext),
        ]);
      }),
    );
  }
}

class _PagerBtn extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  const _PagerBtn({required this.icon, required this.label, this.onTap});

  @override
  // Tap zóna pro AI tlačítko (V2 §4.2): nad šipkou jen nakoukne, nesedí.
  Widget build(BuildContext context) => MgFabAvoid(
        kind: MgAvoidKind.tap,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: label,
          excludeSemantics: true,
          child: MgPress(
            scale: 0.9,
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Opacity(
                  opacity: onTap == null ? 0.35 : 1,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MgColors.white(0.10),
                      border: Border.all(color: MgColors.white(0.25)),
                    ),
                    child: Center(child: MgIcon(icon, size: 18, color: MgColors.onDark)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Funnel title "Kam vyrazíš příště, {nick}?": rather a bit smaller on
/// ONE line than on two (to 85 %, a low phone to 70 %), else two lines at
/// that scale, else it wraps at spaces — whole, never cut (REZERVOVAT stays
/// above the bottom bar).
class FunnelTitle extends StatelessWidget {
  final String text;
  final bool short;
  const FunnelTitle({super.key, required this.text, required this.short});

  @override
  Widget build(BuildContext context) {
    final h2 = MgType.h2.copyWith(color: MgColors.onDark);
    final min = short ? 0.7 : 0.85;
    return LayoutBuilder(builder: (context, c) {
      final one = homeLinesFitIn(context, text, h2.copyWith(fontSize: h2.fontSize! * min), c.maxWidth, 1);
      // Nízký telefon a dva řádky: o stupeň menší nadpis (h3), hustší řádky.
      final style = one || !short ? h2 : MgType.h3.copyWith(color: MgColors.onDark, height: 1.1);
      return MgWordFit(minScale: min, fitLines: one ? 1 : 2, child: Text(text, style: style));
    });
  }
}

/// Sub-line under the funnel title: your rank discount (+ free passenger
/// gear from Motorkář), or list prices + "Zkusit znovu" when loyalty failed.
/// [compact] = the discount only, kept to one line (a low phone, or the
/// header motto already says the gear is free).
class FunnelSubLine extends StatelessWidget {
  final bool loading;
  final LoyaltyStatus? loyalty;
  final bool compact;
  final VoidCallback onRetry;
  const FunnelSubLine(
      {super.key, required this.loading, required this.loyalty, required this.onRetry, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    if (loading) return const SizedBox(height: 4);
    final l = loyalty;
    if (l == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text(tr.tr('v2HomeFnSubNoLoyalty'), style: MgType.small.copyWith(color: MgColors.warnDark)),
          Semantics(
            button: true,
            child: MgPress(
              onTap: onRetry,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  child: Text(tr.tr('eoRetry'),
                      style: MgType.small.copyWith(
                          fontWeight: FontWeight.w800,
                          color: MgColors.neonText,
                          decoration: TextDecoration.underline,
                          decorationColor: MgColors.neonText)),
                ),
              ),
            ),
          ),
        ]),
      );
    }
    final text = l.level >= 3 && !compact
        ? tr.trArgs('v2HomeFnSubGear', {'pct': l.percent})
        : tr.trArgs('v2HomeFnSub', {'pct': l.percent});
    final style = MgType.small.copyWith(color: MgColors.onDarkLead);
    return Padding(
      padding: EdgeInsets.only(top: compact ? 2 : 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: MgIcon(MgIcons.gift, size: 16, color: MgColors.neon),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: compact
              ? MgWordFit(minScale: 0.88, fitLines: 1, child: Text(text, style: style))
              : Text(text, style: style),
        ),
      ]),
    );
  }
}

/// Custom range line "pá 30. 10. → so 31. 10. · 2 dny ✕".
class FunnelDateLine extends StatelessWidget {
  final FunnelRange range;
  final VoidCallback onClear;
  const FunnelDateLine({super.key, required this.range, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final txt =
        '${tripShortDate(tr, range.start)} → ${tripShortDate(tr, range.end)} · ${range.days} ${tr.daysWord(range.days)}';
    return MgEnter(
      child: Row(children: [
        const MgIcon(MgIcons.calendarCheck, size: 16, color: MgColors.neonText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(txt,
              style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText))),
        ),
        Semantics(
          button: true,
          label: tr.tr('v2HomeDateClear'),
          excludeSemantics: true,
          child: MgPress(
            onTap: onClear,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(child: MgIcon(MgIcons.close, size: 16, color: MgColors.onDarkLead)),
            ),
          ),
        ),
      ]),
    );
  }
}
