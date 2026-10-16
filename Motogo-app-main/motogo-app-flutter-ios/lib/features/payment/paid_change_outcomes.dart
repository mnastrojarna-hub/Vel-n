import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/paid_after_restart.dart' show PaidAfterRestart;
import '../../core/paid_change_queue.dart';
import '../../core/payment_pending_marker.dart' show PaymentMarkerKind;
import '../../core/router.dart';
import 'card_minimum.dart';
import 'payment_provider.dart';

/// Texty a výsledkové stavy zaplacené výměny / úpravy (D6, D5 — bez kontaktů,
/// vždy co se stalo, jestli se strhly peníze a co dál).

/// Důvod trvalého selhání (kód serveru) → věta s příčinou.
String paidChangeReasonText(AppTranslations tr, String? reason) {
  final key = switch (reason) {
    'new_moto_unavailable' || 'moto_unavailable' => 'pdFailTaken',
    'wrong_status' || 'not_found' || 'not_paid' => 'pdFailStatus',
    'swap_date_out_of_range' => 'pdFailDate',
    'other_account' => 'pdFailForeign',
    'gone' => 'pdFailGone',
    'refunded' => 'pdFailRefunded',
    'stale_payment' || 'expired' => 'pdFailStale',
    _ => 'pdFailOther',
  };
  return tr.tr(key);
}

/// Motorku mezitím obsadila jiná rezervace (ta má přednost — odpověď majitele
/// 2026-10-16): výměna / úprava se nezapsala, doplatek se vrací.
bool isTakenReason(String? reason) => reason == 'new_moto_unavailable' || reason == 'moto_unavailable';

/// Titulek trvalého selhání: „Motorka je mezitím obsazená" / „Výměnu (úpravu) se nepodařilo dokončit".
String paidChangeFailureTitle(AppTranslations tr, {required bool swap, String? reason}) =>
    tr.tr(isTakenReason(reason) ? 'pdTakenTitle' : (swap ? 'pdSwapFailedTitle' : 'pdEditFailedTitle'));

/// Výběr jiné motorky rovnou na záložce Výměna (úprava rezervace, `?tab=swap`).
String swapPickRoute(String bookingId) => '/reservations/$bookingId/edit?tab=swap';

/// Důvody, jejichž text sám říká, co se děje s penězi (bez věty o vratce).
const _selfContained = {'other_account', 'gone', 'refunded', 'stale_payment', 'expired'};

/// Celý text selhání: příčina + co se děje s doplatkem.
String paidChangeFailureText(AppTranslations tr,
    {String? reason, String refund = 'auto', required double amount}) {
  final why = paidChangeReasonText(tr, reason).replaceAll('{amount}', kcExact(amount));
  if (_selfContained.contains(reason) || refund == 'none') return why;
  final money = tr
      .tr(refund == 'staff' ? 'pdRefundStaff' : 'pdRefundAuto')
      .replaceAll('{amount}', kcExact(amount));
  return '$why $money';
}

/// „Výměna se dokončuje" / „Úprava se dokončuje" — platba prošla, zápis do
/// rezervace doběhne sám (fronta + server). [verified] = výsledek po dokončení.
PaymentOutcome completingOutcome(
  AppTranslations tr, {
  required bool swap,
  required String key,
  required String bookingId,
  required double amount,
  required PaymentOutcome verified,
  bool offline = false,
}) {
  final body = tr
      .tr(swap ? 'pdSwapCompletingBody' : 'pdEditCompletingBody')
      .replaceAll('{amount}', kcExact(amount));
  return PaymentOutcome(
    kind: PaymentOutcomeKind.pending,
    title: tr.tr(swap ? 'pdSwapCompletingTitle' : 'pdEditCompletingTitle'),
    subtitle: offline ? '$body ${tr.tr('pdCompletingOffline')}' : body,
    ctaLabel: tr.tr('psMyReservations'),
    ctaRoute: Routes.reservations,
    verifyBookingId: bookingId,
    // výměna se bez fronty ověřuje jen stavem platby (a podle toho texty)
    verifyIntentOnly: swap,
    completeKey: key,
    verifiedOutcome: verified,
    notPaidMessage: tr.tr('psNotPaidEdit'),
  );
}

/// Zaplacenou změnu trvale nejde zapsat — doplatek se vrací. Výměna, kterou
/// zmařila jiná rezervace (motorka mezitím obsazená): „Vybrat jinou motorku"
/// (záložka Výměna) nebo „Ponechat současnou motorku" (detail rezervace).
PaymentOutcome changeFailedOutcome(AppTranslations tr,
    {required bool swap, required String bookingId, required PaidChangeResult r, required double charge}) {
  final offerOther = swap && isTakenReason(r.reason);
  return PaymentOutcome(
    kind: PaymentOutcomeKind.failed,
    title: paidChangeFailureTitle(tr, swap: swap, reason: r.reason),
    subtitle: paidChangeFailureText(tr, reason: r.reason, refund: r.refund, amount: r.amount ?? charge),
    ctaLabel: tr.tr(offerOther ? 'pdPickOtherMoto' : 'psOpenReservation'),
    ctaRoute: offerOther ? swapPickRoute(bookingId) : '/reservations/$bookingId',
    secondaryLabel: offerOther ? tr.tr('pdKeepCurrentMoto') : null,
    secondaryRoute: offerOther ? '/reservations/$bookingId' : null,
  );
}

/// Řádek s dorovnáním na výsledkové obrazovce („Zaplaceno 15 Kč (z toho
/// dorovnání 8 Kč)"), nebo null bez dorovnání.
PaymentOutcomeLine? roundingLine(AppTranslations tr, CardCharge cc) {
  if (cc.isRound) {
    return PaymentOutcomeLine(
        'ℹ️',
        tr
            .tr('pdPaidWithRounding')
            .replaceAll('{charge}', kcExact(cc.charge))
            .replaceAll('{rounding}', kcExact(cc.rounding)));
  }
  if (cc.isWaive) return PaymentOutcomeLine('ℹ️', tr.tr('pdWaivedSub'));
  return null;
}

/// Jednorázové oznámení po restartu appky (AppShell): platba odeslaná před
/// zabitím appky má mezitím výsledek. Zaplacenou výměnu, kterou zmařila jiná
/// rezervace, oznámí „Motorka je mezitím obsazená" + vratka doplatku; detail
/// rezervace pak nabídne „Vybrat jinou motorku" / „Ponechat současnou".
SnackBar paidAfterRestartSnackBar(BuildContext context, PaidAfterRestart paid) {
  final tr = t(context);
  final swap = paid.kind == PaymentMarkerKind.swap;
  final Widget content;
  if (paid.failed) {
    content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(paidChangeFailureTitle(tr, swap: swap, reason: paid.reason),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(paidChangeFailureText(tr, reason: paid.reason, refund: paid.refund, amount: paid.amount)),
    ]);
  } else {
    // Doplatek úpravy / výměny ≠ „rezervace je potvrzená" (ta byla zaplacená
    // už dřív) — text podle druhu platby; nedokončený zápis = „dokončuje se".
    final notice = paid.completing
        ? (swap ? 'pdSwapCompletingShort' : 'pdEditCompletingShort')
        : switch (paid.kind) {
            PaymentMarkerKind.edit => 'fxEditPaidNotice',
            PaymentMarkerKind.swap => 'fxSwapPaidNotice',
            PaymentMarkerKind.sos => 'fxSosPaidNotice',
            _ => 'psPaidNotice',
          };
    content = Text(tr.tr(notice));
  }
  final id = paid.bookingId;
  return SnackBar(
    content: content,
    duration: Duration(seconds: paid.failed ? 12 : 8),
    action: SnackBarAction(
      label: tr.tr('psShow'),
      onPressed: () => GoRouter.of(context).go('/reservations/$id'),
    ),
  );
}
