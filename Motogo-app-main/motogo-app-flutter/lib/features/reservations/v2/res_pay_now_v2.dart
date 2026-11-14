import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/shell_actions.dart';
import '../../../core/v2/widgets/mg_cta.dart';

/// D2 (owner 2026-11-14): the own "Zaplatit rezervaci · částka" button of an
/// unpaid booking on its list card and in its detail. Shown only for the
/// booking the shell pay strip offers (`resPayTarget`); the tap is the
/// strip's own handler [openPendingPayment] with the same booking — the same
/// payment target and amount. Text = the strip's `coPayNowFab`.
class ResPayNowV2 extends ConsumerWidget {
  final PendingBooking booking;
  final MgCtaSize size;
  const ResPayNowV2({super.key, required this.booking, this.size = MgCtaSize.md56});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MgCta(
        key: const ValueKey('res-pay-now'),
        label: t(context).tr('coPayNowFab'),
        price: booking.totalPrice > 0 ? Money.czk(booking.totalPrice) : null,
        onTap: () => openPendingPayment(context, ref, booking),
        size: size,
        arrow: size != MgCtaSize.sm48,
        showMarks: false,
      );
}
