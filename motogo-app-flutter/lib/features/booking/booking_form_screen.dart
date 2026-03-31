import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../catalog/widgets/availability_calendar.dart';
import 'booking_models.dart';
import 'booking_provider.dart';
import 'widgets/extras_selector.dart';
import 'widgets/address_picker.dart';
import 'widgets/promo_code_input.dart';
import 'widgets/price_summary.dart';

/// Multi-step booking form — mirrors s-booking from templates-booking-form.js + form2.js.
/// Steps: Dates → Extras → Pickup/Return → Discount → Summary.
class BookingFormScreen extends ConsumerStatefulWidget {
  const BookingFormScreen({super.key});

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  bool _consentVop = false;
  bool _consentGdpr = false;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final moto = ref.watch(bookingMotoProvider);
    final breakdown = ref.watch(priceBreakdownProvider);
    final extrasAsync = ref.watch(extrasCatalogProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    20, MediaQuery.of(context).padding.top + 12, 20, 14,
                  ),
                  decoration: const BoxDecoration(
                    color: MotoGoColors.dark,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                          child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rezervace motorky', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                          Text('Vyplňte formulář', style: TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Moto card
              if (moto != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _MotoSelectionCard(moto: moto),
                  ),
                ),

              // Step 1: Date calendar
              SliverToBoxAdapter(
                child: _Section(
                  step: 1,
                  title: 'Datum',
                  child: AvailabilityCalendar(
                    selectedStart: draft.startDate,
                    selectedEnd: draft.endDate,
                    onRangeSelected: (s, e) {
                      ref.read(bookingDraftProvider.notifier).update((d) => d
                        ..startDate = s
                        ..endDate = e);
                    },
                  ),
                ),
              ),

              // Step 2: Pickup time
              SliverToBoxAdapter(
                child: _Section(
                  step: 2,
                  title: 'Čas vyzvednutí',
                  child: _TimeSelector(
                    selected: draft.pickupTime,
                    onChanged: (t) {
                      ref.read(bookingDraftProvider.notifier).update((d) => d..pickupTime = t);
                    },
                  ),
                ),
              ),

              // Step 3: Extras
              SliverToBoxAdapter(
                child: _Section(
                  step: 3,
                  title: 'Výbava a doplňky',
                  child: extrasAsync.when(
                    data: (catalog) => ExtrasSelector(
                      catalog: catalog,
                      selected: draft.extras,
                      onChanged: (extras) {
                        ref.read(bookingDraftProvider.notifier).update((d) => d..extras = extras);
                      },
                    ),
                    loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
                    error: (_, __) => ExtrasSelector(
                      catalog: defaultExtras,
                      selected: draft.extras,
                      onChanged: (extras) {
                        ref.read(bookingDraftProvider.notifier).update((d) => d..extras = extras);
                      },
                    ),
                  ),
                ),
              ),

              // Step 4: Pickup method
              SliverToBoxAdapter(
                child: _Section(
                  step: 4,
                  title: 'Vyzvednutí motorky',
                  child: AddressPickerWidget(
                    label: 'Vyzvednutí',
                    method: draft.pickupMethod,
                    onMethodChanged: (m) {
                      ref.read(bookingDraftProvider.notifier).update((d) => d..pickupMethod = m);
                      if (m == 'store') ref.read(pickupDelivFeeProvider.notifier).state = 0;
                    },
                    onAddressChanged: (addr) {
                      ref.read(bookingDraftProvider.notifier).update((d) => d
                        ..pickupAddress = addr.street
                        ..pickupCity = addr.city
                        ..pickupZip = addr.zip
                        ..pickupLat = addr.lat
                        ..pickupLng = addr.lng);
                    },
                    onDeliveryFeeChanged: (fee) {
                      ref.read(pickupDelivFeeProvider.notifier).state = fee;
                    },
                  ),
                ),
              ),

              // Step 5: Return method
              SliverToBoxAdapter(
                child: _Section(
                  step: 5,
                  title: 'Vrácení motorky',
                  child: AddressPickerWidget(
                    label: 'Vrácení',
                    method: draft.returnMethod,
                    onMethodChanged: (m) {
                      ref.read(bookingDraftProvider.notifier).update((d) => d..returnMethod = m);
                      if (m == 'store') ref.read(returnDelivFeeProvider.notifier).state = 0;
                    },
                    onAddressChanged: (addr) {
                      ref.read(bookingDraftProvider.notifier).update((d) => d
                        ..returnAddress = addr.street
                        ..returnCity = addr.city
                        ..returnZip = addr.zip
                        ..returnLat = addr.lat
                        ..returnLng = addr.lng);
                    },
                    onDeliveryFeeChanged: (fee) {
                      ref.read(returnDelivFeeProvider.notifier).state = fee;
                    },
                  ),
                ),
              ),

              // Step 6: Promo code
              SliverToBoxAdapter(
                child: _Section(
                  step: 6,
                  title: 'Sleva',
                  child: PromoCodeInput(
                    appliedCodes: draft.discounts,
                    onCodeApplied: (d) {
                      ref.read(bookingDraftProvider.notifier).update(
                        (draft) => draft..discounts = [...draft.discounts, d],
                      );
                    },
                    onCodeRemoved: (code) {
                      ref.read(bookingDraftProvider.notifier).update(
                        (draft) => draft..discounts = draft.discounts.where((d) => d.code != code).toList(),
                      );
                    },
                  ),
                ),
              ),

              // Price summary
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: PriceSummaryCard(breakdown: breakdown),
                ),
              ),

              // Consents
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      _ConsentRow(
                        label: 'Souhlasím s obchodními podmínkami a VOP',
                        value: _consentVop,
                        onChanged: (v) => setState(() => _consentVop = v),
                      ),
                      const SizedBox(height: 6),
                      _ConsentRow(
                        label: 'Souhlasím se zpracováním osobních údajů',
                        value: _consentGdpr,
                        onChanged: (v) => setState(() => _consentGdpr = v),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // Sticky CTA
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))],
              ),
              child: ElevatedButton(
                onPressed: (_consentVop && _consentGdpr) ? () => context.push(Routes.payment) : null,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text('Pokračovat k platbě · ${breakdown.total.toStringAsFixed(0)} Kč →'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotoSelectionCard extends StatelessWidget {
  final dynamic moto;
  const _MotoSelectionCard({required this.moto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: MotoGoColors.g200),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: moto.displayImage, width: 50, height: 38, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox(width: 50, height: 38),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(moto.model, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                Text('od ${moto.priceLabel}/den', style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Změnit', style: TextStyle(fontSize: 11, color: MotoGoColors.greenDarker)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final int step;
  final String title;
  final Widget child;
  const _Section({required this.step, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
          boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22, height: 22,
                  decoration: const BoxDecoration(color: MotoGoColors.green, shape: BoxShape.circle),
                  child: Center(child: Text('$step', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white))),
                ),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TimeSelector extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onChanged;
  const _TimeSelector({this.selected, required this.onChanged});

  static const _times = ['07:00', '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _times.map((t) {
        final active = selected == t;
        return GestureDetector(
          onTap: () => onChanged(t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? MotoGoColors.greenDarker : const Color(0xFFBBF7D0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(t, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w900 : FontWeight.w600, color: active ? Colors.white : MotoGoColors.greenDarker)),
          ),
        );
      }).toList(),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ConsentRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: value ? MotoGoColors.green : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: value ? MotoGoColors.green : MotoGoColors.g200, width: 2),
            ),
            child: value ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MotoGoColors.g600))),
        ],
      ),
    );
  }
}
