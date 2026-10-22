import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../booking/price_calculator.dart' show branchLat, branchLng;
import '../../documents/booking_doc_viewer.dart';
import '../../routes/ride_booking_section.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../res_actions.dart';
import 'res_detail_card.dart';
import 'res_detail_row.dart';
import 'res_detail_button.dart';
import 'res_location_row.dart';
import 'res_modification_history.dart';
import 'res_access_codes_card.dart';
import 'res_pickup_procedure.dart';
import 'res_rating_card.dart';
import 'paid_change_banner.dart';
import '../../../core/currency.dart';
import '../../../core/booking_rules.dart';

/// Sliver list content for the "Podrobnosti" tab in reservation detail.
class ResDetailTabContent extends ConsumerWidget {
  final Reservation res;
  final AsyncValue<List<DoorCode>> doorCodesAsync;
  final Color statusColor;
  final String statusTitle;
  final String? branchFullAddress;
  final VoidCallback onShowCancelDialog;
  final Future<void> Function(BuildContext, String) onOpenFinalInvoice;
  final Future<void> Function(BuildContext, String) onOpenContract;
  final Future<void> Function(BuildContext, Reservation) onRestoreBooking;

  const ResDetailTabContent({
    super.key,
    required this.res,
    required this.doorCodesAsync,
    required this.statusColor,
    required this.statusTitle,
    required this.branchFullAddress,
    required this.onShowCancelDialog,
    required this.onOpenFinalInvoice,
    required this.onOpenContract,
    required this.onRestoreBooking,
  });

  /// Otevře reálný dokument rezervace 1:1 (podepsaný protokol / smlouva) —
  /// průběh (po 15 s „Zrušit"), pojistka proti dvojímu klepnutí; offline
  /// skutečný důvod + „Zkusit znovu", jinak „zatím není k dispozici".
  Future<void> _openBookingDoc(BuildContext context, String type, String title) =>
      openBookingDoc(context, res, type, title);

  /// Tlačítka na existující dokumenty rezervace (protokoly, příp. smlouva) —
  /// jen REÁLNÉ (aktuální verze; protokol jen podepsaný elektronicky / sken,
  /// nikdy šablona) — viz `resolveBookingDocs`.
  List<Widget> _bookingDocButtons(BuildContext context, WidgetRef ref, {bool includeContract = false}) {
    final docs = ref.watch(bookingDocsProvider(res.id)).valueOrNull ?? const <String, BookingDocSource>{};
    bool has(String type) => docs.containsKey(type);
    final out = <Widget>[];
    void add(String emoji, String label, String type) {
      out.add(ResDetailButton.outlined(emoji: emoji, label: label, onTap: () => _openBookingDoc(context, type, label)));
      out.add(const SizedBox(height: 8));
    }
    if (includeContract && has('contract')) add('📄', t(context).tr('rentalContract'), 'contract');
    if (has('protocol')) add('📝', t(context).tr('handoverProtocol'), 'protocol');
    if (has('protocol_damage')) add('⚠️', t(context).tr('damageProtocol'), 'protocol_damage');
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = res.displayStatus;
    final sosAsync = ref.watch(sosIncidentsProvider(res.id));
    final sosIncidents = sosAsync.valueOrNull ?? <SosIncident>[];

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.list(
        children: [
          // Zaplacená výměna / úprava se ještě zapisuje (D6).
          PaidChangeBanner(bookingId: res.id),
          ResDetailCard(children: [
            // Motorcycle name + ID
            Text(res.motoName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
            const SizedBox(height: 2),
            Text(res.shortId, style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
            const SizedBox(height: 10),

            // Status badge (+ trvale viditelné hodnocení jízdy, je-li)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    statusTitle,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor),
                  ),
                ),
                if ((res.rating ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: MotoGoColors.amberBg,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: MotoGoColors.amberBorder),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 3),
                      Text(
                        '${res.rating}/5',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFB45309)),
                      ),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Info rows
            ResDetailRow(label: t(context).tr('resCategory'), value: res.category ?? '–'),
            ResDetailRow(label: '${res.category ?? ""} – ${res.branchName ?? ""}', value: ''),
            ResDetailRow(label: t(context).date, value: res.dateRange),
            ResDetailRow(label: t(context).tr('resDuration'), value: '${res.dayCount} ${res.dayCount == 1 ? t(context).tr("day1") : res.dayCount < 5 ? t(context).tr("days24") : t(context).tr("days5")}'),
            ResDetailRow(label: t(context).tr('resDurationTotal'), value: '${res.dayCount} ${t(context).tr("days5")}'),
            // Čas vyzvednutí (HH:MM) i na samoobsluze (zadání 2026-10-01 večer);
            // stará značka 00:01 = „kdykoliv během prvního dne“.
            if (res.pickupAllDayLegacy)
              ResDetailRow(label: t(context).pickupTime, value: t(context).tr('ssPickupAnyTime'))
            else if (res.pickupHm != null)
              ResDetailRow(label: t(context).pickupTime, value: res.pickupHm!),
            // Navigace na pobočku VŽDY přes GPS — textová adresa „Mezná 9" je
            // nejednoznačná (obec Mezná existuje i u Hřenska → mapy navigovaly
            // špatně). Když pobočka nemá GPS v DB, použijí se souřadnice
            // hlavní pobočky (branchLat/branchLng z price_calculator).
            ResLocationRow(
              label: t(context).pickup,
              isDelivery: res.pickupMethod == 'delivery',
              address: res.pickupMethod == 'delivery' ? res.pickupAddress : branchFullAddress,
              lat: res.pickupMethod == 'delivery' ? res.pickupLat : (res.branchLat ?? branchLat),
              lng: res.pickupMethod == 'delivery' ? res.pickupLng : (res.branchLng ?? branchLng),
              fallbackAddress: res.pickupMethod == 'delivery' ? res.pickupAddress : branchFullAddress,
            ),
            ResLocationRow(
              label: t(context).returnLabel,
              isDelivery: res.returnMethod == 'delivery',
              address: res.returnMethod == 'delivery' ? res.returnAddress : branchFullAddress,
              lat: res.returnMethod == 'delivery' ? res.returnLat : (res.branchLat ?? branchLat),
              lng: res.returnMethod == 'delivery' ? res.returnLng : (res.branchLng ?? branchLng),
              fallbackAddress: res.returnMethod == 'delivery' ? res.returnAddress : branchFullAddress,
            ),
          ]),
          const SizedBox(height: 12),

          // ===== VÝDEJ AŽ OD 12:00 (sleva za vyzvednutí od 12:00, samoobsluha) =====
          // Kiosk kódy (šatna i motorka) pustí až od 12:00 dne začátku — dokud
          // výdej nenastal, vysvětlení + cesta k dřívějšímu času (sleva zanikne,
          // doplatek). CTA jen u nevyzvednuté 'reserved' (aktivní čas nezmění).
          if (res.kioskReleasePending) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MotoGoColors.amberBg,
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  '🌗 ${t(context).tr('ssLateGateNote').replaceAll('{datum}', fmtReleaseDate(pragueWallClock(res.startDate)))}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E), height: 1.4),
                ),
                if (res.status == 'reserved') ...[
                  const SizedBox(height: 10),
                  ResDetailButton.primary(
                    emoji: '🕛',
                    label: t(context).tr('ssLateGateCta'),
                    onTap: () => context.push('/reservations/${res.id}/edit'),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // ===== PRICE CARD =====
          ResDetailCard(children: [
            Text(t(context).tr('financialSummary'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 8),
            ResDetailRow(label: t(context).tr('totalPrice'), value: '${Money.czk(res.totalPrice)}', bold: true),
            if (res.deliveryFee != null && res.deliveryFee! > 0)
              ResDetailRow(label: t(context).tr('deliveryFee'), value: '${Money.czk(res.deliveryFee!)}'),
            if (res.extrasPrice != null && res.extrasPrice! > 0)
              ResDetailRow(label: t(context).tr('addons'), value: '${Money.czk(res.extrasPrice!)}'),
            // Sleva 50 % na 1. den (vyzvednutí od 12:00) — přiznaná hodnota.
            if ((res.latePickupDiscount ?? 0) > 0)
              ResDetailRow(
                label: t(context).tr('latePickupDiscountLabel'),
                value: '−${Money.czk(res.latePickupDiscount!)}',
                valueColor: MotoGoColors.greenDarker,
              ),
            if (res.discountAmount != null && res.discountAmount! > 0)
              ResDetailRow(
                label: '${t(context).tr('discountLabel')} ${res.discountCode ?? ""}',
                value: '−${Money.czk(res.discountAmount!)}',
                valueColor: MotoGoColors.greenDarker,
              ),
            ResDetailRow(
              label: t(context).tr('payment'),
              value: res.paymentStatus == 'paid' ? '✓ ${t(context).tr('paid')}' : res.paymentStatus.toUpperCase(),
            ),
          ]),
          const SizedBox(height: 12),

          // ===== COMPREHENSIVE HISTORY (ALL statuses) =====
          ResModificationHistory(res: res, sosIncidents: sosIncidents),
          const SizedBox(height: 12),

          // ===== DOOR CODES (po celý termín — i PŘED vydáním motorky) =====
          // Pořadí brána → šatna → motorka (karta v res_access_codes_card.dart).
          ResAccessCodesCard(res: res, doorCodesAsync: doorCodesAsync),

          // ===== POSTUP PŘI VYZVEDNUTÍ (samoobsluha, výchozí zabalený) =====
          ResPickupProcedure(res: res, codes: doorCodesAsync.valueOrNull),

          // ===== HODNOCENÍ JÍZDY (Completed only) — hvězdy + 2 rovnocenné volby =====
          if (st == ResStatus.dokoncene) ...[
            ResRatingCard(res: res),
            const SizedBox(height: 12),

            // Action buttons for completed — documents section
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t(context).tr('documentsSection'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
            ),
            ResDetailButton.outlined(
              emoji: '💰',
              label: t(context).tr('finalInvoice'),
              onTap: () => onOpenFinalInvoice(context, res.id),
            ),
            const SizedBox(height: 8),
            ResDetailButton.outlined(
              emoji: '📄',
              label: t(context).tr('rentalContract'),
              onTap: () => onOpenContract(context, res.id),
            ),
            const SizedBox(height: 8),
            // Historické protokoly (předávací / o poškození) — 1:1 podepsaný dokument
            ..._bookingDocButtons(context, ref),
            // Google recenze je v kartě hodnocení výše (spolu s „Napiš nám
            // přímo, co máme zlepšit“) — dřívější samostatné tlačítko zrušeno.
            const SizedBox(height: 4),
            ResDetailButton.primary(
              emoji: '🔁',
              label: t(context).tr('bookAgain'),
              onTap: () => rebookSameMoto(context, ref, res),
            ),
          ],

          // ===== CANCELLED — restore button =====
          if (st == ResStatus.cancelled) ...[
            ResDetailButton.primary(
              emoji: '🔄',
              label: t(context).tr('restoreBooking'),
              onTap: () => onRestoreBooking(context, res),
            ),
          ],

          // ===== ACTIVE ACTIONS (motorka vydaná) =====
          // Jediné tlačítko úprav „Upravit rezervaci“ (dřív tu bylo i duplicitní
          // „Upravit“ — zadání majitele 2026-09-29).
          if (st == ResStatus.aktivni) ...[
            ResDetailButton.primary(
              emoji: '✏️',
              label: t(context).tr('editReservation'),
              onTap: () => context.push('/reservations/${res.id}/edit'),
            ),
            if (res.sosAllowed) ...[
              const SizedBox(height: 8),
              ResDetailButton.sos(
                emoji: '🆘',
                label: t(context).sosTitle,
                onTap: () => context.push(Routes.sos),
              ),
            ],
          ],

          // ===== DOKUMENTY (po celý termín, i před vydáním) =====
          // Kalendářní `inRentalTerm`, ne `st` (do podpisu protokolu je rezervace
          // „Nadcházející“). Vyplnění předávacího protokolu (samoobsluha) je jen
          // v banneru nahoře — spodní duplicitní tlačítko zrušeno (zadání majitele
          // 2026-09-29); podepsaný protokol je níž mezi dokumenty.
          // I u motorky vydané před začátkem termínu (obsluha večer předem).
          if (res.inRentalTerm || st == ResStatus.aktivni) ...[
            // Dokumenty aktivní rezervace — smlouva + podepsané protokoly 1:1.
            if (_bookingDocButtons(context, ref, includeContract: true).isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(t(context).tr('documentsSection'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
              ),
              ..._bookingDocButtons(context, ref, includeContract: true),
            ],
          ],

          // ===== UPCOMING ACTIONS =====
          // Zobrazují se i v DEN vyzvednutí, dokud si zákazník motorku nepřevzal:
          // `st` je do vydání (podpis protokolu / DB 'active') `nadchazejici`.
          // Vydaná motorka (`aktivni`, i když DB kvůli vratce drží 'reserved')
          // storno nenabízí — cancel_booking_tracked by zrušil i rozjetou jízdu.
          if (st == ResStatus.nadchazejici) ...[
            ResDetailButton.primary(
              emoji: '✏️',
              label: t(context).tr('editReservation'),
              onTap: () => context.push('/reservations/${res.id}/edit'),
            ),
            const SizedBox(height: 8),
            ResDetailButton.danger(
              emoji: '🗑️',
              label: t(context).tr('cancelReservationBtn'),
              onTap: onShowCancelDialog,
            ),
          ],

          // Projeté jízdy z této výpůjčky (vznikly automaticky s povolenou
          // polohou) — otevírají detail jízdy s mapou, zastávkami a fotkami.
          BookingRidesSection(bookingId: res.id),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
