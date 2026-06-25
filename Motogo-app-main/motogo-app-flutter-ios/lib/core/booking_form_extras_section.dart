import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_ui_helpers.dart';
import 'booking_size_dialogs.dart';
import 'i18n/i18n_provider.dart';
import 'currency.dart';

/// Equipment & extras selector section inside the booking form.
class BookingFormExtrasSection extends ConsumerWidget {
  const BookingFormExtrasSection({
    super.key,
    required this.draft,
    required this.onUpd,
    this.isKids = false,
  });

  final BookingDraft draft;

  /// Dětská motorka (license_required='N') — bez spolujezdce, dětské velikosti.
  final bool isKids;

  /// Applies a mutation to the current [BookingDraft].
  final void Function(BookingDraft Function(BookingDraft) fn) onUpd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return bookingCard(
      6,
      t(context).tr('gearAndAddons'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8FFE8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.shield, size: 20, color: Color(0xFF1A8A18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(context).tr('basicGearFree'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A8A18),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      t(context).tr('basicGearList'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4A6357),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle, size: 18, color: Color(0xFF74FB71)),
            ]),
          ),
          // Velikosti základní výbavy zdarma se vybírají VŽDY (parita s webem),
          // ne jen při přistavení — i při vyzvednutí na pobočce.
          const SizedBox(height: 8),
          // Přepínač „Mám vlastní výbavu" — zákazník nemusí vybírat velikosti
          // základní výbavy zdarma. Při zapnutí vyčistíme dříve zvolené velikosti.
          bookingCheckbox(
            t(context).tr('ownGear'),
            draft.ownGear,
            (v) => onUpd((d) => d.copyWith(
                  ownGear: v,
                  helmetSize: v ? () => null : null,
                  glovesSize: v ? () => null : null,
                  jacketSize: v ? () => null : null,
                  pantsSize: v ? () => null : null,
                )),
          ),
          if (!draft.ownGear) ...[
            const SizedBox(height: 8),
            bookingGearRow(
              t(context).tr('helmet'),
              draft.helmetSize,
              (s) => onUpd((d) => d.copyWith(helmetSize: () => s)),
              sizes: gearSizesFor('helmet', kids: isKids),
            ),
            bookingGearRow(
              t(context).tr('gloves'),
              draft.glovesSize,
              (s) => onUpd((d) => d.copyWith(glovesSize: () => s)),
              sizes: gearSizesFor('gloves', kids: isKids),
            ),
            bookingGearRow(
              t(context).tr('jacket'),
              draft.jacketSize,
              (s) => onUpd((d) => d.copyWith(jacketSize: () => s)),
              sizes: gearSizesFor('jacket', kids: isKids),
            ),
            bookingGearRow(
              t(context).tr('pants'),
              draft.pantsSize,
              (s) => onUpd((d) => d.copyWith(pantsSize: () => s)),
              sizes: gearSizesFor('pants', kids: isKids),
            ),
          ],
          const SizedBox(height: 10),
          ...(isKids
                  ? defaultExtras.where((e) =>
                      e.id != 'extra-spolujezdec' &&
                      e.id != 'extra-boty-spolu')
                  : defaultExtras)
              .map((item) {
            final sel = draft.extras.any((e) => e.id == item.id);
            final selExtra =
                sel ? draft.extras.firstWhere((e) => e.id == item.id) : null;
            final isSpolujezdec = item.id == 'extra-spolujezdec';
            // Velikost se vybírá VŽDY (parita s webem), ne jen při přistavení.
            final needSize =
                sel && item.sizes.isNotEmpty && selExtra?.size == null;
            return GestureDetector(
              onTap: () {
                if (sel) {
                  final ne = List<SelectedExtra>.from(draft.extras);
                  ne.removeWhere((e) => e.id == item.id);
                  onUpd((d) => d.copyWith(extras: ne));
                } else if (isSpolujezdec) {
                  showPassengerGearSheet(context, item, ref,
                      (ne) => onUpd((d) => d.copyWith(extras: ne)));
                } else if (item.sizes.isNotEmpty) {
                  showSizeDialog(context, item, ref,
                      (ne) => onUpd((d) => d.copyWith(extras: ne)),
                      sizesOverride: gearSizesFor('boots', kids: isKids));
                } else {
                  final ne = List<SelectedExtra>.from(draft.extras);
                  ne.add(SelectedExtra(
                      id: item.id, name: item.name, price: item.price));
                  onUpd((d) => d.copyWith(extras: ne));
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      sel ? const Color(0xFFE8FFE8) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel
                        ? const Color(0xFF74FB71)
                        : const Color(0xFFD4E8E0),
                    width: sel ? 2 : 1,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: sel
                          ? const Color(0xFF74FB71)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFF74FB71)
                            : const Color(0xFFD4E8E0),
                        width: 2,
                      ),
                    ),
                    child: sel
                        ? const Icon(Icons.check,
                            size: 14, color: Colors.black)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text('${item.icon ?? ""} ',
                      style: const TextStyle(fontSize: 18)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Text(
                          sel && selExtra?.size != null
                              ? 'Velikost: ${selExtra!.size}'
                              : needSize
                                  ? '⚠ ${t(context).tr('clickSelectSize')}'
                                  : item.description ?? '',
                          style: TextStyle(
                            fontSize: 10,
                            color: needSize
                                ? const Color(0xFFD97706)
                                : const Color(0xFF8AAB99),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '+${Money.czk(item.price)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3DBA3A),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }
}
