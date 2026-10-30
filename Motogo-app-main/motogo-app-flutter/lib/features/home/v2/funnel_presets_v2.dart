import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'funnel_dates.dart';
import 'funnel_provider.dart';
import 'home_fit.dart';

/// "Kdy" row: 2 weekend presets + the 52 px calendar button. [dense] = a
/// low phone (< 700 dp): 6 px chip padding, so REZERVOVAT stays above the
/// bottom bar.
class FunnelPresets extends StatelessWidget {
  final FunnelSelection selection;
  final ValueChanged<int> onPreset;
  final VoidCallback onCalendar;
  final bool dense;
  const FunnelPresets(
      {super.key, required this.selection, required this.onPreset, required this.onCalendar, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final now = DateTime.now();
    final p = funnelPresets(now);
    final selected = selection.preset(now);
    final vPad = dense ? 6.0 : 8.0;
    Widget chip(int i, String label, FunnelRange r, TextStyle labelStyle, {double hPad = 8}) {
      final on = selected == i;
      // Vidět kompaktně bez dne v týdnu („16.–18. 10.", zalomí se jen za
      // pomlčkou — REZERVOVAT zůstane nad lištou); čtečka dostane celé dny.
      final dates = funnelRangeShort(tr, r.start, r.end);
      return Semantics(
        button: true,
        selected: on,
        label: '$label, ${tripShortDate(tr, r.start)} – ${tripShortDate(tr, r.end)}',
        excludeSemantics: true,
        child: MgPress(
          onTap: () => onPreset(i),
          child: AnimatedContainer(
            duration: MgMotion.of(context, MgMotion.color),
            constraints: BoxConstraints(minHeight: dense ? 52 : 56),
            padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
            decoration: BoxDecoration(
              color: on ? MgColors.neonA(0.12) : MgColors.white(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? MgColors.neon : MgColors.white(0.18), width: 1.5),
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                // Nízký telefon: dvouřádkový popisek s hustším řádkováním.
                MgWordFit(minScale: 0.85, child: Text(label, style: dense ? labelStyle.copyWith(height: 1.2) : labelStyle)),
                const SizedBox(height: 2),
                Text(dates, style: MgType.tab(MgType.meta.copyWith(color: MgColors.neonText))),
              ]),
              if (on)
                Positioned(
                  right: -6 - hPad,
                  top: -6 - vPad,
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
    Widget cal({required bool wide, double width = 52}) => MgFabAvoid(
          // Vlastní termín (vpravo dole, pod AI tlačítkem) = CTA zóna: AI
          // tlačítko ho nikdy nepřekryje (nakouknutí by zakrylo půlku).
          child: Semantics(
            button: true,
            selected: calOn,
            label: tr.tr('v2HomeFnOther'),
            excludeSemantics: true,
            child: MgPress(
              onTap: onCalendar,
              child: Container(
                width: wide ? null : width,
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
      // 52px kalendář) → menší písmo → užší (6px okraje, 44px kalendář —
      // pořád v řádku, 320 dp) → 2 předvolby na celou šířku a „Jiný
      // termín" pod nimi → předvolby pod sebou. Měří se při skutečné
      // velikosti písma (textScaler), ne jen při 100 %.
      final scaler = MediaQuery.textScalerOf(context);
      final base = MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark);
      final small = base.copyWith(fontSize: 11);
      final probe = DefaultTextStyle.of(context).style;
      bool fit(TextStyle s, double w) =>
          homeWordsFit(l1, probe.merge(s), w, scaler) && homeWordsFit(l2, probe.merge(s), w, scaler);
      double w3(double calW, double hPad) => (c.maxWidth - 8 - 8 - calW) / 2 - 2 * hPad - 3;
      final w2 = (c.maxWidth - 8) / 2 - 16 - 3;
      Widget pair(TextStyle s) => IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: chip(0, l1, p.$1, s)),
              const SizedBox(width: 8),
              Expanded(child: chip(1, l2, p.$2, s)),
            ]),
          );
      // První varianta, kde se slova vejdou a popisek má nejvýš 2 řádky; na
      // nízkém telefonu (a když žádná nemá ≤ 2) ta s nejméně řádky (shoda =
      // větší písmo): „El siguiente fin de semana" na 320 dp 3 řádky, ne 4.
      final tiers = [(base, 52.0, 8.0), (small, 52.0, 8.0), (small, 44.0, 6.0)];
      int lines(TextStyle s, double w) {
        var n = 1;
        while (n < 6 && !(homeLinesFitIn(context, l1, s, w, n) && homeLinesFitIn(context, l2, s, w, n))) {
          n++;
        }
        return n;
      }

      (TextStyle, double, double)? pick;
      var best = 99;
      for (final t in tiers) {
        final w = w3(t.$2, t.$3);
        if (!fit(t.$1, w)) continue;
        final n = lines(t.$1, w);
        if (!dense && n <= 2) {
          pick = t;
          break;
        }
        if (n < best) (pick, best) = (t, n);
      }
      if (pick != null) {
        final (s, calW, hPad) = pick;
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: chip(0, l1, p.$1, s, hPad: hPad)),
            const SizedBox(width: 8),
            Expanded(child: chip(1, l2, p.$2, s, hPad: hPad)),
            const SizedBox(width: 8),
            cal(wide: false, width: calW),
          ]),
        );
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
