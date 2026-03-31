import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/price_calculator.dart';
import '../booking/widgets/address_picker.dart';
import '../catalog/moto_model.dart';
import '../catalog/catalog_provider.dart';
import '../catalog/widgets/availability_calendar.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';

/// Reservation edit — mirrors s-edit-res from templates-res-edit.js.
/// Tabs: Prodloužit (extend) / Zkrátit (shorten).
/// Shows calendar, address change, price diff, payment/refund.
class ReservationEditScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const ReservationEditScreen({super.key, required this.bookingId});

  @override
  ConsumerState<ReservationEditScreen> createState() => _EditState();
}

class _EditState extends ConsumerState<ReservationEditScreen> {
  String _tab = 'extend'; // 'extend' or 'shorten'
  DateTime? _newStart;
  DateTime? _newEnd;
  double _returnDelivFee = 0;
  bool _saving = false;

  Reservation? _booking;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    final res = await ref.read(reservationByIdProvider(widget.bookingId).future);
    if (res != null && mounted) {
      setState(() {
        _booking = res;
        _isActive = res.displayStatus == ResStatus.aktivni;
        _newStart = res.startDate;
        _newEnd = res.endDate;
      });
    }
  }

  int get _origDays => _booking == null ? 0 : _booking!.dayCount;
  int get _newDays {
    if (_newStart == null || _newEnd == null) return _origDays;
    return _newEnd!.difference(_newStart!).inDays + 1;
  }
  int get _diffDays => _newDays - _origDays;

  double get _dailyPrice {
    // Estimate from total / days
    if (_booking == null || _origDays == 0) return 0;
    return _booking!.totalPrice / _origDays;
  }

  double get _priceDiff {
    if (_tab == 'extend') {
      return _diffDays * _dailyPrice + _returnDelivFee;
    } else {
      // Shorten — refund with storno conditions
      final removedDays = -_diffDays;
      if (removedDays <= 0) return 0;
      final rawRefund = removedDays * _dailyPrice;
      final pct = StornoCalc.refundPercent(_newEnd ?? _booking!.endDate);
      return -(rawRefund * pct / 100);
    }
  }

  Future<void> _save() async {
    if (_booking == null || _newStart == null || _newEnd == null) return;
    if (_newDays < 1) {
      showMotoGoToast(context, icon: '⚠️', title: 'Chyba', message: 'Min. 1 den');
      return;
    }

    setState(() => _saving = true);
    try {
      final changes = <String, dynamic>{
        'start_date': _newStart!.toIso8601String().substring(0, 10),
        'end_date': _newEnd!.toIso8601String().substring(0, 10),
      };

      if (_priceDiff > 0) {
        // Extension — needs extra payment
        changes['total_price'] = _booking!.totalPrice + _priceDiff;
        // Navigate to payment for the diff
        // For now, save and show toast
        await MotoGoSupabase.client.from('bookings').update(changes).eq('id', widget.bookingId);
        if (mounted) {
          showMotoGoToast(context, icon: '✓', title: 'Uloženo', message: 'Doplatek ${_priceDiff.toStringAsFixed(0)} Kč');
          ref.invalidate(reservationsProvider);
          context.go(Routes.reservations);
        }
      } else if (_priceDiff < 0) {
        // Shortening — refund
        changes['total_price'] = _booking!.totalPrice + _priceDiff; // priceDiff is negative
        await MotoGoSupabase.client.from('bookings').update(changes).eq('id', widget.bookingId);
        if (mounted) {
          showMotoGoToast(context, icon: '✓', title: 'Zkráceno', message: 'Vráceno ${(-_priceDiff).toStringAsFixed(0)} Kč');
          ref.invalidate(reservationsProvider);
          context.go(Routes.reservations);
        }
      } else {
        // No price change
        await MotoGoSupabase.client.from('bookings').update(changes).eq('id', widget.bookingId);
        if (mounted) {
          showMotoGoToast(context, icon: '✓', title: 'Uloženo', message: 'Změny uloženy');
          ref.invalidate(reservationsProvider);
          context.go(Routes.reservations);
        }
      }
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: 'Chyba', message: '$e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_booking == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: MotoGoColors.green)));
    }
    final bookedAsync = ref.watch(bookedDatesProvider(_booking!.motoId ?? ''));

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 14),
                  decoration: const BoxDecoration(color: MotoGoColors.dark, borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
                  child: Row(children: [
                    GestureDetector(onTap: () => context.pop(),
                      child: Container(width: 36, height: 36, decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                        child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))))),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Upravit rezervaci · ${_booking!.motoName}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                      Text('${_booking!.dateRange} · $_origDays ${_origDays == 1 ? "den" : _origDays < 5 ? "dny" : "dní"}',
                          style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    ]),
                  ]),
                ),
              ),

              // Tab buttons
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
                    _TabBtn(label: '📅 Prodloužit', active: _tab == 'extend', onTap: () => setState(() { _tab = 'extend'; _newStart = _booking!.startDate; _newEnd = _booking!.endDate; })),
                    const SizedBox(width: 6),
                    _TabBtn(label: '✂️ Zkrátit', active: _tab == 'shorten', onTap: () => setState(() { _tab = 'shorten'; _newStart = _booking!.startDate; _newEnd = _booking!.endDate; })),
                  ]),
                ),
              ),

              // Storno note for shorten
              if (_tab == 'shorten')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
                      child: const Text(
                        'Storno podmínky: 7+ dní = 100% · 2–7 dní = 50% · <2 dny = 0%',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                      ),
                    ),
                  ),
                ),

              // Calendar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                      boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_tab == 'extend' ? 'Klikněte na nový poslední den' : 'Klikněte na nový konec (dříve)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
                        const SizedBox(height: 8),
                        AvailabilityCalendar(
                          bookedDates: bookedAsync.valueOrNull ?? [],
                          selectedStart: _newStart,
                          selectedEnd: _newEnd,
                          onRangeSelected: (s, e) {
                            setState(() { _newStart = s; _newEnd = e; });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Price diff summary
              if (_diffDays != 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Původní délka', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                          Text('$_origDays dní', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
                        ]),
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Nová délka', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                          Text('$_newDays dní', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _diffDays > 0 ? MotoGoColors.greenDarker : MotoGoColors.red)),
                        ]),
                        const Divider(height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(_priceDiff > 0 ? 'Doplatek' : 'Vrácení', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                          Text('${_priceDiff > 0 ? "+" : ""}${_priceDiff.toStringAsFixed(0)} Kč',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _priceDiff > 0 ? MotoGoColors.red : MotoGoColors.greenDarker)),
                        ]),
                        if (_tab == 'shorten') ...[
                          const SizedBox(height: 4),
                          Text('Vrácení ${StornoCalc.refundPercent(_newEnd ?? _booking!.endDate)}%',
                              style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                        ],
                      ]),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // Save button
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(color: Colors.white,
                boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))]),
              child: ElevatedButton(
                onPressed: (_saving || _diffDays == 0) ? null : _save,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_priceDiff > 0
                        ? 'Pokračovat k platbě (+${_priceDiff.toStringAsFixed(0)} Kč) →'
                        : _priceDiff < 0
                            ? 'Uložit a vrátit ${(-_priceDiff).toStringAsFixed(0)} Kč →'
                            : 'Uložit změny →'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _TabBtn({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: active ? MotoGoColors.green : Colors.transparent,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g200),
      ),
      child: Center(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: active ? Colors.white : MotoGoColors.black))),
    ),
  ));
}
