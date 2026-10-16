import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/i18n/i18n_provider.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import '../catalog/catalog_provider.dart';
import '../payment/net_error.dart';
import '../payment/payment_provider.dart';
import '../payment/payment_ui_helpers.dart';
import '../payment/widgets/payment_error_sheet.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';

/// Server obnovu odmítl (RPC `customer_restore_booking`, kód chyby).
class _RestoreRefused implements Exception {
  final String code;
  const _RestoreRefused(this.code);
}

/// „Obnovit a zaplatit" zrušenou rezervaci (2026-10-16).
///
/// Rozlišuje skutečné příčiny: výpadek spojení („zkus znovu", nic se
/// nezměnilo) ≠ obsazená motorka ≠ jiná chyba — dřív se KAŽDÁ chyba hlásila
/// jako „motorka je obsazená" a zákazník skončil ve vyhledávání.
///
/// Obnova jde JEN přes RPC `customer_restore_booking` (nové 30min okno na
/// zaplacení, návrh SQL D3 čeká na schválení majitele). Dokud RPC v DB není,
/// appka rezervaci sama NEOBNOVUJE: dřívější přímý zápis (bez `restored_at`)
/// nechal cron `auto_cancel_expired_pending()` rezervaci do 2 minut znovu
/// zrušit (+ storno e-mail), zatímco platba odpočítávala 30 minut — a platba
/// za mezitím obsazenou motorku skončila stržením bez rezervace. Zákazník
/// místo toho dostane „Napiš nám" (obnovu udělá obsluha ve Velíně).
Future<void> restoreAndPay(
    BuildContext context, WidgetRef ref, Reservation res) async {
  final tr = t(context);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final startDay =
      DateTime(res.startDate.year, res.startDate.month, res.startDate.day);

  void occupied() {
    showMotoGoToast(context,
        icon: '🏍️',
        title: tr.tr('motoOccupiedTitle'),
        message: tr.tr('restoreMotoOccupied'));
    context.go(Routes.search);
  }

  // Obnova v appce teď nejde (RPC chybí) → nic se nezměnilo, „Napsat nám".
  void byStaff() {
    PaymentErrorSheet.show(
      context,
      title: tr.tr('cannotRestore'),
      message: tr.tr('fxRestoreByStaff'),
      buttonLabel: tr.tr('psWriteUs'),
      onButton: () {
        if (context.mounted) openContactUs(context);
      },
    );
  }

  void failed({required bool network}) {
    PaymentErrorSheet.show(
      context,
      title: tr.tr('cannotRestore'),
      message: tr.tr(network ? 'psRestoreNet' : 'psRestoreFail'),
      buttonLabel: tr.tr('retry'),
      onButton: () {
        if (context.mounted) restoreAndPay(context, ref, res);
      },
      secondaryLabel: network ? null : tr.tr('psWriteUs'),
      onSecondary: network ? null : () => openContactUs(context),
    );
  }

  if (!startDay.isAfter(today)) {
    showMotoGoToast(context,
        icon: '📅',
        title: tr.tr('cannotRestore'),
        message: tr.tr('restoreDatePassed'));
    context.go(Routes.search);
    return;
  }
  if (res.motoId == null) {
    occupied();
    return;
  }

  final avail = await checkMotoAvailabilityTri(
      res.motoId!, res.startDate, res.endDate,
      excludeBookingId: res.id);
  if (!context.mounted) return;
  if (avail == MotoAvailability.unknown) {
    failed(network: true);
    return;
  }
  if (avail == MotoAvailability.busy) {
    occupied();
    return;
  }

  DateTime? windowStart;
  try {
    windowStart = await _restore(res.id);
  } on _RestoreRefused catch (e) {
    if (!context.mounted) return;
    if (e.code == 'moto_unavailable') {
      occupied();
    } else if (e.code == _restoreUnavailable) {
      byStaff();
    } else if (e.code == 'date_passed') {
      showMotoGoToast(context,
          icon: '📅',
          title: tr.tr('cannotRestore'),
          message: tr.tr('restoreDatePassed'));
    } else {
      failed(network: false);
    }
    return;
  } catch (e) {
    debugPrint('[RESTORE] Error restoring booking: $e');
    if (!context.mounted) return;
    final raw = '$e';
    if (raw.contains('Překrývající se rezervace') ||
        raw.contains('přiřazen jako vozík')) {
      occupied();
    } else {
      failed(network: isNetworkError(e));
    }
    return;
  }

  if (!context.mounted) return;
  ref.invalidate(reservationsProvider);
  ref.invalidate(reservationByIdProvider(res.id));
  ref.read(paymentContextProvider.notifier).state = PaymentContext(
    flowType: PaymentFlowType.booking,
    bookingId: res.id,
    amount: res.totalPrice,
    label: tr.tr('restorePaymentLabel'),
    // Okno na zaplacení od okamžiku obnovy (RPC) — jinak od otevření platby.
    bookingCreatedAt: windowStart,
    isRestore: true,
  );
  context.push(Routes.payment);
}

/// Kód „obnova v appce teď nejde" (RPC v DB chybí).
const _restoreUnavailable = 'restore_unavailable';

/// Obnova přes RPC. Vrací začátek nového okna na zaplacení (z RPC), jinak
/// null. RPC v DB není → [_RestoreRefused] `restore_unavailable` (žádný
/// přímý zápis, viz [restoreAndPay]).
Future<DateTime?> _restore(String bookingId) async {
  try {
    final r = await MotoGoSupabase.client.rpc('customer_restore_booking',
        params: {'p_booking_id': bookingId}).timeout(const Duration(seconds: 15));
    if (r is Map && r['success'] == true) {
      return DateTime.tryParse('${r['restored_at'] ?? ''}')?.toLocal();
    }
    if (r is Map && r['error'] != null) throw _RestoreRefused('${r['error']}');
    return null;
  } on PostgrestException catch (e) {
    // RPC v DB zatím není (D3) → obnovu udělá obsluha (žádný přímý zápis).
    final missing = e.code == 'PGRST202' ||
        e.code == '42883' ||
        e.message.contains('customer_restore_booking');
    if (!missing) rethrow;
    throw const _RestoreRefused(_restoreUnavailable);
  }
}
