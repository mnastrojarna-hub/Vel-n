import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_ui_helpers.dart';
import '../features/loyalty/loyalty_provider.dart';
import 'booking_size_dialogs.dart';
import 'i18n/i18n_provider.dart';
import 'currency.dart';
import 'v2/flag/v2_scope.dart';
import 'v2/icons/mg_icon.dart';
import '../features/booking/v2/sections/extras_rows_v2.dart';
import '../features/booking/v2/sections/extras_v2.dart';

/// Equipment & extras selector section inside the booking form.
class BookingFormExtrasSection extends ConsumerWidget {
  const BookingFormExtrasSection({
    super.key,
    required this.draft,
    required this.onUpd,
    this.isKids = false,
    this.selfService = false,
    this.motoId,
  });

  final BookingDraft draft;

  /// Dětská motorka (license_required='N') — bez spolujezdce, dětské velikosti.
  final bool isKids;

  /// Motorka stojí na SAMOOBSLUŽNÉ pobočce (`branches.type='samoobslužná'`).
  /// Taková pobočka vozík nevydává (pevná sestava 7 kójí + šatna, výdej 24/7
  /// kódem bez obsluhy) → dlaždice „Vozík" se vůbec nenabídne. Vozík je jen
  /// na obslužné pobočce; backend to hlídá i sám (`get_trailer_availability`
  /// s `p_moto_id` + trigger `trg_check_trailer_overlap`).
  /// Zároveň zužuje řady velikostí výbavy řidiče i spolujezdce (helma S–3XL,
  /// bunda/kalhoty/rukavice max 4XL — [gearSizesFor], zadání 2026-10-10).
  final bool selfService;

  /// Motorka, ke které se vozík přidává — jde do `get_trailer_availability`.
  final String? motoId;

  /// Applies a mutation to the current [BookingDraft].
  final void Function(BookingDraft Function(BookingDraft) fn) onUpd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Věrnostní rank — od [loyaltyFreeGearLevel] je placená výbava zdarma.
    final lvl = ref.watch(loyaltyStatusProvider).valueOrNull?.level ?? 0;
    final gearFree = isGearFreeAt(lvl);
    final v2 = MgV2.on(context);
    // Obsluha sdílená starým i v2 vzhledem (těla beze změny, jen vytažená
    // z inline closur stromu níže).
    void onOwnGear(bool v) => onUpd((d) => d.copyWith(
          ownGear: v,
          helmetSize: v ? () => null : null,
          glovesSize: v ? () => null : null,
          jacketSize: v ? () => null : null,
          pantsSize: v ? () => null : null,
        ));
    void setHelmet(String? s) => onUpd((d) => d.copyWith(helmetSize: () => s));
    void setGloves(String? s) => onUpd((d) => d.copyWith(glovesSize: () => s));
    void setJacket(String? s) => onUpd((d) => d.copyWith(jacketSize: () => s));
    void setPants(String? s) => onUpd((d) => d.copyWith(pantsSize: () => s));
    final extraTiles = (isKids
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
      final priceLabel = effectiveExtraPrice(item.id, item.price, lvl) == 0
          ? t(context).tr('gearFree')
          : '+${Money.czk(item.price)}';
      // Zvolená výbava s velikostmi → její list + „Odebrat“ (2026-10-22).
      void onTap() {
        if (sel && !isSpolujezdec && item.sizes.isEmpty) {
          final ne = List<SelectedExtra>.from(draft.extras);
          ne.removeWhere((e) => e.id == item.id);
          onUpd((d) => d.copyWith(extras: ne));
        } else if (isSpolujezdec) {
          showPassengerGearSheet(context, item, ref,
              (ne) => onUpd((d) => d.copyWith(extras: ne)),
              selfService: selfService, current: selExtra);
        } else if (item.sizes.isNotEmpty) {
          showSizeDialog(context, item, ref,
              (ne) => onUpd((d) => d.copyWith(extras: ne)),
              sizesOverride: gearSizesFor('boots', kids: isKids, selfService: selfService),
              current: selExtra);
        } else {
          final ne = List<SelectedExtra>.from(draft.extras);
          ne.add(SelectedExtra(
              id: item.id,
              name: item.name,
              price: effectiveExtraPrice(item.id, item.price, lvl)));
          onUpd((d) => d.copyWith(extras: ne));
        }
      }

      // v2 vzhled (kill-switch app_v2_ui): stejná data i klepnutí.
      if (v2) {
        final freeByRank =
            effectiveExtraPrice(item.id, item.price, lvl) == 0 && item.price > 0;
        return BookingExtraRowV2(
          icon: isSpolujezdec
              ? MgIcons.user
              : (item.sizes.isNotEmpty ? MgIcons.boot : MgIcons.plus),
          title: extraLabel(t(context).tr, item.id, item.name),
          sub: bkExtraSub(t(context), item,
              size: sel ? selExtra?.size : null, needSize: needSize),
          needSize: needSize,
          price: priceLabel,
          struck: freeByRank ? Money.czk(item.price) : null,
          freeWithRank: freeByRank,
          selected: sel,
          opensSheet: isSpolujezdec || item.sizes.isNotEmpty,
          onTap: onTap,
        );
      }
      return GestureDetector(
        onTap: onTap,
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
                    extraLabel(t(context).tr, item.id, item.name),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    sel && selExtra?.size != null
                        ? '${t(context).tr('sizeLabel')}: ${extraSizeLabel(t(context).tr, selExtra!.size!)}'
                        : needSize
                            ? '⚠ ${t(context).tr('clickSelectSize')}'
                            : extraDescription(t(context).tr, item.id, item.description) ?? '',
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
              priceLabel,
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
    }).toList();
    // v2 vzhled (kill-switch app_v2_ui): stejné přepínače, velikosti,
    // doplňky i vozík (každý řádek výše už kreslí svůj v2 vzhled).
    if (v2) {
      return BookingExtrasV2(
        ownGear: draft.ownGear,
        onOwnGear: onOwnGear,
        gearFree: gearFree,
        gearRows: draft.ownGear
            ? const []
            : [
                BookingGearRowV2(
                  label: t(context).tr('helmet'),
                  selected: draft.helmetSize,
                  onChanged: setHelmet,
                  sizes: gearSizesFor('helmet', kids: isKids, selfService: selfService),
                ),
                BookingGearRowV2(
                  label: t(context).tr('gloves'),
                  selected: draft.glovesSize,
                  onChanged: setGloves,
                  sizes: gearSizesFor('gloves', kids: isKids, selfService: selfService),
                ),
                BookingGearRowV2(
                  label: t(context).tr('jacket'),
                  selected: draft.jacketSize,
                  onChanged: setJacket,
                  sizes: gearSizesFor('jacket', kids: isKids, selfService: selfService),
                ),
                BookingGearRowV2(
                  label: t(context).tr('pants'),
                  selected: draft.pantsSize,
                  onChanged: setPants,
                  sizes: gearSizesFor('pants', kids: isKids, selfService: selfService),
                ),
              ],
        items: extraTiles,
        trailer: !isKids && !selfService ? _buildTrailerTile(context, ref) : null,
      );
    }
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
            onOwnGear,
          ),
          if (!draft.ownGear) ...[
            const SizedBox(height: 8),
            bookingGearRow(
              t(context).tr('helmet'),
              draft.helmetSize,
              setHelmet,
              sizes: gearSizesFor('helmet', kids: isKids, selfService: selfService),
            ),
            bookingGearRow(
              t(context).tr('gloves'),
              draft.glovesSize,
              setGloves,
              sizes: gearSizesFor('gloves', kids: isKids, selfService: selfService),
            ),
            bookingGearRow(
              t(context).tr('jacket'),
              draft.jacketSize,
              setJacket,
              sizes: gearSizesFor('jacket', kids: isKids, selfService: selfService),
            ),
            bookingGearRow(
              t(context).tr('pants'),
              draft.pantsSize,
              setPants,
              sizes: gearSizesFor('pants', kids: isKids, selfService: selfService),
            ),
          ],
          const SizedBox(height: 10),
          // Od [loyaltyFreeGearLevel]: veškerá výbava i obuv zdarma
          // (řidič i spolujezdec). Stejný banner jako při úpravě rezervace.
          if (gearFree)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FFE8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x8074FB71)),
                ),
                child: Row(children: [
                  const Text('🏅', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(context).tr('loyaltyGearBenefit'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A8A18),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ...extraTiles,
          // Vozík (přívěs) — zdarma v appce; přiřadí volný kus a blokuje jeho
          // kalendář. Skryté u dětských motorek, u SAMOOBSLUŽNÉ pobočky
          // (nemá ho kdo vydat) i když není volný kus.
          if (!isKids && !selfService) _buildTrailerTile(context, ref),
        ],
      ),
    );
  }

  Widget _buildTrailerTile(BuildContext context, WidgetRef ref) {
    final selected = draft.trailerMotoId != null;
    final avail = ref.watch(trailerAvailabilityProvider(
        (start: draft.startDate, end: draft.endDate, motoId: motoId)));
    final candidate = avail.valueOrNull;
    // Skryj, pokud vozík není vybraný a žádný volný kus není dostupný.
    if (!selected && (candidate == null || !candidate.hasFree)) {
      return const SizedBox.shrink();
    }
    final assignId = selected ? draft.trailerMotoId : candidate?.trailerId;
    // Obsluha sdílená starým i v2 vzhledem (tělo beze změny).
    void onTap() {
      if (selected) {
        final ne = List<SelectedExtra>.from(draft.extras)
          ..removeWhere((e) => e.id == 'extra-vozik');
        onUpd((d) => d.copyWith(extras: ne, trailerMotoId: () => null));
      } else if (assignId != null) {
        final ne = List<SelectedExtra>.from(draft.extras)
          ..add(SelectedExtra(
              id: 'extra-vozik',
              name: t(context).tr('gearTrailer'),
              price: 0));
        onUpd((d) => d.copyWith(extras: ne, trailerMotoId: () => assignId));
      }
    }

    // v2 vzhled (kill-switch app_v2_ui): stejná dostupnost i klepnutí.
    if (MgV2.on(context)) {
      return BookingExtraRowV2(
        icon: MgIcons.truck,
        title: t(context).tr('gearTrailer'),
        sub: t(context).tr('gearTrailerDesc'),
        needSize: false,
        price: t(context).tr('gearFree'),
        selected: selected,
        onTap: onTap,
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8FFE8) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF74FB71) : const Color(0xFFD4E8E0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF74FB71) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected ? const Color(0xFF74FB71) : const Color(0xFFD4E8E0),
                width: 2,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, size: 14, color: Colors.black)
                : null,
          ),
          const SizedBox(width: 10),
          const Text('🛻 ', style: TextStyle(fontSize: 18)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(context).tr('gearTrailer'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  t(context).tr('gearTrailerDesc'),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF8AAB99),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          Text(
            t(context).tr('gearFree'),
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
  }
}
