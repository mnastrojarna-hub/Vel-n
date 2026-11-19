import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../../core/v2/flag/v2_scope.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../gear_rental/gear_contract.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../v2/res_detail_hints_v2.dart' show ResPayStatusValueV2;
import '../v2/res_detail_parts_v2.dart';
import '../widgets/res_access_codes_card.dart';
import '../widgets/res_detail_button.dart';
import '../widgets/res_detail_card.dart';
import '../widgets/res_detail_row.dart';
import '../widgets/res_location_row.dart';
import '../widgets/res_modification_history.dart';
import '../widgets/res_pickup_procedure.dart';
import 'gear_detail_docs.dart';
import 'gear_links.dart';
import 'gear_models.dart';
import 'gear_note.dart';

/// Záložka „Podrobnosti“ výpůjčky JEN výbavy (oba vzhledy; v2 přes švy
/// `ResDetailCard`/`ResDetailRow`/…): kusy s velikostmi, cena/den,
/// pobočka + navigace na její GPS, doklad totožnosti, kód šatny, postup.
/// Bez kategorie, SPZ, km, jízd, hodnocení, SOS, výměny a obnovy
/// (GEAR_RENTAL_APP.md §5, web gearbk-view.js).
class GearDetailTabContent extends ConsumerWidget {
  final Reservation res;
  final AsyncValue<List<DoorCode>> doorCodesAsync;
  final Color statusColor;
  final String statusTitle;
  final String? branchFullAddress;
  final VoidCallback onShowCancelDialog;
  final Future<void> Function(BuildContext, String) onOpenFinalInvoice;
  final Future<void> Function(BuildContext, String) onOpenContract;

  const GearDetailTabContent({
    super.key,
    required this.res,
    required this.doorCodesAsync,
    required this.statusColor,
    required this.statusTitle,
    required this.branchFullAddress,
    required this.onShowCancelDialog,
    required this.onOpenFinalInvoice,
    required this.onOpenContract,
  });

  static const _paid = {'paid', 'partial_refund', 'refund_pending'};

  Widget _label(BuildContext context, String text, {bool title = false}) => MgV2.on(context)
      ? ResDetailLabelV2(text, title: title)
      : Padding(
          padding: EdgeInsets.only(bottom: 8, top: title ? 0 : 6),
          child: Text(title ? text : text.toUpperCase(),
              style: title
                  ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)
                  : const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
        );

  List<Widget> _head(BuildContext context) {
    if (MgV2.on(context)) return [ResDetailHeadV2(res: res)];
    return [
      Text(res.motoName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 2),
      Text(res.shortId, style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Text(statusTitle, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor)),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final st = res.displayStatus;
    final prices = ref.watch(gearPricesProvider).valueOrNull;
    final labels = prices == null ? null : {for (final p in prices) p.key: p.label};
    final perDay = res.gearPerDay;
    final live = res.status == 'reserved' || res.status == 'active';
    final paid = _paid.contains(res.paymentStatus);
    final appVisible = ref.watch(gearRentalSettingsProvider).valueOrNull?.appVisible ?? false;
    final items = res.gearLines.isNotEmpty
        ? [
            for (final l in res.gearLines)
              ResDetailRow(
                label: [gearLineLabel(l, tr, labels), if (gearLineSizes(l).isNotEmpty) '(${gearLineSizes(l)})'].join(' '),
                value: tr.trArgs('gearPerDay', {'price': Money.czk(l.perDay)}),
              ),
          ]
        : [for (final e in gearItemSizes(res).entries) ResDetailRow(label: tr.tr(e.key), value: e.value)];

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.list(children: [
        ResDetailCard(children: [
          ..._head(context),
          _label(context, tr.tr('gearItems')),
          ...items,
          const SizedBox(height: 4),
          ResDetailRow(label: tr.date, value: res.dateRange),
          ResDetailRow(label: tr.tr('resDuration'), value: '${res.dayCount} ${tr.daysWord(res.dayCount)}'),
          if (res.pickupHm != null) ResDetailRow(label: tr.pickupTime, value: res.pickupHm!),
          ResLocationRow(
            label: tr.tr('gearPlaceLabel'),
            isDelivery: false,
            address: <String>[gearBranchName(res.branchName), branchFullAddress ?? '']
                .where((s) => s.trim().isNotEmpty)
                .toSet()
                .join(', '),
            lat: res.branchLat,
            lng: res.branchLng,
            fallbackAddress: branchFullAddress,
          ),
        ]),
        const SizedBox(height: 12),

        // Rozdělaná webová výpůjčka: zaplatit (appka / web).
        if (gearCanPay(res))
          GearNoteBox(
            tone: MgTone.warn,
            title: tr.tr('gearPendingTitle'),
            text: tr.tr('gearPendingText'),
            actions: [_payButton(context, ref, appVisible)],
          ),

        ResDetailCard(children: [
          _label(context, tr.tr('financialSummary'), title: true),
          if (perDay != null)
            ResDetailRow(
              label: tr.trArgs('gearPerDay', {'price': Money.czk(perDay)}),
              value: '× ${res.dayCount} ${tr.daysWord(res.dayCount)}',
            ),
          if ((res.discountAmount ?? 0) > 0)
            ResDetailRow(
              label: tr.tr('discountLabel'),
              value: '−${Money.czk(res.discountAmount!)}',
              valueColor: MotoGoColors.greenDarker,
            ),
          ResDetailRow(label: tr.tr('totalPrice'), value: Money.czk(res.totalPrice), bold: true),
          if (MgV2.on(context))
            ResDetailRow(label: tr.tr('payment'), child: ResPayStatusValueV2(res: res))
          else
            ResDetailRow(
              label: tr.tr('payment'),
              value: res.paymentStatus == 'paid' ? '✓ ${tr.tr('paid')}' : res.paymentStatus.toUpperCase(),
            ),
        ]),
        const SizedBox(height: 12),

        GearDocsCard(res: res),
        ResModificationHistory(res: res),
        const SizedBox(height: 12),
        // Jen kód šatny (+ brána) — karta kódů je gear-aware.
        ResAccessCodesCard(res: res, doorCodesAsync: doorCodesAsync),
        // Samoobsluha: kroky na displeji; obslužná pobočka: předání obsluhou.
        ResPickupProcedure(res: res, codes: doorCodesAsync.valueOrNull),
        if (live && !res.isSelfService && st != ResStatus.dokoncene)
          GearNoteBox(text: tr.tr('gearStaffedPickup')),
        if (live && paid) GearNoteBox(text: tr.tr('gearAddItemContact')),

        if (st == ResStatus.dokoncene) ...[
          _label(context, tr.tr('documentsSection')),
          ResDetailButton.outlined(emoji: '💰', label: tr.tr('finalInvoice'), onTap: () => onOpenFinalInvoice(context, res.id)),
          const SizedBox(height: 8),
          ResDetailButton.outlined(emoji: '📄', label: tr.tr('rentalContract'), onTap: () => onOpenContract(context, res.id)),
        ],
        // Probíhající / nadcházející zaplacená: úpravy (velikosti, termín na
        // webu, odebrat kus) + storno jen před převzetím (web: reserved + paid).
        if ((st == ResStatus.nadchazejici || st == ResStatus.aktivni) && live && paid) ...[
          ResDetailButton.primary(
            emoji: '✏️',
            label: tr.tr('editReservation'),
            onTap: () => context.push('/reservations/${res.id}/edit'),
          ),
          if (st == ResStatus.nadchazejici && res.status == 'reserved' && res.pickedUpAt == null) ...[
            const SizedBox(height: 8),
            ResDetailButton.danger(emoji: '🗑️', label: tr.tr('cancelReservationBtn'), onTap: onShowCancelDialog),
          ],
        ],
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _payButton(BuildContext context, WidgetRef ref, bool appVisible) {
    final tr = t(context);
    final label = appVisible ? tr.trArgs('gearPayNow', {'amount': Money.czk(res.totalPrice)}) : tr.tr('gearPayWeb');
    void onTap() => payGearOrWeb(context, ref, res);
    if (MgV2.on(context)) {
      return MgBtnInk(key: const ValueKey('gear-pay-btn'), label: label, onTap: onTap, height: 44);
    }
    return ResDetailButton.primary(key: const ValueKey('gear-pay-btn'), emoji: '💳', label: label, onTap: onTap);
  }
}
