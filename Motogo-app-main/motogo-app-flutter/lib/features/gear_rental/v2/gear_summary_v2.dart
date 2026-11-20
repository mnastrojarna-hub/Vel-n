import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/v2/booking_v2_parts.dart' show BkCard, bkNb, bkNbAmounts;
import '../gear_order_state.dart';
import '../gear_order_ui.dart';

/// Souhrn (web `renderSum`): pobočka · termín (dny), řádky „kusy ×
/// cena“, úspora kompletu, poukaz (Celkem / −poukaz / K úhradě),
/// varování serveru; pod ním chyba odeslání a ujištění webu.
class GearSummaryV2 extends StatelessWidget {
  final GearOrderState state;
  const GearSummaryV2({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lang = Localizations.localeOf(context).languageCode;
    final sum = state.summary;
    final rowStyle = MgType.small.copyWith(color: MgColors.body2);
    Widget money(String l, String v, {bool strong = false, Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(
                child: Text(l,
                    style: strong ? MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink) : rowStyle)),
            Text(bkNb(v),
                style: MgType.tab(strong
                    ? MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink)
                    : rowStyle.copyWith(fontWeight: FontWeight.w800))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BkCard(
        key: const ValueKey('gear-summary'),
        icon: MgIcons.receipt,
        title: tr.tr('groSumTitle'),
        child: sum.empty
            ? Text(tr.tr('groSumEmpty'), key: const ValueKey('gear-sum-empty'), style: rowStyle)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MgIcon(MgIcons.pin, size: 16, color: MgColors.link),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(gearSumMeta(tr, state),
                          style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
                ]),
                const SizedBox(height: 4),
                for (final l in sum.quote.lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: l.label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                          if (GearSummary.lineSizes(l, state, (x) => gearLc(lang, x)).isNotEmpty)
                            TextSpan(
                                text: '  ${GearSummary.lineSizes(l, state, (x) => gearLc(lang, x))}',
                                style: MgType.small.copyWith(color: MgColors.lead)),
                        ])),
                      ),
                      const SizedBox(width: 8),
                      Text(bkNbAmounts('${sum.days} × ${gearMoney(l.perDay)}'),
                          style: MgType.tab(rowStyle.copyWith(fontWeight: FontWeight.w700))),
                    ]),
                  ),
                if (sum.quote.save > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      MgIcon(MgIcons.check, size: 16, color: MgColors.link),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(tr.trArgs('groSave', {'amount': gearMoney(sum.quote.save * sum.days)}),
                            key: const ValueKey('gear-sum-save'),
                            style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.link)),
                      ),
                    ]),
                  ),
                const Divider(height: 18, color: MgColors.line),
                if (sum.voucher > 0) ...[
                  money(tr.tr('groTotal'), gearMoney(sum.full)),
                  money(tr.trArgs('groVoucherLine', {'code': sum.voucherCode}), '−${gearMoney(sum.voucher)}',
                      key: const ValueKey('gear-sum-voucher')),
                ],
                money(tr.tr(sum.voucher > 0 ? 'groToPay' : 'groTotal'), gearMoney(sum.pay),
                    strong: true, key: const ValueKey('gear-sum-total')),
                if (sum.warn != null) ...[
                  const SizedBox(height: 10),
                  MgStateBanner(key: const ValueKey('gear-sum-warn'), tone: MgTone.warn, title: sum.warn!.text(tr)),
                ],
              ]),
      ),
      if (state.error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: MgShake(
            trigger: state.error,
            child: MgStateBanner(key: const ValueKey('gear-error'), tone: MgTone.err, title: state.error!.text(tr)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgIcon(MgIcons.check, size: 16, color: MgColors.link),
          const SizedBox(width: 6),
          Expanded(child: Text(tr.tr('groAssure'), style: MgType.meta.copyWith(color: MgColors.meta))),
        ]),
      ),
    ]);
  }
}

/// Dok: k úhradě + „Pokračovat k platbě“ (při odesílání „Připravuji
/// platbu…“); chyba odeslání v řádku nad tlačítkem.
class GearDockV2 extends StatelessWidget {
  final GearOrderState state;
  final VoidCallback onSubmit;
  const GearDockV2({super.key, required this.state, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final sum = state.summary;
    final err = state.error;
    final line = err != null
        ? MgEnter(
            trigger: err,
            child: Row(children: [
              MgIcon(MgIcons.warn, size: 16, color: MgColors.warnDark),
              const SizedBox(width: 6),
              Flexible(
                child: MgWordFit(
                  child: Text(err.text(tr),
                      key: const ValueKey('gear-dock-error'),
                      maxLines: 3,
                      style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.warnDark)),
                ),
              ),
            ]),
          )
        : (sum.empty
            ? Text(tr.tr('groSumEmpty'), maxLines: 2, style: MgType.small.copyWith(color: MgColors.onDarkLead))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${tr.tr(sum.voucher > 0 ? 'groToPay' : 'groTotal')} · ${sum.days} ${tr.daysWord(sum.days)}',
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(bkNb(gearMoney(sum.pay)),
                      key: const ValueKey('gear-dock-price'),
                      maxLines: 1,
                      style: MgType.tab(MgType.section.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon))),
                ),
              ]));
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MgColors.night,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: MgDock(
        contextLine: line,
        child: MgFabAvoid(
          child: MgCta(
            key: const ValueKey('gear-cta'),
            label: tr.tr(state.busy ? 'groProcessing' : 'groCta'),
            arrow: !state.busy,
            busy: state.busy,
            onTap: state.busy ? null : onSubmit,
            size: MgCtaSize.lg60,
            loop: !state.busy && state.complete,
          ),
        ),
      ),
    );
  }
}
