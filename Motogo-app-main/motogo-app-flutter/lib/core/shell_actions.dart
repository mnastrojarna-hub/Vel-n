import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'i18n/i18n_provider.dart';
import 'pending_booking_fab_provider.dart';
import 'pending_sos_fab_provider.dart';
import '../features/payment/payment_provider.dart';

/// Pokračovat v rozdělané platbě rezervace (PM-7, přesunuto beze změny z
/// `_BookingFab` v `AppShell`; sdílí ho FAB i v2 obrazovky).
void openPendingPayment(BuildContext context, WidgetRef ref, PendingBooking booking) {
  // Resume rozdělané platby: PaymentScreen NESMÍ spoléhat na booking
  // draft (po restartu/úklidu je prázdný → „Motorka × 0 dny, 0 Kč
  // zdarma" a vznikaly nesmyslné rezervace). Předáme kontext s ID a
  // částkou přímo z DB řádku rezervace.
  ref.read(paymentContextProvider.notifier).state = PaymentContext(
    flowType: PaymentFlowType.booking,
    bookingId: booking.id,
    amount: booking.totalPrice,
    label: t(context).tr('bookingReservation'),
    bookingCreatedAt: booking.createdAt,
  );
  context.push(Routes.payment);
}

/// Dokončit SOS hlášení — výběr náhradní motorky (PM-7, z `_SosFab`).
void openPendingSos(BuildContext context, WidgetRef ref, PendingSosReplacement incident) {
  context.push(Routes.sosReplacement);
}
