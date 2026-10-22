import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_provider.dart' show profileProvider;
import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/loyalty/loyalty_provider.dart';
import 'i18n/i18n_provider.dart';
import 'widgets/mg_nav_controls.dart';

// ═══════════════════════════════════════════════════════════════════
// BOOKING SIZE / GEAR PICKER DIALOGS
// Extracted from booking_form_widget.dart to keep file sizes manageable.
// ═══════════════════════════════════════════════════════════════════

/// Passenger gear picker — helma, rukavice, bunda, kalhoty.
/// Boots are NOT selected here — they are a separate paid extra
/// ("Boty spolujezdce") to avoid asking for passenger boot size twice.
/// Stačí vybrat ALESPOŇ JEDEN kus (zadání majitele 2026-09-28: spolujezdec
/// chce třeba jen helmu) — nevybrané kusy se neukládají (sloupec zůstane NULL).
/// Calls [onExtrasUpdated] with the updated extras list after confirm.
/// [selfService] = motorka na samoobslužné pobočce → užší řady velikostí.
/// Bez dvojího vybírání (2026-10-22): [current] = už zvolená výbava
/// spolujezdce → list otevře její velikosti + „Odebrat“ (dřív klepnutí
/// výbavu rovnou odebralo a velikosti se vybíraly znovu); nová výbava se
/// předvyplní z `profiles.gear_sizes.passenger` (minulá rezervace) — jen
/// velikosti z nabízené řady, potvrzuje se vždy tlačítkem.
void showPassengerGearSheet(
  BuildContext ctx,
  ExtraCatalogItem item,
  WidgetRef ref,
  void Function(List<SelectedExtra>) onExtrasUpdated, {
  bool selfService = false,
  SelectedExtra? current,
}) {
  final sizes = <String, String?>{
    'Helma': null, 'Rukavice': null, 'Bunda': null, 'Kalhoty': null,
  };
  final fromLast = _prefillPassenger(sizes, ref, current, selfService);
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => StatefulBuilder(
      builder: (c, ss) {
        final anySelected = sizes.values.any((v) => v != null);
        // Posouvatelné: 4 řady velikostí + nápověda + „Odebrat“ se při
        // velkém písmu na malý telefon nevejdou.
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20,
            MediaQuery.of(c).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const MgSheetHandle(),
            const SizedBox(height: 14),
            Text('${t(ctx).tr('sizesLabel')} – ${item.name}',
              style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(t(ctx).tr('passengerBootsSeparate'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF8AAB99))),
            if (fromLast) ...[
              const SizedBox(height: 6),
              Text(t(ctx).tr('bkSizesFromLast'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFF1A8A18))),
            ],
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
                    children: _passengerGearSizes(e.key, selfService).map((s) {
                      final a = sizes[e.key] == s;
                      return GestureDetector(
                        onTap: () => ss(() =>
                          sizes[e.key] = a ? null : s),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: a ? const Color(0xFF1A8A18)
                                : const Color(0xFFE8FFE8),
                            borderRadius: BorderRadius.circular(6)),
                          child: Text(s,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11,
                              fontWeight: a ? FontWeight.w900
                                  : FontWeight.w600,
                              color: a ? Colors.black
                                  : const Color(0xFF0F1A14)))));
                    }).toList()),
                ]));
            }),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: anySelected ? () {
                  // Jen zvolené kusy — payment_screen `_parsePassengerGearSizes`
                  // chybějící části tolerantně přeskočí (→ NULL v DB).
                  final sizeStr = sizes.entries
                      .where((e) => e.value != null)
                      .map((e) => '${e.key}: ${e.value}')
                      .join(', ');
                  final ne = List<SelectedExtra>.from(
                    ref.read(bookingDraftProvider).extras);
                  ne.removeWhere((e) => e.id == item.id);
                  // Od [loyaltyFreeGearLevel] je tento gear zdarma.
                  final lvl = ref
                      .read(loyaltyStatusProvider).valueOrNull?.level ?? 0;
                  ne.add(SelectedExtra(id: item.id,
                    name: item.name,
                    price: effectiveExtraPrice(item.id, item.price, lvl),
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
                child: Text(anySelected
                    ? t(ctx).tr('confirm').toUpperCase()
                    : t(ctx).tr('selectAtLeastOneSize'),
                  style: const TextStyle(fontWeight: FontWeight.w800)))),
            if (current != null) _RemoveExtraButton(item: item, ref: ref, onExtrasUpdated: onExtrasUpdated),
          ]));
      }));
}

/// Předvyplní [sizes] z už zvolené výbavy ([current], text „Helma: L, …“)
/// nebo z minulé rezervace; true = předvyplněno z minulé rezervace.
bool _prefillPassenger(Map<String, String?> sizes, WidgetRef ref, SelectedExtra? current, bool selfService) {
  String? valid(String label, Object? v) {
    final s = v is String ? v.trim() : null;
    return s != null && _passengerGearSizes(label, selfService).contains(s) ? s : null;
  }
  if (current != null) {
    for (final part in (current.size ?? '').split(',')) {
      final ix = part.indexOf(':');
      if (ix <= 0) continue;
      final k = part.substring(0, ix).trim();
      if (sizes.containsKey(k)) sizes[k] = valid(k, part.substring(ix + 1));
    }
    return false;
  }
  final gs = ref.read(profileProvider).valueOrNull?['gear_sizes'];
  final p = gs is Map ? gs['passenger'] : null;
  if (p is! Map) return false;
  const keys = {'Helma': 'helmet', 'Rukavice': 'gloves', 'Bunda': 'jacket', 'Kalhoty': 'pants'};
  keys.forEach((label, k) => sizes[label] = valid(label, p[k]));
  return sizes.values.any((v) => v != null);
}

/// Velikost bot z minulé rezervace (`gear_sizes.rider|passenger.boots`).
String? _lastBootsSize(WidgetRef ref, String itemId) {
  final gs = ref.read(profileProvider).valueOrNull?['gear_sizes'];
  final who = itemId == 'extra-boty-spolu' ? 'passenger' : 'rider';
  final m = gs is Map ? gs[who] : null;
  final v = m is Map ? m['boots'] : null;
  return v is String && v.trim().isNotEmpty ? v.trim() : null;
}

/// „Odebrat“ v listu velikostí už zvoleného doplňku (dřív to dělalo klepnutí
/// na dlaždici a velikosti se pak vybíraly znovu).
class _RemoveExtraButton extends StatelessWidget {
  final ExtraCatalogItem item;
  final WidgetRef ref;
  final void Function(List<SelectedExtra>) onExtrasUpdated;
  const _RemoveExtraButton({required this.item, required this.ref, required this.onExtrasUpdated});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton(
            onPressed: () {
              final ne = List<SelectedExtra>.from(ref.read(bookingDraftProvider).extras)
                ..removeWhere((e) => e.id == item.id);
              onExtrasUpdated(ne);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
            child: Text(t(context).tr('removeBtn'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

/// Adult passenger gear sizes per Czech gear label. Passengers only exist on
/// adult bikes, so these are always the adult lists ([selfService] = řady
/// samoobslužné pobočky, viz [gearSizesFor]).
List<String> _passengerGearSizes(String czLabel, bool selfService) {
  final type = switch (czLabel) {
    'Rukavice' => 'gloves',
    'Bunda' => 'jacket',
    'Kalhoty' => 'pants',
    _ => 'helmet',
  };
  return gearSizesFor(type, kids: false, selfService: selfService);
}

/// Single-item size picker (e.g. boot size for extras).
/// Calls [onExtrasUpdated] with the updated extras list after selection.
/// [sizesOverride] replaces [item.sizes] (used to switch boots to kids sizing).
/// [current] = už zvolený doplněk → jeho velikost je zvýrazněná + „Odebrat“.
/// Velikost z minulé rezervace je jen OZNAČENÁ „naposledy“ — vybírá se vždy
/// klepnutím (nevybrané boty se nesmí uložit, incident 2026-09-28).
void showSizeDialog(
  BuildContext ctx,
  ExtraCatalogItem item,
  WidgetRef ref,
  void Function(List<SelectedExtra>) onExtrasUpdated, {
  List<String>? sizesOverride,
  SelectedExtra? current,
}) {
  final sizeList = sizesOverride ?? item.sizes;
  final last = current == null ? _lastBootsSize(ref, item.id) : null;
  showModalBottomSheet(
    context: ctx,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(20))),
    builder: (c) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20,
        MediaQuery.of(c).padding.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const MgSheetHandle(),
        const SizedBox(height: 14),
        Text('${t(c).tr('selectSizeTitle')} – ${extraLabel(t(c).tr, item.id, item.name)}',
          style: const TextStyle(fontSize: 15,
            fontWeight: FontWeight.w800)),
        if (extraDescription(t(c).tr, item.id, item.description) != null) ...[
          const SizedBox(height: 4),
          Text(extraDescription(t(c).tr, item.id, item.description)!,
            style: const TextStyle(fontSize: 12,
              color: Color(0xFF8AAB99))),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8,
          children: sizeList.map((size) =>
            GestureDetector(
              onTap: () {
                final ne = List<SelectedExtra>.from(
                  ref.read(bookingDraftProvider).extras);
                ne.removeWhere((e) => e.id == item.id);
                // Od [loyaltyFreeGearLevel] je tento gear zdarma.
                final lvl = ref
                    .read(loyaltyStatusProvider).valueOrNull?.level ?? 0;
                ne.add(SelectedExtra(id: item.id,
                  name: item.name,
                  price: effectiveExtraPrice(item.id, item.price, lvl),
                  size: size));
                onExtrasUpdated(ne);
                Navigator.pop(c);
              },
              child: Container(
                constraints: const BoxConstraints(minWidth: 52, minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: size == current?.size
                      ? const Color(0xFF74FB71) : const Color(0xFFE8FFE8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: size == last
                        ? const Color(0xFF1A8A18) : const Color(0xFF74FB71),
                    width: size == last ? 2 : 1.5)),
                child: Column(mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(size, style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800)),
                  if (size == last)
                    Text(t(c).tr('bkSizeLastTag'), style: const TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: Color(0xFF1A8A18))),
                ])),
            )).toList()),
        if (current != null) _RemoveExtraButton(item: item, ref: ref, onExtrasUpdated: onExtrasUpdated),
      ])),
  );
}
