import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/offline_guard.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import 'booking_upsell_provider.dart';
import 'payment_provider.dart';

/// Potvrzení odchodu z běžící platby (šipka, systémové „zpět", záložka).
/// true = zákazník chce odejít. Platba může i tak doběhnout — výsledek najde
/// v Rezervacích / e-mailu; nikdy nesmí odejít bez vysvětlení.
Future<bool> confirmLeaveRunningPayment(BuildContext context) async {
  final tr = t(context);
  final leave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr.tr('psLeaveTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(tr.tr('psLeaveBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr.tr('psLeave'),
              style: const TextStyle(color: MotoGoColors.g500)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr.tr('psStay')),
        ),
      ],
    ),
  );
  return leave == true;
}

/// true = obrazovka s [context] je nahoře: nad ní není jiná trasa ve vlastním
/// navigátoru (sheet, Zprávy) ani dialog / sheet v kořenovém navigátoru (ten
/// leží nad celým shellem). Jen pak smí `BackButtonListener` obrazovky
/// převzít systémové „zpět" — jinak ho musí dostat horní dialog / sheet.
bool isTopmostRoute(BuildContext context) {
  // Překryv „Nejsi připojený" leží nad vším (není to trasa) → zpět je jeho.
  if (OfflineGuard.overlayVisible) return false;
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
  var popupOnTop = false;
  Navigator.of(context, rootNavigator: true).popUntil((r) {
    popupOnTop = r is PopupRoute;
    return true; // jen nahlédnout na vrchol, nic nezavírat
  });
  return !popupOnTop;
}

/// „Přihlásit" z chybové hlášky (jiný účet, odmítnuté přihlášení): dokud
/// přihlášení v appce trvá, router by z /login hned vrátil Domů a nic by se
/// nestalo → nejdřív odhlásit, pak přihlašovací obrazovka.
Future<void> signInAgain(BuildContext context) async {
  try {
    await MotoGoSupabase.client.auth.signOut().timeout(const Duration(seconds: 8));
  } catch (_) {/* odhlášení lokálně proběhne i bez sítě */}
  if (context.mounted) context.go(Routes.login);
}

/// Výsledek „Platba se ověřuje" pro rezervaci (nová / dokončovaná / obnovená).
/// [netTrouble] = výsledek neznáme kvůli výpadku spojení (ne kvůli bance) →
/// text řekne pravý důvod. [restore] / [upsell] se uplatní po ověřeném
/// zaplacení (děkovačka „znovu potvrzená", objednávka doplňků).
PaymentOutcome pendingBookingOutcome(
  AppTranslations tr, {
  required String bookingId,
  String? verifiedRoute,
  bool netTrouble = false,
  bool restore = false,
  List<BookingUpsellItem> upsell = const [],
}) =>
    PaymentOutcome(
      kind: PaymentOutcomeKind.pending,
      title: tr.tr('psPendingTitle'),
      subtitle: tr.tr(netTrouble ? 'fxPendingSubNet' : 'psPendingSub'),
      nextStepNote: tr.tr(netTrouble ? 'fxPendingBodyNet' : 'psPendingBody'),
      ctaLabel: tr.tr('psMyReservations'),
      ctaRoute: Routes.reservations,
      verifyBookingId: bookingId,
      verifiedRoute: verifiedRoute ?? Routes.success,
      verifiedRestore: restore,
      verifiedUpsell: upsell,
      notPaidMessage: tr.tr('psNotPaidBooking'),
    );

/// „Platba se ověřuje" pro doplatek úpravy / výměny motorky. [completeKey] =
/// id PaymentIntentu ve frontě zaplacených změn — ověření ji rovnou dokončí (D6).
PaymentOutcome pendingEditOutcome(
  AppTranslations tr, {
  required String bookingId,
  double? expectedTotal,
  bool intentOnly = false,
  bool netTrouble = false,
  String? completeKey,
  required PaymentOutcome verified,
}) =>
    PaymentOutcome(
      kind: PaymentOutcomeKind.pending,
      title: tr.tr('psPendingTitle'),
      subtitle: tr.tr(netTrouble ? 'fxPendingSubNet' : 'psPendingSub'),
      nextStepNote: tr.tr(netTrouble ? 'fxPendingBodyNet' : 'psPendingBodyEdit'),
      ctaLabel: tr.tr('psMyReservations'),
      ctaRoute: Routes.reservations,
      verifyBookingId: bookingId,
      verifyExpectedTotal: expectedTotal,
      verifyIntentOnly: intentOnly,
      verifiedOutcome: verified,
      notPaidMessage: tr.tr('psNotPaidEdit'),
      completeKey: completeKey,
    );

/// „Platba se ověřuje" pro objednávku z e-shopu.
PaymentOutcome pendingOrderOutcome(
  AppTranslations tr, {
  required String orderId,
  bool netTrouble = false,
  required PaymentOutcome verified,
}) =>
    PaymentOutcome(
      kind: PaymentOutcomeKind.pending,
      title: tr.tr('psPendingTitle'),
      subtitle: tr.tr(netTrouble ? 'fxPendingSubNet' : 'psPendingSub'),
      nextStepNote: tr.tr(netTrouble ? 'fxPendingBodyNet' : 'psPendingBodyShop'),
      ctaLabel: tr.tr('psBackToShop'),
      ctaRoute: Routes.shop,
      verifyOrderId: orderId,
      verifiedOutcome: verified,
      notPaidMessage: tr.tr('psNotPaidShop'),
    );
