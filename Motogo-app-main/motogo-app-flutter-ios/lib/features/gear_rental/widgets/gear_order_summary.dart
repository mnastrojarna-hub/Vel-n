import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../booking/booking_ui_helpers.dart' show bookingPriceRow;
import '../gear_order_state.dart';
import '../gear_order_ui.dart';
import 'gear_order_branch.dart' show GearOldNote;

/// Souhrn (starý vzhled, web `renderSum`), chyba odeslání, zelené
/// tlačítko „Pokračovat k platbě“ a ujištění.
class GearOrderSummary extends StatelessWidget {
  final GearOrderState state;
  final VoidCallback onSubmit;
  const GearOrderSummary({super.key, required this.state, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lang = Localizations.localeOf(context).languageCode;
    final sum = state.summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Container(
          key: const ValueKey('gear-summary'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr.tr('groSumTitle'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 8),
            if (sum.empty)
              GearOldNote(tr.tr('groSumEmpty'), key: const ValueKey('gear-sum-empty'))
            else ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.place_outlined, size: 16, color: MotoGoColors.greenDarker),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(gearSumMeta(tr, state),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                ),
              ]),
              const SizedBox(height: 8),
              for (final l in sum.quote.lines)
                bookingPriceRow(
                  [l.label, GearSummary.lineSizes(l, state, (x) => gearLc(lang, x))].where((e) => e.isNotEmpty).join('  '),
                  '${sum.days} × ${gearMoney(l.perDay)}',
                ),
              if (sum.quote.save > 0)
                GearOldNote('✓ ${tr.trArgs('groSave', {'amount': gearMoney(sum.quote.save * sum.days)})}',
                    key: const ValueKey('gear-sum-save')),
              const Divider(color: MotoGoColors.g200),
              if (sum.voucher > 0) ...[
                bookingPriceRow(tr.tr('groTotal'), gearMoney(sum.full)),
                KeyedSubtree(
                  key: const ValueKey('gear-sum-voucher'),
                  child: bookingPriceRow(tr.trArgs('groVoucherLine', {'code': sum.voucherCode}), '−${gearMoney(sum.voucher)}',
                      color: MotoGoColors.greenDarker),
                ),
              ],
              Row(key: const ValueKey('gear-sum-total'), children: [
                Expanded(
                  child: Text(tr.tr(sum.voucher > 0 ? 'groToPay' : 'groTotal'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                ),
                Text(gearMoney(sum.pay),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
              ]),
              if (sum.warn != null) GearOldNote(sum.warn!.text(tr), key: const ValueKey('gear-sum-warn'), warn: true),
            ],
          ]),
        ),
      ),
      if (state.error != null)
        Container(
          key: const ValueKey('gear-error'),
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MotoGoColors.redBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MotoGoColors.red),
          ),
          child: Text(state.error!.text(tr),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.red)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            key: const ValueKey('gear-cta'),
            onPressed: state.busy ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: MotoGoColors.green,
              foregroundColor: Colors.black,
              disabledBackgroundColor: MotoGoColors.g200,
              disabledForegroundColor: MotoGoColors.g400,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: Text(tr.tr(state.busy ? 'groProcessing' : 'groCta'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
              if (!state.busy) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward, size: 18)],
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: GearOldNote('✓ ${tr.tr('groAssure')}'),
      ),
    ]);
  }
}
