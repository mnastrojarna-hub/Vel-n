import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../auth/widgets/toast_helper.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';

/// Reservation detail — mirrors s-res-detail from templates-res.js +
/// reservations-detail.js + reservations-detail-2.js.
class ReservationDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const ReservationDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<ReservationDetailScreen> createState() => _DetailState();
}

class _DetailState extends ConsumerState<ReservationDetailScreen> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    final resAsync = ref.watch(reservationByIdProvider(widget.bookingId));
    final doorCodesAsync = ref.watch(doorCodesProvider(widget.bookingId));

    return resAsync.when(
      data: (res) => res == null
          ? _error('Rezervace nenalezena')
          : _buildDetail(context, res, doorCodesAsync),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: MotoGoColors.green))),
      error: (e, _) => _error('Chyba: $e'),
    );
  }

  Widget _error(String msg) => Scaffold(
    backgroundColor: MotoGoColors.bg,
    appBar: AppBar(title: const Text('Detail')),
    body: Center(child: Text(msg)),
  );

  Widget _buildDetail(BuildContext context, Reservation res, AsyncValue<List<DoorCode>> doorCodesAsync) {
    final st = res.displayStatus;
    _rating = res.rating ?? 0;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: CustomScrollView(
        slivers: [
          // Image header
          SliverToBoxAdapter(
            child: Stack(
              children: [
                SizedBox(
                  height: 200, width: double.infinity,
                  child: CachedNetworkImage(
                    imageUrl: res.motoImage ?? '', fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: MotoGoColors.g200),
                  ),
                ),
                Positioned(bottom: 0, left: 0, right: 0, height: 80,
                  child: Container(
                    decoration: BoxDecoration(gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, MotoGoColors.black.withValues(alpha: 0.9)],
                    )),
                  ),
                ),
                Positioned(bottom: 12, left: 16, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(res.motoName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                    Text(res.shortId, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                  ],
                )),
                Positioned(top: MediaQuery.of(context).padding.top + 8, left: 12,
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(children: [
              // Status + dates
              _Card(children: [
                _Row(label: 'Stav', child: _StatusChip(status: st)),
                _Row(label: 'Termín', value: res.dateRange),
                _Row(label: 'Délka', value: '${res.dayCount} ${res.dayCount == 1 ? "den" : res.dayCount < 5 ? "dny" : "dní"}'),
                if (res.pickupTime != null) _Row(label: 'Čas vyzvednutí', value: res.pickupTime!),
                _Row(label: 'Vyzvednutí', value: res.pickupMethod == 'delivery' ? (res.pickupAddress ?? 'Přistavení') : 'Pobočka Mezná'),
                _Row(label: 'Vrácení', value: res.returnMethod == 'delivery' ? (res.returnAddress ?? 'Odvoz') : 'Pobočka Mezná'),
              ]),
              const SizedBox(height: 12),

              // Price
              _Card(children: [
                _Row(label: 'Celková cena', value: '${res.totalPrice.toStringAsFixed(0)} Kč', bold: true),
                if (res.deliveryFee != null && res.deliveryFee! > 0)
                  _Row(label: 'Přistavení', value: '${res.deliveryFee!.toStringAsFixed(0)} Kč'),
                if (res.extrasPrice != null && res.extrasPrice! > 0)
                  _Row(label: 'Doplňky', value: '${res.extrasPrice!.toStringAsFixed(0)} Kč'),
                if (res.discountAmount != null && res.discountAmount! > 0)
                  _Row(label: 'Sleva ${res.discountCode ?? ""}', value: '−${res.discountAmount!.toStringAsFixed(0)} Kč',
                      valueColor: MotoGoColors.greenDarker),
                _Row(label: 'Platba', value: res.paymentStatus == 'paid' ? '✓ Zaplaceno' : res.paymentStatus.toUpperCase()),
              ]),
              const SizedBox(height: 12),

              // Door codes (only when active + sent)
              doorCodesAsync.when(
                data: (codes) {
                  if (codes.isEmpty || st != ResStatus.aktivni) return const SizedBox.shrink();
                  return Column(children: [
                    _Card(children: [
                      const Padding(padding: EdgeInsets.only(bottom: 8),
                        child: Text('🔑 Přístupové kódy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
                      ...codes.map((c) => _Row(
                        label: c.codeType == 'motorcycle' ? 'Motorka' : 'Příslušenství',
                        value: c.sentToCustomer ? c.doorCode : (c.withheldReason ?? 'Čeká na doklady'),
                        bold: c.sentToCustomer,
                      )),
                    ]),
                    const SizedBox(height: 12),
                  ]);
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // Rating (completed only)
              if (st == ResStatus.dokoncene) ...[
                _Card(children: [
                  const Text('⭐ Hodnocení jízdy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final star = i + 1;
                      return GestureDetector(
                        onTap: () async {
                          setState(() => _rating = star);
                          await rateBooking(widget.bookingId, star);
                          if (mounted) showMotoGoToast(context, icon: '⭐', title: 'Děkujeme!', message: '$star/5 hvězdiček');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '⭐',
                            style: TextStyle(
                              fontSize: star <= _rating ? 28 : 24,
                              color: star <= _rating ? null : Colors.grey,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ]),
                const SizedBox(height: 12),
              ],

              // Actions
              if (st == ResStatus.aktivni) ...[
                ElevatedButton(
                  onPressed: () => context.push('/reservations/${res.id}/edit'),
                  child: const Text('⏱ Prodloužit / Zkrátit'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.push('/sos'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: MotoGoColors.red, width: 2),
                    foregroundColor: MotoGoColors.red,
                  ),
                  child: const Text('🆘 SOS — Pomoc na cestě'),
                ),
              ],
              if (st == ResStatus.nadchazejici) ...[
                ElevatedButton(
                  onPressed: () => context.push('/reservations/${res.id}/edit'),
                  child: const Text('✏️ Upravit rezervaci'),
                ),
              ],
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  final bool bold;
  final Color? valueColor;
  const _Row({required this.label, this.value, this.child, this.bold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
          child ?? Text(value ?? '', style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: valueColor ?? MotoGoColors.black)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ResStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      ResStatus.aktivni => ('Aktivní', MotoGoColors.greenPale, MotoGoColors.greenDark),
      ResStatus.nadchazejici => ('Nadcházející', const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      ResStatus.dokoncene => ('Dokončené', MotoGoColors.g100, MotoGoColors.g400),
      ResStatus.cancelled => ('Zrušené', const Color(0xFFFEE2E2), MotoGoColors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(50)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}
