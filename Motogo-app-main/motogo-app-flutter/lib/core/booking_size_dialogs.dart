import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';

// ═══════════════════════════════════════════════════════════════════
// BOOKING SIZE / GEAR PICKER DIALOGS
// Extracted from booking_form_widget.dart to keep file sizes manageable.
// ═══════════════════════════════════════════════════════════════════

/// Passenger gear picker — helma, rukavice, bunda, kalhoty.
/// Boots are NOT selected here — they are a separate paid extra
/// ("Boty spolujezdce") to avoid asking for passenger boot size twice.
/// Calls [onExtrasUpdated] with the updated extras list after confirm.
void showPassengerGearSheet(
  BuildContext ctx,
  ExtraCatalogItem item,
  WidgetRef ref,
  void Function(List<SelectedExtra>) onExtrasUpdated,
) {
  final sizes = <String, String?>{
    'Helma': null, 'Rukavice': null, 'Bunda': null, 'Kalhoty': null,
  };
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => StatefulBuilder(
      builder: (c, ss) {
        final allSelected = sizes.values.every((v) => v != null);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20,
            MediaQuery.of(c).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: const Color(0xFFD4E8E0),
              borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text('Velikosti – ${item.name}',
              style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Boty spolujezdce se vybírají samostatně.',
              style: TextStyle(fontSize: 11, color: Color(0xFF8AAB99))),
            const SizedBox(height: 14),
            ...sizes.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(e.key, style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6,
                    children: gearSizes.map((s) {
                      final a = sizes[e.key] == s;
                      return GestureDetector(
                        onTap: () => ss(() =>
                          sizes[e.key] = a ? null : s),
                        child: Container(
                          width: 40, height: 32,
                          decoration: BoxDecoration(
                            color: a ? const Color(0xFF1A8A18)
                                : const Color(0xFFE8FFE8),
                            borderRadius: BorderRadius.circular(6)),
                          child: Center(child: Text(s,
                            style: TextStyle(fontSize: 11,
                              fontWeight: a ? FontWeight.w900
                                  : FontWeight.w600,
                              color: a ? Colors.black
                                  : const Color(0xFF0F1A14))))));
                    }).toList()),
                ]));
            }),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: allSelected ? () {
                  final sizeStr = sizes.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join(', ');
                  final ne = List<SelectedExtra>.from(
                    ref.read(bookingDraftProvider).extras);
                  ne.removeWhere((e) => e.id == item.id);
                  ne.add(SelectedExtra(id: item.id,
                    name: item.name, price: item.price,
                    size: sizeStr));
                  onExtrasUpdated(ne);
                  Navigator.pop(c);
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF74FB71),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: const Color(0xFFD4E8E0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50))),
                child: Text(allSelected
                    ? 'POTVRDIT'
                    : 'VYBERTE VŠECHNY VELIKOSTI',
                  style: const TextStyle(fontWeight: FontWeight.w800)))),
          ]));
      })),
  );
}

/// Single-item size picker (e.g. boot size for extras).
/// Calls [onExtrasUpdated] with the updated extras list after selection.
void showSizeDialog(
  BuildContext ctx,
  ExtraCatalogItem item,
  WidgetRef ref,
  void Function(List<SelectedExtra>) onExtrasUpdated,
) {
  showModalBottomSheet(
    context: ctx,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(20))),
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20,
        MediaQuery.of(c).padding.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(
          color: const Color(0xFFD4E8E0),
          borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Text('Vyberte velikost – ${item.name}',
          style: const TextStyle(fontSize: 15,
            fontWeight: FontWeight.w800)),
        if (item.description != null) ...[
          const SizedBox(height: 4),
          Text(item.description!,
            style: const TextStyle(fontSize: 12,
              color: Color(0xFF8AAB99))),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8,
          children: item.sizes.map((size) =>
            GestureDetector(
              onTap: () {
                final ne = List<SelectedExtra>.from(
                  ref.read(bookingDraftProvider).extras);
                ne.removeWhere((e) => e.id == item.id);
                ne.add(SelectedExtra(id: item.id,
                  name: item.name, price: item.price,
                  size: size));
                onExtrasUpdated(ne);
                Navigator.pop(c);
              },
              child: Container(width: 52, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FFE8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF74FB71),
                    width: 1.5)),
                child: Center(child: Text(size,
                  style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800)))),
            )).toList()),
      ])),
  );
}
