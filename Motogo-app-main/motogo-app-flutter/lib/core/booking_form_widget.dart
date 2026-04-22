import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'booking_form_header_widget.dart';
import 'booking_form_moto_card.dart';
import 'booking_form_time_section.dart';
import 'booking_form_pickup_section.dart';
import 'booking_form_return_section.dart';
import 'booking_form_extras_section.dart';
import 'booking_form_price_section.dart';
import 'booking_form_promo_section.dart';
import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_ui_helpers.dart';
import '../features/catalog/catalog_provider.dart';
import '../features/catalog/moto_model.dart';
import '../features/catalog/widgets/availability_calendar.dart';

// ═══════════════════════════════════════════════════════════════════
// INLINE BOOKING FORM — everything in ONE file, per-section try-catch
// ═══════════════════════════════════════════════════════════════════

class BookingDebugWrapper extends ConsumerStatefulWidget {
  const BookingDebugWrapper({super.key});

  @override
  ConsumerState<BookingDebugWrapper> createState() => _BDWState();
}

class _BDWState extends ConsumerState<BookingDebugWrapper> {
  bool _calOpen = false;

  void _upd(BookingDraft Function(BookingDraft) fn) {
    final d = ref.read(bookingDraftProvider);
    ref.read(bookingDraftProvider.notifier).state = fn(d);
  }

  /// Gear sizes that must be filled before proceeding when the motorcycle
  /// is delivered (přistavení). Returns a human-readable list of missing
  /// items — empty list means OK to continue.
  List<String> _missingGearSizes(BookingDraft d) {
    if (d.pickupMethod != 'delivery') return const [];
    final missing = <String>[];
    if (d.helmetSize == null) missing.add('helma – řidič');
    if (d.glovesSize == null) missing.add('rukavice – řidič');
    if (d.jacketSize == null) missing.add('bunda – řidič');
    if (d.pantsSize == null) missing.add('kalhoty – řidič');
    SelectedExtra? findExtra(String id) =>
        d.extras.where((e) => e.id == id).firstOrNull;
    final botyRidic = findExtra('extra-boty-ridic');
    if (botyRidic != null && (botyRidic.size == null || botyRidic.size!.isEmpty)) {
      missing.add('boty – řidič');
    }
    final spolujezdec = findExtra('extra-spolujezdec');
    if (spolujezdec != null && (spolujezdec.size == null || spolujezdec.size!.isEmpty)) {
      missing.add('výbava – spolujezdec');
    }
    final botySpolu = findExtra('extra-boty-spolu');
    if (botySpolu != null && (botySpolu.size == null || botySpolu.size!.isEmpty)) {
      missing.add('boty – spolujezdec');
    }
    return missing;
  }

  // ─── Date section (stateful — owns _calOpen) ─────────────────────

  Widget _buildDateSection(BookingDraft draft, PriceBreakdown bd,
      bool hasDates, int dc, String Function(DateTime) f) {
    return bookingCard(
      2,
      'DATUM',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_calOpen && hasDates)
            GestureDetector(
              onTap: () => setState(() => _calOpen = true),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FFE8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today,
                      size: 14, color: Color(0xFF1A8A18)),
                  const SizedBox(width: 6),
                  Text(
                    '${f(draft.startDate!)} – ${f(draft.endDate!)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A8A18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$dc ${dc == 1 ? "den" : dc < 5 ? "dny" : "dní"}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'UPRAVIT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3DBA3A),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ]),
              ),
            ),
          if (_calOpen || !hasDates) ...[
            const Text(
              'Pro výběr jednoho dne klikněte dvakrát',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF8AAB99),
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Consumer(builder: (context, ref, _) {
              final booked =
                  ref.watch(bookedDatesProvider(draft.motoId ?? ''));
              return AvailabilityCalendar(
                bookedDates: booked.valueOrNull ?? [],
                selectedStart: draft.startDate,
                selectedEnd: draft.endDate,
                onRangeSelected: (s, e) {
                  _upd((d) =>
                      d.copyWith(startDate: () => s, endDate: () => e));
                  setState(() => _calOpen = false);
                },
                onReset: () {
                  _upd((d) => d.copyWith(
                      startDate: () => null, endDate: () => null));
                },
              );
            }),
          ],
          if (hasDates)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FFE8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF74FB71), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Celkem za pronájem',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4A6357),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      '${bd.basePrice.toStringAsFixed(0)} Kč',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A8A18),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Main build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final moto = ref.watch(bookingMotoProvider);
    if (moto == null) {
      return Container(
        color: const Color(0xFFDFF0EC),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.motorcycle,
                    size: 48, color: Color(0xFF8AAB99)),
                const SizedBox(height: 12),
                const Text(
                  'Nejprve vyberte motorku',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F1A14),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => GoRouter.of(context).go('/search'),
                  child: const Text('VYBRAT MOTORKU'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final draft = ref.watch(bookingDraftProvider);
    final bd = ref.watch(priceBreakdownProvider);
    final err = ref.watch(bookingValidationErrorProvider);
    final hasDates = draft.startDate != null && draft.endDate != null;
    final dc = hasDates ? draft.dayCount : 0;
    final isKids = moto.licenseRequired == 'N';
    final missingSizes = _missingGearSizes(draft);
    String f(DateTime d) => '${d.day}.${d.month}.${d.year}';

    return Material(
      color: const Color(0xFFDFF0EC),
      child: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                BookingFormHeader(draft: draft, moto: moto),
                BookingFormMotoCard(moto: moto),
                _buildDateSection(draft, bd, hasDates, dc, f),
                BookingFormTimeSection(
                  draft: draft,
                  onTimeChanged: (t) =>
                      _upd((d) => d.copyWith(pickupTime: () => t)),
                ),
                BookingFormPickupSection(draft: draft, onUpd: _upd),
                BookingFormReturnSection(draft: draft, onUpd: _upd),
                BookingFormExtrasSection(draft: draft, onUpd: _upd),
                BookingFormPriceSection(draft: draft, bd: bd, dayCount: dc),
                BookingFormPromoSection(draft: draft, onUpd: _upd),
                // SOUHLASY — only kids consent needed for children's bikes
                if (isKids)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: bookingCheckbox(
                      'Potvrzuji, že jsem zákonný zástupce a dětský '
                      'motocykl bude provozován pod mým dohledem',
                      draft.consentKids,
                      (v) => _upd((d) => d.copyWith(consentKids: v)),
                    ),
                  ),
                // WARNING — chybějící velikosti výbavy při přistavení
                if (missingSizes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9E6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFFFD54F),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 18, color: Color(0xFF92400E)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Při přistavení vyplňte velikosti výbavy',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF92400E),
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Chybí: ${missingSizes.join(', ')}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF92400E),
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // CTA — disabled when sizes are missing (přistavení)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: missingSizes.isEmpty
                          ? () => GoRouter.of(context).push('/payment')
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF74FB71),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: const Color(0xFFD4E8E0),
                        disabledForegroundColor: const Color(0xFF8AAB99),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'POKRAČOVAT K PLATBĚ',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
// END of _BDWState
