import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'i18n/i18n_provider.dart';
import 'payment_pending_marker.dart' show PaymentMarkerKind;
import 'pending_booking_fab_provider.dart';

/// Oznámení „platba se mezitím potvrdila" po restartu appky (PM-2,
/// přesunuto beze změny z `AppShell.build`; obaluje Scaffold staré i v2
/// lišty, takže kontext má stejné předky — ScaffoldMessenger i router).
class ShellPaidListener extends ConsumerWidget {
  final Widget child;
  const ShellPaidListener({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Platba odeslaná před zabitím appky se mezitím potvrdila → jednou
    // oznámit (jinak by zákazník nevěděl, jestli zaplatil).
    ref.listen<AsyncValue<PaidAfterRestart?>>(paidAfterRestartProvider, (_, next) {
      final paid = next.valueOrNull;
      if (paid == null) return;
      final id = paid.bookingId;
      final tr = t(context);
      // Doplatek úpravy / výměny ≠ „rezervace je potvrzená" (ta byla
      // zaplacená už dřív) — text podle druhu platby.
      final notice = switch (paid.kind) {
        PaymentMarkerKind.edit => 'fxEditPaidNotice',
        PaymentMarkerKind.swap => 'fxSwapPaidNotice',
        PaymentMarkerKind.sos => 'fxSosPaidNotice',
        _ => 'psPaidNotice',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr.tr(notice)),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: tr.tr('psShow'),
          onPressed: () => GoRouter.of(context).go('/reservations/$id'),
        ),
      ));
    });
    return child;
  }
}
