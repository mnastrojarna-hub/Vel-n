import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';
import 'widgets/reservation_card.dart';

/// Reservations list — mirrors s-res from templates-res.js + reservations-ui.js.
/// Tabs: All, Active, Upcoming, Completed, Cancelled.
/// Realtime-updated via Supabase stream.
class ReservationsScreen extends ConsumerWidget {
  const ReservationsScreen({super.key});

  static const _filters = [
    ('all', 'Vše'),
    ('aktivni', 'Aktivní'),
    ('nadchazejici', 'Nadcházející'),
    ('dokoncene', 'Dokončené'),
    ('cancelled', 'Zrušené'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(resFilterProvider);
    final reservationsAsync = ref.watch(filteredReservationsProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 16, 20, 16,
              ),
              decoration: const BoxDecoration(
                color: MotoGoColors.dark,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Moje rezervace', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  SizedBox(height: 4),
                  Text('Přehled všech rezervací', style: TextStyle(fontSize: 12, color: Colors.white54)),
                ],
              ),
            ),
          ),

          // Filter chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((f) {
                    final active = filter == f.$1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(f.$2),
                        selected: active,
                        onSelected: (_) {
                          ref.read(resFilterProvider.notifier).state = f.$1;
                        },
                        selectedColor: MotoGoColors.green,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: active ? Colors.white : MotoGoColors.black,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                          side: BorderSide(color: active ? MotoGoColors.green : MotoGoColors.g200),
                        ),
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // List
          reservationsAsync.when(
            data: (reservations) {
              if (reservations.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('📋', style: TextStyle(fontSize: 48)),
                        SizedBox(height: 12),
                        Text('Žádné rezervace', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                        Text('Zarezervujte si motorku', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                      ],
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                sliver: SliverList.builder(
                  itemCount: reservations.length,
                  itemBuilder: (context, index) {
                    final res = reservations[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ReservationCard(
                        reservation: res,
                        onTap: () => context.push('/reservations/${res.id}'),
                        onEdit: () => context.push('/reservations/${res.id}/edit'),
                        onCancel: () => _showCancelDialog(context, ref, res),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Chyba: $e', style: const TextStyle(color: MotoGoColors.red))),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref, Reservation res) {
    showDialog(
      context: context,
      builder: (ctx) => _CancelDialog(reservation: res),
    ).then((_) {
      ref.invalidate(reservationsProvider);
    });
  }
}

/// Cancel booking dialog — mirrors storno logic from booking-edit-price.js.
class _CancelDialog extends StatefulWidget {
  final Reservation reservation;
  const _CancelDialog({required this.reservation});

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  bool _loading = false;
  String _reason = '';

  @override
  Widget build(BuildContext context) {
    final pct = StornoCalc.refundPercent(widget.reservation.startDate);
    final refund = StornoCalc.refundAmount(widget.reservation.totalPrice, widget.reservation.startDate);

    return AlertDialog(
      title: const Text('Zrušit rezervaci?', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.reservation.motoName, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(widget.reservation.dateRange, style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
          const SizedBox(height: 12),
          // Storno conditions
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: pct == 100 ? MotoGoColors.greenPale : (pct == 50 ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Storno podmínky:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                const Text(
                  '7+ dní = 100% · 2–7 dní = 50% · <2 dny = 0%',
                  style: TextStyle(fontSize: 10, color: MotoGoColors.g600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Aktuálně: $pct% vrácení (${refund.toStringAsFixed(0)} Kč)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Důvod storna (volitelné)',
              hintStyle: TextStyle(fontSize: 12),
            ),
            onChanged: (v) => _reason = v,
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Zpět'),
        ),
        TextButton(
          onPressed: _loading ? null : _doCancel,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Zrušit rezervaci', style: TextStyle(color: MotoGoColors.red)),
        ),
      ],
    );
  }

  Future<void> _doCancel() async {
    setState(() => _loading = true);
    final err = await cancelBooking(widget.reservation.id, _reason.isNotEmpty ? _reason : 'Zákazník zrušil');
    if (!mounted) return;
    Navigator.pop(context);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}
