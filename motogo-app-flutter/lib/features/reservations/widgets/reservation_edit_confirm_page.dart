import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';

/// Confirmation page shown after successful edit save.
class EditConfirmPage extends StatelessWidget {
  final String title, message;
  final bool isRefund;
  const EditConfirmPage({super.key, required this.title, required this.message, this.isRefund = false});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72,
            decoration: BoxDecoration(
              color: isRefund ? MotoGoColors.amberBg : MotoGoColors.greenPale,
              shape: BoxShape.circle),
            child: Icon(
              isRefund ? Icons.currency_exchange : Icons.check_circle,
              size: 36,
              color: isRefund ? MotoGoColors.amber : MotoGoColors.greenDarker)),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.6, color: MotoGoColors.g600)),
          const SizedBox(height: 28),
          SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: () => context.go(Routes.reservations),
              style: ElevatedButton.styleFrom(
                backgroundColor: MotoGoColors.green, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('ZPĚT NA REZERVACE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                SizedBox(width: 6), Icon(Icons.arrow_forward, size: 16),
              ]))),
        ]),
      )),
    );
  }
}
