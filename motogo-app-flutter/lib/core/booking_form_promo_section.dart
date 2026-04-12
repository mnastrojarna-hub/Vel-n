import 'package:flutter/material.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_ui_helpers.dart';
import 'i18n/i18n_provider.dart';

/// Promo/discount-code entry section inside the booking form.
class BookingFormPromoSection extends StatelessWidget {
  const BookingFormPromoSection({
    super.key,
    required this.draft,
    required this.onUpd,
  });

  final BookingDraft draft;

  /// Applies a mutation to the current [BookingDraft].
  final void Function(BookingDraft Function(BookingDraft) fn) onUpd;

  @override
  Widget build(BuildContext context) {
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
              const Icon(Icons.local_offer, size: 16, color: Color(0xFF1A2E22)),
              const SizedBox(width: 6),
              Text(
                t(context).tr('promoCodeSection'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2E22),
                  decoration: TextDecoration.none,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => showPromoBottomSheet(
                context,
                draft.discounts,
                (d) => onUpd((dr) => dr.copyWith(
                      discounts: [...dr.discounts, d],
                    )),
                (code) => onUpd((dr) => dr.copyWith(
                      discounts: dr.discounts
                          .where((x) => x.code != code)
                          .toList(),
                    )),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFD4E8E0),
                    width: 1.5,
                  ),
                ),
                child: Row(children: [
                  const Icon(Icons.add_circle_outline,
                      size: 16, color: Color(0xFF8AAB99)),
                  const SizedBox(width: 8),
                  Text(
                    t(context).tr('clickEnterCode'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8AAB99),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ]),
              ),
            ),
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
                          d.code,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A8A18),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => onUpd((dr) => dr.copyWith(
                              discounts: dr.discounts
                                  .where((x) => x.code != d.code)
                                  .toList(),
                            )),
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
