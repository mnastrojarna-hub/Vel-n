import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';

/// Cancel reservation confirmation dialog with storno policy info.
class ResCancelDialog extends StatefulWidget {
  final Reservation reservation;
  const ResCancelDialog({super.key, required this.reservation});

  @override
  State<ResCancelDialog> createState() => _ResCancelDialogState();
}

class _ResCancelDialogState extends State<ResCancelDialog> {
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: pct == 100 ? MotoGoColors.greenPale : (pct == 50 ? MotoGoColors.amberBg : MotoGoColors.redBg),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Storno podmínky:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                const Text('7+ dní = 100% · 2–7 dní = 50% · <2 dny = 0%', style: TextStyle(fontSize: 10, color: MotoGoColors.g600)),
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
