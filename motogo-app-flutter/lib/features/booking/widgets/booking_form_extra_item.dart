import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../booking_models.dart';
import '../booking_provider.dart';

/// Checkbox-style extra equipment row for the booking form.
Widget buildBookingFormExtraItem(
  WidgetRef ref,
  String id,
  String icon,
  String name,
  String desc,
  double price,
  BookingDraft draft,
) {
  final selected = draft.extras.any((e) => e.id == id);
  return GestureDetector(
    onTap: () {
      final newExtras = List<SelectedExtra>.from(draft.extras);
      if (selected) {
        newExtras.removeWhere((e) => e.id == id);
      } else {
        newExtras.add(SelectedExtra(id: id, name: name, price: price));
      }
      ref.read(bookingDraftProvider.notifier).state = draft.copyWith(extras: newExtras);
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? MotoGoColors.greenPale : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? MotoGoColors.green : MotoGoColors.g200,
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: selected ? MotoGoColors.green : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? MotoGoColors.green : MotoGoColors.g200,
              width: 2,
            ),
          ),
          child: selected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
        ),
        const SizedBox(width: 10),
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            Text(desc, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
          ]),
        ),
        Text(
          '+${price.toStringAsFixed(0)} Kč',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark),
        ),
      ]),
    ),
  );
}
