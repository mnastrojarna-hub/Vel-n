import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../gear_rental/gear_contract.dart';
import '../reservation_models.dart';

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
    payGearBooking(context, ref, bookingId: r.id, amount: r.totalPrice);
  } else {
    await openGearWeb(gearWebResumeUri(r.id, lang));
  }
}
