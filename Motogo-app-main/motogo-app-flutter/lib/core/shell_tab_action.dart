import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'pending_booking_fab_provider.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_models.dart';
import '../features/catalog/catalog_provider.dart';
import '../features/payment/payment_ui_helpers.dart';

/// Klepnutí na záložku spodní lišty (PM-1, přesunuto beze změny z
/// `AppShell` — sdílí ho stará i v2 lišta). [isActive] = klepnutá záložka
/// je ta zvýrazněná, [isHome] = záložka Domů, [location] = aktuální poloha.
Future<void> onShellTabTap(
  BuildContext context,
  WidgetRef ref, {
  required String route,
  required bool isActive,
  required bool isHome,
  required String location,
}) async {
  // Běží platba → odchod záložkou jen po potvrzení (výsledek
  // by se ztratil a zákazník by mohl zaplatit podruhé).
  if (ref.read(paymentProcessingProvider)) {
    if (!await confirmLeaveRunningPayment(context)) return;
    if (!context.mounted) return;
    final leave = ref.read(paymentLeaveActionProvider);
    if (leave != null) {
      leave();
      return;
    }
  }
  if (!context.mounted) return;
  // Obrazovky mimo záložky (profil/menu, zprávy, obchod,
  // faktury…) mají zvýrazněný tab Domů, ale poloha není '/'.
  // Klik na Domů tam musí fungovat, ne až přes Rezervace.
  final goHome = isHome && location != Routes.home;
  if (!isActive || goHome) {
    // Reset booking flow when navigating to home tab
    if (isHome) {
      ref.read(bookingDraftProvider.notifier).state = BookingDraft();
      ref.read(bookingMotoProvider.notifier).state = null;
      ref.read(catalogFilterProvider.notifier).state = const CatalogFilter();
    }
    context.go(route);
  }
}
