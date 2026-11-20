import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../../core/v2/flag/v2_scope.dart';
import '../../../core/v2/widgets/mg_dialog.dart';
import '../../auth/widgets/toast_helper.dart';
import '../../gear_rental/gear_contract.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart' show cancelBooking;
import 'gear_booking_api.dart' show refreshGearBookings;

/// Webové odkazy výpůjčky výbavy + zaplacení rozdělané výpůjčky.

const _kWeb = 'https://motogo24.cz';

Uri _web(String path, Map<String, String> q, String lang) => Uri.parse('$_kWeb$path')
    .replace(queryParameters: {...q, if (lang != 'cs') 'lang': lang});

/// Dokončení platby na webu (`/pujceni-obleceni?resume=<id>`).
Uri gearWebResumeUri(String bookingId, String lang) =>
    _web('/pujceni-obleceni', {'resume': bookingId}, lang);

/// Úprava termínu na webu (posun / prodloužení / zkrácení — appka zatím
/// neumí zaplatit doplatek gear změny, viz GEAR_RENTAL_APP_EDIT.md §6).
Uri gearWebEditUri(String bookingId, String lang) =>
    _web('/upravit-rezervaci', {'edit_booking': bookingId, 'edit_tab': 'move'}, lang);

Future<bool> openGearWeb(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Rozdělaná (pending + unpaid) webová výpůjčka, kterou server ještě drží
/// (= RPC `can_pay`; okno 4 h hlídá [Reservation.displayStatus]).
bool gearCanPay(Reservation r) =>
    r.isGearOnly &&
    r.status == 'pending' &&
    r.paymentStatus == 'unpaid' &&
    r.displayStatus != ResStatus.cancelled;

/// „Zaplatit“: platební obrazovka appky, jen když Velín zapnul „Zobrazit
/// v aplikaci“ (jinak ověření platby přímým selectem gear řádek nevidí) —
/// jinak dokončení platby na webu.
Future<void> payGearOrWeb(BuildContext context, WidgetRef ref, Reservation r) async {
  final lang = ref.read(localeProvider).languageCode;
  GearRentalSettings settings;
  try {
    settings = await ref.read(gearRentalSettingsProvider.future);
  } catch (_) {
    settings = const GearRentalSettings();
  }
  if (!context.mounted) return;
  if (settings.appVisible) {
    // Okno na zaplacení běží od vzniku rezervace (server 4 h), ne od otevření platby.
    payGearBooking(context, ref, bookingId: r.id, amount: r.totalPrice, createdAt: r.createdAt);
  } else {
    await openGearWeb(gearWebResumeUri(r.id, lang));
  }
}

/// Zrušit rozdělanou (nezaplacenou) výpůjčku — web „Zrušit rezervaci“ v pruhu
/// nezaplacené výpůjčky: potvrzení → RPC `cancel_booking_tracked` (žádný
/// přímý zápis řádku), pak znovu načíst rezervace.
Future<void> cancelGearPending(BuildContext context, WidgetRef ref, Reservation r) async {
  final tr = t(context);
  final bool? yes;
  if (MgV2.on(context)) {
    yes = await showMgConfirm(
      context,
      title: tr.tr('gearCancelPendingAsk'),
      safeLabel: tr.tr('gearCancelPendingNo'),
      actionLabel: tr.tr('gearCancelPendingYes'),
      destructive: true,
    );
  } else {
    yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(tr.tr('gearCancelPendingAsk'),
            style: const TextStyle(fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr.tr('gearCancelPendingNo'))),
          TextButton(
            key: const ValueKey('gear-cancel-pending-yes'),
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: MotoGoColors.red),
            child: Text(tr.tr('gearCancelPendingYes')),
          ),
        ],
      ),
    );
  }
  if (yes != true || !context.mounted) return;
  final res = await cancelBooking(r.id, tr.tr('gearCancelPendingReason'));
  if (!context.mounted) return;
  refreshGearBookings(ref, r.id);
  showMotoGoToast(context,
      icon: res.ok ? '✓' : '⚠️',
      title: tr.tr(res.ok ? 'success' : 'error'),
      message: tr.tr(res.ok ? 'gearCancelPendingDone' : 'cancelError'));
}
