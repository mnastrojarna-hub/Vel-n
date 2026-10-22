import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/my_vouchers.dart';
import 'i18n/i18n_provider.dart';
import 'currency.dart';
import 'v2/flag/v2_scope.dart';
import '../features/booking/v2/sections/promo_v2.dart';

/// Promo/discount-code entry section inside the booking form.
/// NO TextField in main tree — uses showDialog (AlertDialog has own Material).
class BookingFormPromoSection extends StatelessWidget {
  const BookingFormPromoSection({
    super.key,
    required this.draft,
    required this.onUpd,
  });

  final BookingDraft draft;
  final void Function(BookingDraft Function(BookingDraft) fn) onUpd;

  /// Dialog slevového kódu. [autoCode] = poukaz zvolený klepnutím (v2 karta)
  /// → dialog ho rovnou uplatní stejnou cestou jako napsaný kód.
  void _openPromoDialog(BuildContext context, {String? autoCode}) {
    final ctrl = TextEditingController(text: autoCode ?? '');
    String? error;
    bool loading = false;
    var autoDone = autoCode == null;

    // Jedno uplatnění pro tlačítko „Použít“, Enter i poukaz jedním klepnutím.
    // Ochrana `loading`: bez ní dvojí Enter spustil dvě souběžné validace
    // a fixní sleva (voucher) se přičetla dvakrát.
    Future<void> apply(BuildContext ctx, StateSetter ss) async {
      if (loading) return;
      final code = ctrl.text.trim();
      if (code.isEmpty) return;
      if (draft.discounts.any((d) => d.code == code.toUpperCase())) {
        ss(() => error = t(context).tr('promoAlreadyUsed').replaceAll('{code}', code));
        return;
      }
      ss(() { loading = true; error = null; });
      final result = await validateAndApplyCode(code);
      if (!ctx.mounted) return;
      ss(() => loading = false);
      if (result.success && result.discount != null) {
        final d = result.discount!;
        if (d.type == DiscountType.percent &&
            draft.discounts.any((x) => x.type == DiscountType.percent)) {
          ss(() => error = t(context).tr('promoNoCombinePercent'));
          return;
        }
        onUpd((dr) => dr.copyWith(discounts: [...dr.discounts, d]));
        Navigator.pop(ctx);
      } else {
        ss(() => error = result.message(t(context).tr));
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          if (!autoDone) {
            autoDone = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => apply(ctx, ss));
          }
          return AlertDialog(
          title: Text(t(context).tr('discountCode'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Vlastní dárkové poukazy jedním klepnutím (2026-10-22).
              Consumer(
                builder: (_, ref, __) => MyVoucherChips(
                  vouchers: unusedVouchers(ref.watch(myVouchersProvider).valueOrNull,
                      draft.discounts.map((d) => d.code)),
                  busy: loading,
                  onUse: (code) {
                    ctrl.text = code;
                    apply(ctx, ss);
                  },
                ),
              ),
              TextField(
                controller: ctrl,
                autofocus: autoCode == null,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => apply(ctx, ss),
                decoration: InputDecoration(
                  hintText: t(context).tr('enterCodeHint'),
                  hintMaxLines: 2,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFEF4444))),
                ),
            ],
          ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t(context).tr('cancel'))),
            ElevatedButton(
              onPressed: loading ? null : () => apply(ctx, ss),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A2E22),
                  foregroundColor: Colors.white),
              child: loading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(t(context).tr('apply').toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        );
        },
      ),
    );
  }

  /// Odebrání uplatněného kódu (sdílí starý i v2 vzhled; tělo beze změny).
  void _removeCode(AppliedDiscount d) => onUpd((dr) => dr.copyWith(
        discounts: dr.discounts
            .where((x) => x.code != d.code)
            .toList(),
      ));

  @override
  Widget build(BuildContext context) {
    // v2 vzhled (kill-switch app_v2_ui): stejný dialog i odebrání kódu.
    if (MgV2.on(context)) {
      return Consumer(
        builder: (context, ref, _) => BookingPromoV2(
          discounts: draft.discounts,
          onOpen: () => _openPromoDialog(context),
          onRemove: _removeCode,
          vouchers: unusedVouchers(ref.watch(myVouchersProvider).valueOrNull,
              draft.discounts.map((d) => d.code)),
          onVoucher: (code) => _openPromoDialog(context, autoCode: code),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.local_offer,
                  size: 16, color: Color(0xFF1A2E22)),
              const SizedBox(width: 6),
              Text(
                t(context).tr('promoCodeSection'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2E22),
                  decoration: TextDecoration.none,
                ),
              ),
            ]),
            const SizedBox(height: 10),

            // Tap to open dialog — NO TextField in main tree
            GestureDetector(
              onTap: () => _openPromoDialog(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFD4E8E0), width: 1.5),
                ),
                child: Row(children: [
                  const Icon(Icons.add_circle_outline,
                      size: 16, color: Color(0xFF8AAB99)),
                  const SizedBox(width: 8),
                  Text(
                    t(context).tr('clickEnterCode'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8AAB99),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ]),
              ),
            ),

            // Applied codes
            if (draft.discounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...draft.discounts.map((d) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8FFE8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle,
                          size: 14, color: Color(0xFF1A8A18)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          d.type == DiscountType.percent
                              ? '${d.code} (−${d.value.toStringAsFixed(0)}%)'
                              : '${d.code} (−${Money.czk(d.calculatedAmount > 0 ? d.calculatedAmount : d.value)})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A8A18),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _removeCode(d),
                        child: const Icon(Icons.close,
                            size: 16, color: Color(0xFF8AAB99)),
                      ),
                    ]),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
