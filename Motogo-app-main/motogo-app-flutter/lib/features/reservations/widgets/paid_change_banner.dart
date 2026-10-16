import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/paid_change_queue.dart';
import '../../../core/theme.dart';
import '../../payment/paid_change_outcomes.dart' show paidChangeFailureText;
import '../reservation_provider.dart';

/// Řádek v detailu rezervace, dokud se zaplacená výměna / úprava zapisuje
/// (D6): „Výměna motorky se dokončuje…". Trvalé selhání ukáže jednou
/// i s tím, co se děje s doplatkem (vratka), a po „Rozumím" zmizí.
class PaidChangeBanner extends ConsumerStatefulWidget {
  final String bookingId;
  const PaidChangeBanner({super.key, required this.bookingId});

  @override
  ConsumerState<PaidChangeBanner> createState() => _PaidChangeBannerState();
}

class _PaidChangeBannerState extends ConsumerState<PaidChangeBanner> {
  List<PaidChangeEntry> _entries = const [];
  StreamSubscription<PaidChangeEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = PaidChangeQueue.events.listen((ev) {
      if (ev.entry.bookingId != widget.bookingId || !mounted) return;
      if (ev.result.status == PaidChangeStatus.done) {
        ref.invalidate(reservationByIdProvider(widget.bookingId));
        ref.invalidate(reservationsProvider);
      }
      _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await PaidChangeQueue.forBooking(widget.bookingId);
    if (mounted) setState(() => _entries = list);
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();
    final tr = t(context);
    final failed = _entries.where((e) => e.isFailed).firstOrNull;
    if (failed != null) {
      final f = failed.failure ?? const {};
      return _box(
        color: MotoGoColors.redBg,
        border: MotoGoColors.red,
        icon: '!',
        title: tr.tr(failed.isSwap ? 'pdSwapFailedTitle' : 'pdEditFailedTitle'),
        text: paidChangeFailureText(tr,
            reason: f['reason']?.toString(),
            refund: '${f['refund'] ?? 'auto'}',
            amount: (f['amount'] as num?)?.toDouble() ?? failed.charge),
        action: TextButton(
          onPressed: () async {
            await PaidChangeQueue.acknowledge(failed.key);
            _load();
          },
          child: Text(tr.tr('pdUnderstood')),
        ),
      );
    }
    final swap = _entries.first.isSwap;
    return _box(
      color: MotoGoColors.amberBg,
      border: MotoGoColors.amberBorder,
      icon: '⏳',
      title: tr.tr(swap ? 'pdSwapCompletingTitle' : 'pdEditCompletingTitle'),
      text: tr.tr(swap ? 'pdSwapCompletingShort' : 'pdEditCompletingShort'),
    );
  }

  Widget _box({
    required Color color,
    required Color border,
    required String icon,
    required String title,
    required String text,
    Widget? action,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$icon  $title',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 4),
          Text(text,
              style: const TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: MotoGoColors.g600)),
          if (action != null) Align(alignment: Alignment.centerRight, child: action),
        ]),
      );
}
