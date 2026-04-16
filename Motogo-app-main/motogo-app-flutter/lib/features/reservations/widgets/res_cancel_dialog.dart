import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
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
      title: Text(t(context).tr('cancelReservationQ'), style: const TextStyle(fontWeight: FontWeight.w800)),
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
                Text('${t(context).tr('stornoConditions')}:', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                Text(t(context).tr('stornoRules'), style: const TextStyle(fontSize: 10, color: MotoGoColors.g600)),
                const SizedBox(height: 4),
                Text(
                  '${t(context).tr('currentlyRefund')}: $pct% (${refund.toStringAsFixed(0)} Kč)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: t(context).tr('cancelReasonHint'),
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
    final defaultReason = t(context).tr('customerCancelled');
    final err = await cancelBooking(widget.reservation.id, _reason.isNotEmpty ? _reason : defaultReason);
    if (!mounted) return;
    Navigator.pop(context);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context).tr('cancelError')}: $err')));
    }
  }
}
