import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'router.dart';
import 'i18n/i18n_provider.dart';
import 'pending_booking_fab_provider.dart';
import 'pending_sos_fab_provider.dart';
import 'shell_actions.dart';
import 'v2/chrome/mg_status_strip.dart';
import 'widgets/error_feedback.dart' show showErrorSnack;
import 'widgets/moto_fx.dart';
import '../features/payment/payment_provider.dart';
import '../features/payment/payment_ui_helpers.dart';

// Plovoucí panely shellu — PŘESUNUTO beze změny z app_shell.dart (PM-2):
// `_BookingFab` → [ShellBookingFab], `_VerifyingFab` → [ShellVerifyingFab],
// `_SosFab` → [ShellSosFab]; zbytek v shell_fabs_b.dart. Jediný přídavek:
// `v2: true` vykreslí TÝMŽ closures v2 stavový proužek (`MgStatusStrip`).

// ═══════════════════════════════════════════════════════════════════════
// FAB Bars — shared UI pattern: green main btn (left pill) + red X (right pill)
// Mirrors .cart-fab-bar / .cart-fab-btn / .cart-fab-clear from elements.css
// ═══════════════════════════════════════════════════════════════════════

const kShellFabShadow = [
  BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 6)),
];

/// Booking FAB — "Dokončit rezervaci · M:SS" with countdown.
class ShellBookingFab extends ConsumerWidget {
  final PendingBooking booking;
  final bool v2;
  const ShellBookingFab({super.key, required this.booking, this.v2 = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (booking.verifying) return ShellVerifyingFab(booking: booking, v2: v2);
    // Hoisted beze změny (stejné tělo pro starou pilulku i v2 proužek).
    Future<void> onCancel() async {
      // Tlačítko sedí hned vedle „zaplatit" a zrušení je nevratné —
      // bez potvrzení stačil překlep a rozdělaná rezervace byla pryč.
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(t(ctx).tr('cancelReservationQ')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(t(ctx).tr('back')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(t(ctx).tr('cancelReservationBtn'),
                      style: const TextStyle(color: MotoGoColors.red)),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok || !context.mounted) return;
      // Selhání (offline / timeout) → CO, PROČ a JAK + „Zkusit znovu"
      // (dřív holé „Chyba storna").
      Future<void> doCancel() async {
        try {
          await cancelPendingBooking(booking.id);
          ref.invalidate(pendingBookingFabProvider);
        } catch (e) {
          if (context.mounted) {
            showErrorSnack(context, t(context).tr('psCancelFailTitle'), e,
                where: 'fab_cancel_pending', onRetry: doCancel, contact: false);
          }
        }
      }
      await doCancel();
    }

    if (v2) {
      return MgStatusStrip(
        kind: MgStripKind.pay,
        title: t(context).tr('completeBookingFab'),
        sub: t(context).trArgs('v2StripTimeLeft', {'t': booking.timeLabel}),
        onTap: () => openPendingPayment(context, ref, booking),
        onDismiss: onCancel,
        dismissLabel: t(context).tr('cancelReservationBtn'),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main green button (left pill)
        PressableScale(
          pressedScale: 0.93,
          onTap: () => openPendingPayment(context, ref, booking),
          child: Container(
            padding: const EdgeInsets.only(left: 24, right: 16, top: 14, bottom: 14),
            decoration: const BoxDecoration(
              color: MotoGoColors.green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(MotoGoRadius.pill),
                bottomLeft: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: kShellFabShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💳', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  '${t(context).tr('completeBookingFab')} · ${booking.timeLabel}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: MotoGoTypo.w800,
                    color: MotoGoColors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Red dismiss button (right pill)
        GestureDetector(
          onTap: onCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            decoration: const BoxDecoration(
              color: Color(0xFFB91C1C),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(MotoGoRadius.pill),
                bottomRight: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: kShellFabShadow,
            ),
            child: const Text(
              '✕',
              style: TextStyle(
                fontSize: 16,
                fontWeight: MotoGoTypo.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// FAB rezervace, jejíž platba už byla odeslána a čeká na potvrzení banky /
/// serveru: NEnabízí další platbu (dvojí platba), jen otevře „Platba se ověřuje".
class ShellVerifyingFab extends ConsumerWidget {
  final PendingBooking booking;
  final bool v2;
  const ShellVerifyingFab({super.key, required this.booking, this.v2 = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    // Hoisted beze změny (stejné tělo pro pilulku i v2 proužek).
    void open() {
      ref.read(paymentOutcomeProvider.notifier).state = pendingBookingOutcome(
        tr,
        bookingId: booking.id,
        verifiedRoute: Routes.success,
      );
      context.push(Routes.paymentResult);
    }

    if (v2) {
      return MgStatusStrip(
        kind: MgStripKind.verifying,
        title: tr.tr('psFabVerifying'),
        sub: tr.tr('v2StripVerifyingSub'),
        onTap: open,
      );
    }
    return Center(
      child: PressableScale(
        pressedScale: 0.93,
        onTap: open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFFFDE68A),
            borderRadius: BorderRadius.all(Radius.circular(MotoGoRadius.pill)),
            boxShadow: kShellFabShadow,
          ),
          child: Text(
            '⏳ ${tr.tr('psFabVerifying')}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
            ),
          ),
        ),
      ),
    );
  }
}

/// SOS FAB — "SOS dokončit" for pending replacement selection.
class ShellSosFab extends ConsumerWidget {
  final PendingSosReplacement incident;
  final bool v2;
  const ShellSosFab({super.key, required this.incident, this.v2 = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hoisted beze změny (stejné tělo pro pilulku i v2 proužek).
    Future<void> onDismiss() async {
      await dismissSosFab(incident.id);
      ref.invalidate(pendingSosFabProvider);
    }

    if (v2) {
      return MgStatusStrip(
        kind: MgStripKind.sos,
        title: t(context).tr('sosCompleteFab'),
        sub: t(context).tr('v2StripSosSub'),
        onTap: () => openPendingSos(context, ref, incident),
        onDismiss: onDismiss,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main green button (left pill)
        PressableScale(
          pressedScale: 0.93,
          onTap: () => openPendingSos(context, ref, incident),
          child: Container(
            padding: const EdgeInsets.only(left: 24, right: 16, top: 14, bottom: 14),
            decoration: const BoxDecoration(
              color: MotoGoColors.green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(MotoGoRadius.pill),
                bottomLeft: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: kShellFabShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🆘', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  t(context).tr('sosCompleteFab'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: MotoGoTypo.w800,
                    color: MotoGoColors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Red dismiss button (right pill)
        GestureDetector(
          onTap: onDismiss,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            decoration: const BoxDecoration(
              color: Color(0xFFB91C1C),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(MotoGoRadius.pill),
                bottomRight: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: kShellFabShadow,
            ),
            child: const Text(
              '✕',
              style: TextStyle(
                fontSize: 16,
                fontWeight: MotoGoTypo.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

