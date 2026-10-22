import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'pending_booking_fab_provider.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_models.dart';
import '../features/booking/v2/booking_carry_v2.dart' show bookingDraftSeedMarkProvider, bookingEntryFilterProvider;
import '../features/catalog/catalog_provider.dart';
import '../features/payment/payment_provider.dart' show lastConfirmedBookingProvider;
import '../features/payment/payment_ui_helpers.dart';
import 'v2/flag/v2_scope.dart';

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
    if (isHome) _resetOnHome(context, ref);
    context.go(route);
  }
}

/// Klepnutí na Domů a rozpracovaná rezervace. Starý vzhled beze změny:
/// zahodí termín, filtr katalogu i rozpracovanou rezervaci. v2 (majitel
/// 2026-10-22: „nikdy nic nevyplňovat dvakrát“) nic nemaže, dokud se od
/// posledního vstupu do formuláře nezaplatila rezervace (stejné pravidlo
/// jako `carryBookingDraft`) — zákazník se podívá na Domů a vrátí se k
/// termínu i k formuláři. Po zaplacení se zahodí draft hotové rezervace
/// a filtr jen s jejím termínem (Domů by jinak nabízelo termín už
/// zarezervované jízdy); termín zvolený až potom zůstává. Odhlášení
/// a „Znovu rezervovat“ resetují dál.
void _resetOnHome(BuildContext context, WidgetRef ref) {
  final v2 = MgV2.peek(context);
  final confirmed = ref.read(lastConfirmedBookingProvider);
  if (v2 && confirmed == ref.read(bookingDraftSeedMarkProvider)) return;
  final f = ref.read(catalogFilterProvider);
  final atEntry = ref.read(bookingEntryFilterProvider);
  final filterOfBooked = atEntry != null && atEntry.$1 == f.startDate && atEntry.$2 == f.endDate;
  ref.read(bookingDraftProvider.notifier).state = BookingDraft();
  ref.read(bookingMotoProvider.notifier).state = null;
  if (!v2 || filterOfBooked) {
    ref.read(catalogFilterProvider.notifier).state = const CatalogFilter();
  }
  if (!v2) return;
  // Čisté kolo: další Domů už nic nemaže.
  ref.read(bookingDraftSeedMarkProvider.notifier).state = confirmed;
  ref.read(bookingEntryFilterProvider.notifier).state = null;
}
