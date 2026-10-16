import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/i18n/i18n_provider.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../payment/net_error.dart';
import '../payment/payment_provider.dart';
import '../payment/payment_ui_helpers.dart' show signInAgain;
import '../payment/widgets/payment_error_sheet.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';

/// Server obnovu odmítl (RPC `customer_restore_booking`, kód chyby).
class RestoreRefused implements Exception {
  final String code;
  /// `moto_unavailable`: moto_overlap | own_overlap | branch_closed | trailer.
  final String? reason;
  /// `voucher_unavailable` / `promo_unavailable`: kód slevy.
  final String? discountCode;
  const RestoreRefused(this.code, {this.reason, this.discountCode});
}

/// Kód „obnova se na serveru právě nasazuje" (RPC v DB zatím není).
const restoreUpdatingCode = 'restore_unavailable';

/// „Obnovit a zaplatit" zrušenou rezervaci (D3, rozhodnutí majitele 2026-10-16:
/// „obnovit a zaplatit by mělo být jako možnost").
///
/// Obnova jde přes RPC `customer_restore_booking` (SQL 20261016p2): ověří
/// vlastníka, stav, termín, volnou motorku a platnost slev, znovu uplatní
/// poukazy (nesmí se použít dvakrát) a založí nové 30min okno na zaplacení,
/// během kterého ani běžící platbu nezruší cron. Každé odmítnutí má přesnou
/// hlášku s krokem, který opravdu něco dělá — bez kontaktů (D5).
Future<void> restoreAndPay(
    BuildContext context, WidgetRef ref, Reservation res) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final startDay =
      DateTime(res.startDate.year, res.startDate.month, res.startDate.day);
  // Rezervace začínající dnes má vlastní text (obnovit jde jen od zítřka).
  final startsToday = startDay == today;
  if (!startDay.isAfter(today)) {
    _showRefusal(context, ref, res,
        RestoreRefused('date_passed', reason: startsToday ? 'today' : null));
    return;
  }

  Map<String, dynamic> r;
  try {
    r = await restoreBookingRpc(res.id);
  } on RestoreRefused catch (e) {
    if (!context.mounted) return;
    if (e.code == 'not_cancelled') {
      // Obnova už proběhla (odpověď předchozího pokusu se ztratila po
      // timeoutu) a rezervace čeká na platbu → rovnou k platbě.
      final again = await restoredAwaitingPayment(res.id);
      if (!context.mounted) return;
      if (again != null) {
        _goPay(context, ref, res, again);
        return;
      }
    }
    _showRefusal(context, ref, res, e);
    return;
  } catch (e) {
    debugPrint('[RESTORE] Error restoring booking: $e');
    if (!context.mounted) return;
    final tr = t(context);
    final network = isNetworkError(e);
    PaymentErrorSheet.show(
      context,
      title: tr.tr('cannotRestore'),
      message: tr.tr(network ? 'psRestoreNet' : 'pdRestoreServer'),
      buttonLabel: tr.tr('retry'),
      onButton: () {
        if (context.mounted) restoreAndPay(context, ref, res);
      },
    );
    return;
  }

  if (!context.mounted) return;
  _goPay(context, ref, res, r);
}

/// Obnovená rezervace → platba (okno na zaplacení běží od obnovy).
void _goPay(BuildContext context, WidgetRef ref, Reservation res, Map<String, dynamic> r) {
  ref.invalidate(reservationsProvider);
  ref.invalidate(reservationByIdProvider(res.id));
  ref.read(paymentContextProvider.notifier).state = PaymentContext(
    flowType: PaymentFlowType.booking,
    bookingId: res.id,
    // Částka k zaplacení podle SERVERU (po obnově, i s případným dorovnáním).
    amount: (r['total_price'] as num?)?.toDouble() ?? res.totalPrice,
    label: t(context).tr('restorePaymentLabel'),
    // Nové okno na zaplacení běží od obnovy (stejně jako na serveru).
    bookingCreatedAt: DateTime.tryParse('${r['restored_at'] ?? ''}')?.toLocal(),
    isRestore: true,
  );
  context.push(Routes.payment);
}

/// Rezervace je už obnovená v appce a čeká na zaplacení (v okně 30 min od
/// obnovy) → `{restored_at, total_price}`, jinak null. Pro „obnovu" po ztracené
/// odpovědi: server pak hlásí `not_cancelled`, ale zákazník chce zaplatit.
Future<Map<String, dynamic>?> restoredAwaitingPayment(String bookingId) async {
  try {
    final row = await MotoGoSupabase.client
        .from('bookings')
        .select('status, payment_status, total_price, restored_at, restored_by_source')
        .eq('id', bookingId)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    if (row == null) return null;
    final at = DateTime.tryParse('${row['restored_at'] ?? ''}');
    if (row['status'] != 'pending' ||
        row['payment_status'] != 'unpaid' ||
        row['restored_by_source'] != 'app' ||
        at == null ||
        DateTime.now().difference(at.toLocal()) >= paymentTimeoutDuration) {
      return null;
    }
    return {'restored_at': row['restored_at'], 'total_price': row['total_price']};
  } catch (e) {
    debugPrint('[RESTORE] re-read failed: $e');
    return null;
  }
}

/// Obnova přes RPC → `{success, restored_at, total_price, …}`, jinak
/// [RestoreRefused]. RPC v DB ještě není → [restoreUpdatingCode].
Future<Map<String, dynamic>> restoreBookingRpc(String bookingId) async {
  try {
    final r = await MotoGoSupabase.client.rpc('customer_restore_booking',
        params: {'p_booking_id': bookingId}).timeout(const Duration(seconds: 15));
    if (r is Map && r['success'] == true) return Map<String, dynamic>.from(r);
    if (r is Map && r['error'] != null) {
      throw RestoreRefused('${r['error']}',
          reason: r['reason']?.toString(), discountCode: r['code']?.toString());
    }
    throw const RestoreRefused('unknown');
  } on PostgrestException catch (e) {
    final missing = e.code == 'PGRST202' ||
        e.code == '42883' ||
        e.message.contains('customer_restore_booking');
    if (!missing) rethrow;
    throw const RestoreRefused(restoreUpdatingCode);
  }
}

/// Text odmítnutí obnovy (čistá funkce kvůli testům): klíč + dosazení kódu.
String restoreRefusalText(AppTranslations tr, RestoreRefused e) {
  final key = switch (e.code) {
    'forbidden' => 'pdRestoreForbidden',
    'not_found' => 'pdRestoreNotFound',
    'not_cancelled' => 'pdRestoreNotCancelled',
    'not_restorable' => 'pdRestoreNotRestorable',
    'cancelled_by_staff' => 'pdRestoreByStaffCancel',
    'date_passed' => e.reason == 'today' ? 'pdRestoreStartsToday' : 'restoreDatePassed',
    'restore_limit' => 'pdRestoreLimit',
    'voucher_unavailable' => 'pdRestoreVoucher',
    'promo_unavailable' => 'pdRestorePromo',
    'price_changed' => 'pdRestorePriceChanged',
    'moto_unavailable' => switch (e.reason) {
        'own_overlap' => 'pdRestoreOwnOverlap',
        'branch_closed' => 'pdRestoreBranchClosed',
        'trailer' => 'pdRestoreTrailer',
        _ => 'restoreMotoOccupied',
      },
    restoreUpdatingCode => 'pdRestoreUpdating',
    _ => 'pdRestoreServer',
  };
  return tr.tr(key).replaceAll('{code}', e.discountCode ?? '');
}

void _showRefusal(BuildContext context, WidgetRef ref, Reservation res, RestoreRefused e) {
  final tr = t(context);
  final motoRoute = res.motoId != null ? '/moto/${res.motoId}' : Routes.search;
  String title = tr.tr('cannotRestore');
  String label;
  VoidCallback onTap;
  String? second;
  VoidCallback? onSecond;
  switch (e.code) {
    case 'forbidden':
      label = tr.tr('login');
      onTap = () => signInAgain(context);
    case 'not_found':
      label = tr.tr('psMyReservations');
      onTap = () {
        ref.invalidate(reservationsProvider);
        context.go(Routes.reservations);
      };
    case 'not_cancelled':
      label = tr.tr('psOpenReservation');
      onTap = () {
        ref.invalidate(reservationByIdProvider(res.id));
        context.go('/reservations/${res.id}');
      };
    case 'moto_unavailable':
      title = tr.tr('motoOccupiedTitle');
      label = tr.tr('psChangeDates');
      onTap = () => context.go(motoRoute);
      second = tr.tr('psOtherMoto');
      onSecond = () => context.go(Routes.search);
    case 'not_restorable':
    case 'cancelled_by_staff':
    case 'date_passed':
    case 'restore_limit':
    case 'voucher_unavailable':
    case 'promo_unavailable':
    case 'price_changed':
      // Obnova nejde (termín uplynul, zrušila obsluha, limit, sleva, změněný
      // ceník) → nová rezervace téže motorky (výběr termínu), nebo jiná motorka.
      label = tr.tr('psPickAgain');
      onTap = () => context.go(motoRoute);
      second = tr.tr('psOtherMoto');
      onSecond = () => context.go(Routes.search);
    default:
      // Aktualizace serveru / neznámý kód (chyba serveru) → nic se
      // nezměnilo, „Zkusit znovu".
      label = tr.tr('retry');
      onTap = () => restoreAndPay(context, ref, res);
  }
  PaymentErrorSheet.show(
    context,
    title: title,
    message: restoreRefusalText(tr, e),
    buttonLabel: label,
    onButton: () {
      if (context.mounted) onTap();
    },
    secondaryLabel: second,
    onSecondary: onSecond == null
        ? null
        : () {
            if (context.mounted) onSecond!();
          },
  );
}
