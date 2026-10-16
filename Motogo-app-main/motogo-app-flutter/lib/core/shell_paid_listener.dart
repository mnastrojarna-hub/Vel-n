import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pending_booking_fab_provider.dart';
import '../features/payment/paid_change_outcomes.dart' show paidAfterRestartSnackBar;

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
    // Zaplacenou výměnu zmařila mezitím jiná rezervace → „Motorka je mezitím
    // obsazená" + vratka (text i druh platby řeší paidAfterRestartSnackBar).
    ref.listen<AsyncValue<PaidAfterRestart?>>(paidAfterRestartProvider, (_, next) {
      final paid = next.valueOrNull;
      if (paid == null) return;
      ScaffoldMessenger.of(context).showSnackBar(paidAfterRestartSnackBar(context, paid));
    });
    return child;
  }
}
