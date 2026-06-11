import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';
import 'widgets/reservation_card.dart';

/// Reservations list — mirrors s-res from templates-res.js + reservations-ui.js.
/// Tabs: All, Active, Upcoming, Completed, Cancelled.
/// Realtime-updated via Supabase stream. Swipeable filter switching.
class ReservationsScreen extends ConsumerStatefulWidget {
  const ReservationsScreen({super.key});

  static const _filterKeys = ['all', 'aktivni', 'nadchazejici', 'dokoncene', 'cancelled'];
  static const _filterI18nKeys = ['all', 'active', 'upcoming', 'completed', 'cancelled'];

  static List<(String, String)> _filters(BuildContext context) {
    return List.generate(_filterKeys.length, (i) =>
      (_filterKeys[i], t(context).tr(_filterI18nKeys[i])));
  }

  @override
  ConsumerState<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends ConsumerState<ReservationsScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(reservationsProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _swipeFilter(int direction) {
    final filter = ref.read(resFilterProvider);
    final filters = ReservationsScreen._filterKeys;
    final idx = filters.indexOf(filter);
    final next = (idx + direction).clamp(0, filters.length - 1);
    if (next != idx) {
      ref.read(resFilterProvider.notifier).state = filters[next];
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(resFilterProvider);
    final reservationsAsync = ref.watch(filteredReservationsProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -200) _swipeFilter(1);  // swipe left → next
          if (details.primaryVelocity! > 200) _swipeFilter(-1);  // swipe right → prev
        },
        child: CustomScrollView(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 28, height: 28,
                          decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.motorcycle, size: 16, color: Colors.black))),
                    ),
                    const SizedBox(width: 8),
                    Text(t(context).tr('myReservations'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  ]),
                  const SizedBox(height: 4),
                  Text(t(context).tr('resOverview'), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ],
              ),
            ),
          ),

          // Filter chips — two rows
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ReservationsScreen._filters(context).map((f) {
                  final active = filter == f.$1;
                  return ChoiceChip(
                    label: Text(f.$2),
                    selected: active,
                    onSelected: (_) {
                      ref.read(resFilterProvider.notifier).state = f.$1;
                    },
                    selectedColor: MotoGoColors.green,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: active ? Colors.black : MotoGoColors.black,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                      side: BorderSide(color: active ? MotoGoColors.green : MotoGoColors.g200),
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
            ),
          ),

          // List — swipeable to switch filters
          reservationsAsync.when(
            data: (reservations) {
              if (reservations.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('📋', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(t(context).tr('noReservations'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                        const SizedBox(height: 4),
                        Text(t(context).tr('noReservationsDesc'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => context.go(Routes.search),
                          icon: const Icon(Icons.search, size: 18),
                          label: Text(t(context).tr('noResBookCta')),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
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
            error: (_, __) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 12),
                    Text(t(context).tr('loadingError'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.red)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(reservationsProvider),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(t(context).tr('retry')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
      title: Text(t(context).tr('cancelReservationTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
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
              color: pct == 100 ? MotoGoColors.greenPale : (pct == 50 ? MotoGoColors.amberBg : MotoGoColors.redBg),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(context).tr('stornoConditions'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                Text(
                  t(context).tr('stornoRules'),
                  style: const TextStyle(fontSize: 10, color: MotoGoColors.g600),
                ),
                const SizedBox(height: 4),
                Text(
                  t(context).tr('currentlyRefund').replaceAll('{pct}', '$pct').replaceAll('{amount}', refund.toStringAsFixed(0)),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: t(context).tr('cancelReason'),
              hintStyle: const TextStyle(fontSize: 12),
            ),
            onChanged: (v) => _reason = v,
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t(context).back),
        ),
        TextButton(
          onPressed: _loading ? null : _doCancel,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t(context).tr('cancelReservationBtn'), style: const TextStyle(color: MotoGoColors.red)),
        ),
      ],
    );
  }

  Future<void> _doCancel() async {
    setState(() => _loading = true);
    final err = await cancelBooking(widget.reservation.id, _reason.isNotEmpty ? _reason : t(context).tr('customerCancelled'));
    if (!mounted) return;
    Navigator.pop(context);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}
