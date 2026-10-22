import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../loyalty/loyalty_provider.dart';
import 'funnel_provider.dart';
import 'home_fit.dart';

/// Bike detail from Home (the same `/moto/:id` push the old list used).
void homePushMoto(BuildContext context, String id) => mgPushOrGo(context, '/moto/$id');

/// Eyebrow "TVOJE PŘÍŠTÍ JÍZDA" + pager ‹ 1 / n › (single-pointer
/// alternative to swiping; the eyebrow collapses to its icon then).
class FunnelTopRow extends ConsumerWidget {
  final int count;
  final int index;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const FunnelTopRow({super.key, required this.count, required this.index, this.onPrev, this.onNext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final pager = count > 1;
    final label = tr.tr('v2HomeFnEyebrow');
    Widget eb = Container(
      height: 28,
      padding: EdgeInsets.symmetric(horizontal: pager ? 0 : 10),
      width: pager ? 32 : null,
      decoration: BoxDecoration(
        color: MgColors.white(0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MgColors.white(0.12)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        MgIcon(MgIcons.route, size: 16, color: rank.accentOnDark),
        if (!pager) ...[
          const SizedBox(width: 6),
          // „TWÓJ NASTĘPNY PRZEJAZD" celé — raději menší než useknuté.
          Flexible(
            child: MgWordFit(
              minScale: 0.7,
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: MgType.eyebrow.copyWith(height: 1, color: rank.accentOnDark)),
            ),
          ),
        ],
      ]),
    );
    eb = Semantics(label: label, excludeSemantics: true, child: eb);
    return SizedBox(
      height: 36,
      child: Row(children: [
        if (pager) ...[
          eb,
          const Spacer(),
          _PagerBtn(icon: MgIcons.chevronLeft, label: tr.tr('v2HomeFnPrev'), onTap: onPrev),
          SizedBox(
            width: 48,
            child: Text('${index + 1} / $count',
                textAlign: TextAlign.center,
                style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDarkBody))),
          ),
          _PagerBtn(icon: MgIcons.chevronRight, label: tr.tr('v2HomeFnNext'), onTap: onNext),
        ] else
          Flexible(child: eb),
      ]),
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

/// Sub-line under the funnel title: your rank discount (+ free passenger
/// gear from Motorkář), or list prices + "Zkusit znovu" when loyalty failed.
class FunnelSubLine extends StatelessWidget {
  final bool loading;
  final LoyaltyStatus? loyalty;
  final VoidCallback onRetry;
  const FunnelSubLine({super.key, required this.loading, required this.loyalty, required this.onRetry});

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
    final text = l.level >= 3
        ? tr.trArgs('v2HomeFnSubGear', {'pct': l.percent})
        : tr.trArgs('v2HomeFnSub', {'pct': l.percent});
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: MgIcon(MgIcons.gift, size: 16, color: MgColors.neon),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: MgType.small.copyWith(color: MgColors.onDarkLead))),
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
    final txt = '${tripShortDate(tr, range.start)} → ${tripShortDate(tr, range.end)} · ${range.days} ${tr.daysWord(range.days)}';
    return MgEnter(
      child: Row(children: [
        const MgIcon(MgIcons.calendarCheck, size: 16, color: MgColors.neonText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(txt, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText))),
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

/// "Kdy" row: 2 weekend presets + the 52 px calendar button.
class FunnelPresets extends StatelessWidget {
  final FunnelSelection selection;
  final ValueChanged<int> onPreset;
  final VoidCallback onCalendar;
  const FunnelPresets({super.key, required this.selection, required this.onPreset, required this.onCalendar});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final now = DateTime.now();
    final p = funnelPresets(now);
    final selected = selection.preset(now);
    Widget chip(int i, String label, FunnelRange r, TextStyle labelStyle) {
      final on = selected == i;
      final dates = '${tripShortDate(tr, r.start)} – ${tripShortDate(tr, r.end)}';
      return Semantics(
        button: true,
        selected: on,
        label: '$label, $dates',
        excludeSemantics: true,
        child: MgPress(
          onTap: () => onPreset(i),
          child: AnimatedContainer(
            duration: MgMotion.of(context, MgMotion.color),
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: on ? MgColors.neonA(0.12) : MgColors.white(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? MgColors.neon : MgColors.white(0.18), width: 1.5),
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                MgWordFit(minScale: 0.85, child: Text(label, style: labelStyle)),
                const SizedBox(height: 2),
                Text(dates, style: MgType.tab(MgType.meta.copyWith(color: MgColors.neonText))),
              ]),
              if (on)
                Positioned(
                  right: -14,
                  top: -14,
                  child: MgPop(
                    playOnMount: true,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [MgColors.neonHi, MgColors.neonLo]),
                        border: Border.all(color: MgColors.night, width: 2),
                      ),
                      child: const Center(child: MgIcon(MgIcons.check, size: 11, color: MgColors.onNeon, stroke: 3)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
    }

    final calOn = selected == 2;
    final l1 = tr.tr('v2HomeFnPreset1'), l2 = tr.tr('v2HomeFnPreset2');
    Widget cal({required bool wide}) => MgFabAvoid(
          // Vlastní termín (vpravo dole, pod AI tlačítkem) = tap zóna.
          kind: MgAvoidKind.tap,
          child: Semantics(
            button: true,
            selected: calOn,
            label: tr.tr('v2HomeFnOther'),
            excludeSemantics: true,
            child: MgPress(
              onTap: onCalendar,
              child: Container(
                width: wide ? null : 52,
                constraints: BoxConstraints(minHeight: wide ? 48 : 0),
                padding: wide ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : null,
                decoration: BoxDecoration(
                  color: calOn ? MgColors.neonA(0.16) : MgColors.white(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: calOn ? MgColors.neon : MgColors.white(0.18), width: 1.5),
                ),
                child: wide
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const MgIcon(MgIcons.calendarCheck, size: 20, color: MgColors.neon),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(tr.tr('v2HomeFnOther'),
                              style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
                        ),
                      ])
                    : const Center(child: MgIcon(MgIcons.calendarCheck, size: 24, color: MgColors.neon)),
              ),
            ),
          ),
        );
    return LayoutBuilder(builder: (context, c) {
      // Slovo se NIKDY nedělí („Wochen|ende"): 3 vedle sebe (předvolby +
      // 52px kalendář) → menší písmo → 2 předvolby na celou šířku a „Jiný
      // termín" pod nimi → předvolby pod sebou. Měří se při skutečné
      // velikosti písma (textScaler), ne jen při 100 %.
      final scaler = MediaQuery.textScalerOf(context);
      final base = MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark);
      final small = base.copyWith(fontSize: 11);
      final probe = DefaultTextStyle.of(context).style;
      bool fit(TextStyle s, double w) =>
          homeWordsFit(l1, probe.merge(s), w, scaler) && homeWordsFit(l2, probe.merge(s), w, scaler);
      final w3 = (c.maxWidth - 8 - 8 - 52) / 2 - 16 - 3;
      final w2 = (c.maxWidth - 8) / 2 - 16 - 3;
      Widget pair(TextStyle s) => IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: chip(0, l1, p.$1, s)),
              const SizedBox(width: 8),
              Expanded(child: chip(1, l2, p.$2, s)),
            ]),
          );
      for (final s in [base, small]) {
        if (fit(s, w3)) {
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: chip(0, l1, p.$1, s)),
              const SizedBox(width: 8),
              Expanded(child: chip(1, l2, p.$2, s)),
              const SizedBox(width: 8),
              cal(wide: false),
            ]),
          );
        }
      }
      for (final s in [base, small]) {
        if (fit(s, w2)) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [pair(s), const SizedBox(height: 8), cal(wide: true)]);
        }
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        chip(0, l1, p.$1, base),
        const SizedBox(height: 8),
        chip(1, l2, p.$2, base),
        const SizedBox(height: 8),
        cal(wide: true),
      ]);
    });
  }
}
