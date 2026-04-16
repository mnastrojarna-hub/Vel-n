import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../booking/booking_provider.dart';
import '../catalog/catalog_provider.dart';
import '../reservations/reservation_provider.dart';

/// Payment success / confirmation screen — mirrors s-success from templates-done.js.
/// Shows animated checkmark, booking details, security tips.
class PaymentConfirmationScreen extends ConsumerStatefulWidget {
  const PaymentConfirmationScreen({super.key});

  @override
  ConsumerState<PaymentConfirmationScreen> createState() =>
      _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState
    extends ConsumerState<PaymentConfirmationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final moto = ref.watch(bookingMotoProvider);
    final dateFmt = DateFormat('d. M. yyyy');

    return Scaffold(
      backgroundColor: MotoGoColors.dark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated checkmark ring
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: MotoGoColors.green, width: 4),
                    ),
                    child: const Center(
                      child: Text(
                        '\u2713',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: MotoGoColors.green,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  t(context).tr('successTitle'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  t(context).tr('successSubtitle'),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 20),

                // Booking details card
                if (draft.motoName != null || draft.startDate != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(MotoGoTheme.radiusSm),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (draft.motoName != null)
                          _detailRow(
                            '\uD83C\uDFCD\uFE0F',
                            draft.motoName!,
                            bold: true,
                          ),
                        if (draft.startDate != null &&
                            draft.endDate != null) ...[
                          const SizedBox(height: 8),
                          _detailRow(
                            '\uD83D\uDCC5',
                            '${dateFmt.format(draft.startDate!)} \u2013 ${dateFmt.format(draft.endDate!)}',
                          ),
                        ],
                        if (moto?.branchName != null) ...[
                          const SizedBox(height: 8),
                          _detailRow(
                            '\uD83D\uDCCD',
                            moto!.branchName!,
                          ),
                        ],
                        if (draft.pickupTime != null) ...[
                          const SizedBox(height: 8),
                          _detailRow(
                            '\u23F0',
                            '${t(context).tr('pickupTimeLabel')}: ${draft.pickupTime}',
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Email confirmation info
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenPale.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(MotoGoTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Text('\uD83D\uDCE7',
                          style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t(context).tr('successEmailSent'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Security tips
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MotoGoColors.amberBg,
                    borderRadius:
                        BorderRadius.circular(MotoGoTheme.radiusSm),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '\u26A0\uFE0F ${t(context).tr('successSafetyTitle')}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t(context).tr('successSafetyTips'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78350F),
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Sync badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    '\uD83D\uDCE1 ${t(context).tr('successSynced')}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: MotoGoColors.g400,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // CTA button
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(reservationsProvider);
                    context.go(Routes.reservations);
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                      '${t(context).tr('successCta')} \u2192'),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String emoji, String text, {bool bold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}
