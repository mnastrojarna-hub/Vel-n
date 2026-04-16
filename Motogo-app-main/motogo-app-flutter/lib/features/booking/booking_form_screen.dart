import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
// NOTE: NO import of router.dart — circular dependency kills rendering!
import '../catalog/catalog_provider.dart';
import '../catalog/widgets/availability_calendar.dart';
import 'booking_models.dart';
import 'booking_provider.dart';
import 'widgets/booking_form_card.dart';
import 'widgets/booking_form_consent.dart';
import 'widgets/booking_form_extra_item.dart';
import 'widgets/booking_form_price_row.dart';
import 'widgets/booking_form_radio_tile.dart';

/// Full booking form — all widgets inline (no external widget imports).
class BookingFormScreen extends ConsumerStatefulWidget {
  const BookingFormScreen({super.key});
  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  bool _consentVop = false;
  bool _consentGdpr = false;
  bool _calendarExpanded = false;
  String _promoText = '';

  String _fmt(DateTime d) => '${d.day}.${d.month}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final moto = ref.watch(bookingMotoProvider);
    final draft = ref.watch(bookingDraftProvider);
    final breakdown = ref.watch(priceBreakdownProvider);

    if (moto == null) {
      return Container(color: MotoGoColors.bg, child: SafeArea(child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.motorcycle, size: 48, color: MotoGoColors.g400),
          const SizedBox(height: 12),
          const Text('Nejprve vyberte motorku', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => context.go('/search'),
            style: ElevatedButton.styleFrom(backgroundColor: MotoGoColors.green, foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))),
            child: const Text('VYBRAT MOTORKU')),
        ]))));
    }

    final hasDates = draft.startDate != null && draft.endDate != null;
    final dayCount = hasDates ? draft.dayCount : 0;

    return Container(
      color: MotoGoColors.bg,
      child: SafeArea(child: Column(children: [
        // ── HEADER ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: const BoxDecoration(color: MotoGoColors.dark,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
          child: Row(children: [
            GestureDetector(onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                final id = draft.motoId;
                context.go(id != null ? '/moto/$id' : '/search');
              }
            }, child: Container(width: 38, height: 38,
                decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back, size: 20, color: Colors.black))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rezervace: ${moto.model}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
              const Text('Vyplňte formulář pro rezervaci', style: TextStyle(fontSize: 11, color: Colors.white54)),
            ])),
          ]),
        ),

        // ── SCROLLABLE BODY ──
        Expanded(child: SingleChildScrollView(child: Column(children: [

          // ═══ 1. MOTORKA ═══
          buildBookingFormCard(1, 'MOTORKA', GestureDetector(
            onTap: () {
              // Sync booking dates into catalog filter so search shows only available motos
              final d = ref.read(bookingDraftProvider);
              ref.read(catalogFilterProvider.notifier).state = ref.read(catalogFilterProvider).copyWith(
                startDate: () => d.startDate,
                endDate: () => d.endDate,
              );
              context.go('/search');
            },
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8),
                child: Image.network(moto.displayImage, width: 48, height: 36, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 48, height: 36, color: MotoGoColors.g200,
                    child: const Icon(Icons.motorcycle, size: 18, color: MotoGoColors.g400)))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(moto.model, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                Text('od ${moto.priceLabel}/den · záloha neúčtována', style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                if (moto.branchName != null)
                  Row(children: [
                    const Icon(Icons.location_on, size: 12, color: MotoGoColors.red), const SizedBox(width: 2),
                    Flexible(child: Text('Pobočka: ${moto.branchName}${moto.branchCity != null ? ', ${moto.branchCity}' : ''}',
                      style: const TextStyle(fontSize: 10, color: MotoGoColors.g400))),
                  ]),
              ])),
              const Text('ZMĚNIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.greenDark)),
            ]),
          )),

          // ═══ 2. DATUM ═══
          buildBookingFormCard(2, 'DATUM', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!_calendarExpanded && hasDates)
              GestureDetector(onTap: () => setState(() => _calendarExpanded = true),
                child: Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 14, color: MotoGoColors.greenDarker), const SizedBox(width: 6),
                    Text('${_fmt(draft.startDate!)} – ${_fmt(draft.endDate!)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: MotoGoColors.greenDarker, borderRadius: BorderRadius.circular(6)),
                      child: Text('$dayCount ${dayCount == 1 ? 'den' : dayCount < 5 ? 'dny' : 'dní'}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black))),
                    const Spacer(),
                    const Text('UPRAVIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.greenDark)),
                  ]))),
            if (_calendarExpanded || !hasDates) ...[
              const Text('Pro výběr jednoho dne klikněte dvakrát', style: TextStyle(fontSize: 11, color: MotoGoColors.g400)),
              const SizedBox(height: 8),
              Consumer(builder: (context, ref, _) {
                final bookedAsync = ref.watch(bookedDatesProvider(draft.motoId ?? ''));
                return AvailabilityCalendar(
                  bookedDates: bookedAsync.valueOrNull ?? [],
                  selectedStart: draft.startDate, selectedEnd: draft.endDate,
                  onRangeSelected: (s, e) {
                    ref.read(bookingDraftProvider.notifier).state = draft.copyWith(startDate: () => s, endDate: () => e);
                    setState(() => _calendarExpanded = false);
                  },
                  onStartSelected: (date) {
                    ref.read(bookingDraftProvider.notifier).state = draft.copyWith(startDate: () => date, endDate: () => null);
                  },
                  onReset: () {
                    ref.read(bookingDraftProvider.notifier).state = draft.copyWith(startDate: () => null, endDate: () => null);
                  });
              }),
            ],
          ])),

          // ═══ 3. ČAS VYZVEDNUTÍ ═══
          buildBookingFormCard(3, 'ČAS VYZVEDNUTÍ', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vyberte čas, kdy si motorku vyzvednete / chcete přistavit.',
              style: TextStyle(fontSize: 11, color: MotoGoColors.g400)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6,
              children: ['07:00','08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00','18:00'].map((t) {
                final a = draft.pickupTime == t;
                return GestureDetector(onTap: () => ref.read(bookingDraftProvider.notifier).state = draft.copyWith(pickupTime: () => t),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: a ? MotoGoColors.greenDarker : MotoGoColors.greenPale, borderRadius: BorderRadius.circular(8)),
                    child: Text(t, style: TextStyle(fontSize: 12, fontWeight: a ? FontWeight.w900 : FontWeight.w600,
                      color: a ? Colors.black : MotoGoColors.greenDarker))));
              }).toList()),
          ])),

          // ═══ 4. ŘIDIČSKÝ PRŮKAZ ═══
          buildBookingFormCard(4, 'ŘIDIČSKÝ PRŮKAZ', Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [Icon(Icons.credit_card, size: 18, color: MotoGoColors.g400), SizedBox(width: 8),
              Expanded(child: Text('Údaje z vašeho profilu', style: TextStyle(fontSize: 12, color: MotoGoColors.g600)))]))),

          // ═══ 5. VYZVEDNUTÍ ═══
          buildBookingFormCard(5, 'VYZVEDNUTÍ MOTORKY', Column(children: [
            buildBookingFormRadioTile('Na pobočce', 'Mezná 9, Mezná', 'Zdarma', draft.pickupMethod == 'store',
              () => ref.read(bookingDraftProvider.notifier).state = draft.copyWith(pickupMethod: 'store')),
            const SizedBox(height: 6),
            buildBookingFormRadioTile('Přistavení na vaši adresu', '1 000 Kč + 40 Kč/km', 'od 1 000 Kč', draft.pickupMethod == 'delivery',
              () => ref.read(bookingDraftProvider.notifier).state = draft.copyWith(pickupMethod: 'delivery')),
          ])),

          // ═══ 6. VRÁCENÍ ═══
          buildBookingFormCard(6, 'VRÁCENÍ MOTORKY', Column(children: [
            buildBookingFormRadioTile('Na pobočce', 'Mezná 9, Mezná', 'Zdarma', draft.returnMethod == 'store',
              () => ref.read(bookingDraftProvider.notifier).state = draft.copyWith(returnMethod: 'store')),
            const SizedBox(height: 6),
            buildBookingFormRadioTile('Odvoz z vaší adresy', '1 000 Kč + 40 Kč/km', 'od 1 000 Kč', draft.returnMethod == 'delivery',
              () => ref.read(bookingDraftProvider.notifier).state = draft.copyWith(returnMethod: 'delivery')),
          ])),

          // ═══ 7. VÝBAVA ═══
          buildBookingFormCard(7, 'VÝBAVA A DOPLŇKY', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3))),
              child: const Row(children: [
                Icon(Icons.shield, size: 20, color: MotoGoColors.greenDarker), SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Základní výbava zdarma', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
                  Text('Helma, rukavice, bunda, kalhoty', style: TextStyle(fontSize: 11, color: MotoGoColors.g600)),
                ])), Icon(Icons.check_circle, size: 18, color: MotoGoColors.green)])),
            const SizedBox(height: 10),
            buildBookingFormExtraItem(ref, 'extra-spolujezdec', '👥', 'Výbava spolujezdce', 'Helma, rukavice, vesta', 400, draft),
            buildBookingFormExtraItem(ref, 'extra-boty-ridic', '👢', 'Boty řidiče', 'Moto boty', 300, draft),
            buildBookingFormExtraItem(ref, 'extra-boty-spolu', '👟', 'Boty spolujezdce', 'Moto boty', 300, draft),
          ])),

          // ═══ SHRNUTÍ CENY ═══
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Shrnutí ceny', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              buildBookingFormPriceRow('Motorka × $dayCount ${dayCount == 1 ? 'den' : dayCount < 5 ? 'dny' : 'dní'}', '${breakdown.basePrice.toStringAsFixed(0)} Kč'),
              if (breakdown.deliveryFee > 0) buildBookingFormPriceRow('Přistavení / vrácení', '+${breakdown.deliveryFee.toStringAsFixed(0)} Kč'),
              if (breakdown.extrasTotal > 0) buildBookingFormPriceRow('Doplňky a výbava', '+${breakdown.extrasTotal.toStringAsFixed(0)} Kč'),
              if (breakdown.discountTotal > 0) buildBookingFormPriceRow('Sleva', '−${breakdown.discountTotal.toStringAsFixed(0)} Kč', color: MotoGoColors.greenDarker),
              buildBookingFormPriceRow('✓ Záloha se neúčtuje', '0 Kč', subtle: true),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: MotoGoColors.g200, height: 1)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Celkem (cena konečná)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                Text('${breakdown.total.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
              ]),
              const SizedBox(height: 4),
              const Text('Cena bez DPH, nejsme plátci', style: TextStyle(fontSize: 9, color: MotoGoColors.g400)),
            ]),
          )),

          // ═══ SLEVOVÝ KÓD ═══
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.local_offer, size: 16, color: MotoGoColors.dark), SizedBox(width: 6),
                Text('SLEVOVÝ KÓD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.dark))]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: MotoGoColors.g200, width: 1.5)),
                  child: TextField(onChanged: (v) => _promoText = v,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(hintText: 'Zadejte kód', hintStyle: TextStyle(fontSize: 12, color: MotoGoColors.g400),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none)))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () async {
                  if (_promoText.trim().isEmpty) return;
                  final result = await validateAndApplyCode(_promoText.trim());
                  if (!mounted) return;
                  if (result.success && result.discount != null) {
                    ref.read(bookingDraftProvider.notifier).state = draft.copyWith(discounts: [...draft.discounts, result.discount!]);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message(t(context).tr))));
                }, style: ElevatedButton.styleFrom(backgroundColor: MotoGoColors.dark, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  child: Text(t(context).tr('apply').toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
              ]),
              if (draft.discounts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
                child: Column(children: draft.discounts.map((d) => Container(
                  margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.check_circle, size: 14, color: MotoGoColors.greenDarker), const SizedBox(width: 6),
                    Expanded(child: Text(d.code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker))),
                    GestureDetector(onTap: () => ref.read(bookingDraftProvider.notifier).state =
                      draft.copyWith(discounts: draft.discounts.where((x) => x.code != d.code).toList()),
                      child: const Icon(Icons.close, size: 16, color: MotoGoColors.g400)),
                  ]))).toList())),
            ]),
          )),

          // ═══ SOUHLASY ═══
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Column(children: [
            buildBookingFormConsent('Souhlasím s obchodními podmínkami a VOP', _consentVop, (v) => setState(() => _consentVop = v)),
            const SizedBox(height: 6),
            buildBookingFormConsent('Souhlasím se zpracováním osobních údajů', _consentGdpr, (v) => setState(() => _consentGdpr = v)),
          ])),

          // ═══ CTA ═══
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: SizedBox(height: 52, child: ElevatedButton(
            onPressed: (_consentVop && _consentGdpr) ? () {
              // Auto-confirm single-day booking if only start date selected
              final d = ref.read(bookingDraftProvider);
              if (d.startDate != null && d.endDate == null) {
                ref.read(bookingDraftProvider.notifier).state =
                    d.copyWith(endDate: () => d.startDate);
              }
              context.push('/payment');
            } : null,
            style: ElevatedButton.styleFrom(backgroundColor: MotoGoColors.green, foregroundColor: Colors.black,
              disabledBackgroundColor: MotoGoColors.g200, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('POKRAČOVAT K PLATBĚ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              SizedBox(width: 8), Icon(Icons.arrow_forward, size: 18)])))),
          const SizedBox(height: 100),
        ]))),
      ])),
    );
  }
}
