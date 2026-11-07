import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/booking_rules.dart';
import '../../../core/date_days.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/rank/mg_logo_ring.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';
import '../../loyalty/loyalty_provider.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../widgets/res_access_codes_card.dart';
import '../widgets/res_pickup_procedure.dart';
import 'res_sections_v2.dart' show resReturnRules;
import 'res_status_v2.dart';

/// What CO TEĎ is about — derived from today's fields + the shell's
/// pending-payment provider; it never decides anything new.
enum ResCoState { upcoming, unpaid, verifying, active, done, cancelled }

ResCoState resCoState(Reservation r, ResPayFlag pay) {
  final st = r.displayStatus;
  if (st == ResStatus.cancelled) return ResCoState.cancelled;
  if (st == ResStatus.dokoncene) return ResCoState.done;
  if (pay == ResPayFlag.verifying) return ResCoState.verifying;
  if (pay == ResPayFlag.unpaid) return ResCoState.unpaid;
  if (st == ResStatus.aktivni) return ResCoState.active;
  return ResCoState.upcoming;
}

/// The ONE primary (looping) action of CO TEĎ (Reservation board): docs
/// missing → the codes card's "upload docs & release codes"; self-service
/// pickup → "Postup na pobočce" (the procedure sheet); staffed pickup →
/// "Navigovat na pobočku"; running rental → navigate to the return place;
/// unpaid → pay; done → book again; cancelled → restore. Delivery keeps
/// today's "Upravit rezervaci". Every one is an action the detail had.
enum ResCoCta { none, release, procedure, navigatePickup, navigateReturn, edit, pay, rebook, restore }

/// Withheld codes the customer can release by uploading documents (the
/// codes card's own condition; swap-withheld codes do not count).
bool resCodesHeld(Reservation r, List<DoorCode>? codes) =>
    r.inRentalTerm && (codes ?? const []).any((c) => !c.sentToCustomer && c.withheldReason != swapWithheldReason);

ResCoCta resCoCta(Reservation r, ResCoState state, List<DoorCode>? codes) {
  final branchPickup = r.pickupMethod != 'delivery' && (r.pickupAddress ?? '').trim().isEmpty;
  switch (state) {
    case ResCoState.cancelled:
      return ResCoCta.restore;
    case ResCoState.done:
      return ResCoCta.rebook;
    case ResCoState.verifying:
      return ResCoCta.none;
    case ResCoState.unpaid:
      return ResCoCta.pay;
    case ResCoState.upcoming:
      if (resCodesHeld(r, codes)) return ResCoCta.release;
      if (ResPickupProcedure.visibleFor(r)) return ResCoCta.procedure;
      return branchPickup ? ResCoCta.navigatePickup : ResCoCta.edit;
    case ResCoState.active:
      if (resCodesHeld(r, codes)) return ResCoCta.release;
      return r.returnMethod != 'delivery' ? ResCoCta.navigateReturn : ResCoCta.edit;
  }
}

/// CO TEĎ — the ONE dark hero of the detail (V22 §2.4): the next step with
/// the SAME actions today's detail offers (edit, restore & pay, book again,
/// SOS, complete payment = the shell strip's action), the door codes
/// (`ResAccessCodesCard`, dark v2 look) and the self-service procedure
/// (`ResPickupProcedure`, link → sheet).
class ResCoTedV2 extends StatelessWidget {
  final Reservation res;
  final AsyncValue<List<DoorCode>> doorCodesAsync;
  final ResCoState state;
  final String? payTimeLeft;
  final VoidCallback onEdit;
  final VoidCallback onRestore;
  final VoidCallback onRebook;
  final VoidCallback? onPay;

  /// Navigation to the pickup / return place (`ResLocationRow` targets).
  final VoidCallback? onNavigatePickup;
  final VoidCallback? onNavigateReturn;

  /// Finished booking: the rating card (dark look) above "Znovu rezervovat".
  final Widget? rating;

  /// Branch address shown under the heading of a staffed pickup (board
  /// "Mezná 9, 393 01 Pelhřimov") — the same address as "Kdy a kde".
  final String? pickupAddress;

  const ResCoTedV2({
    super.key,
    required this.res,
    required this.doorCodesAsync,
    required this.state,
    required this.payTimeLeft,
    required this.onEdit,
    required this.onRestore,
    required this.onRebook,
    required this.onPay,
    this.onNavigatePickup,
    this.onNavigateReturn,
    this.rating,
    this.pickupAddress,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final (String heading, List<Widget> lines, String? ctaLabel, VoidCallback? cta) = switch (state) {
      ResCoState.cancelled => (tr.tr('v2ResCoCancelH'), [_line(tr.tr('v2ResCoCancelLine'))], tr.tr('restoreBooking'), onRestore),
      ResCoState.done => (tr.tr('v2ResCoDoneH'), [_line(tr.tr('v2ResCoDoneLine'))], tr.tr('bookAgain'), onRebook),
      ResCoState.verifying => (
          tr.tr('psPendingTitle'),
          [_line(tr.tr('v2ResCoVerifyLine')), _line(tr.tr('v2ResCoVerifyNoPay'), icon: MgIcons.info)],
          null,
          null
        ),
      ResCoState.unpaid => (
          tr.tr('v2ResCoUnpaidH'),
          [
            _line(tr.tr('v2ResCoUnpaidLine')),
            if (payTimeLeft != null) _line(tr.trArgs('v2StripTimeLeft', {'t': payTimeLeft}), icon: MgIcons.clock),
          ],
          tr.tr('completeBookingFab'),
          onPay
        ),
      ResCoState.active => (
          _activeHeading(tr),
          [for (final l in resReturnRules(tr, res)) _line(l, icon: MgIcons.info)],
          null,
          null
        ),
      ResCoState.upcoming => (_pickupHeading(tr), <Widget>[], null, null),
    };
    final kind = resCoCta(res, state, doorCodesAsync.valueOrNull);
    // Jediné hlavní tlačítko CO TEĎ (board): postup / navigace / úprava
    // u přistavení; uvolnění kódů a postup kreslí jejich vlastní widgety.
    final (String? label, VoidCallback? action) = switch (kind) {
      ResCoCta.navigatePickup when onNavigatePickup != null => (tr.tr('navigateToBranch'), onNavigatePickup),
      ResCoCta.navigateReturn when onNavigateReturn != null => (tr.tr('navigateToBranch'), onNavigateReturn),
      ResCoCta.navigatePickup || ResCoCta.navigateReturn || ResCoCta.edit => (tr.tr('editReservation'), onEdit),
      _ => (ctaLabel, cta),
    };
    final showOps = state != ResCoState.done && state != ResCoState.cancelled;
    final address = (pickupAddress ?? '').trim();
    if (kind == ResCoCta.navigatePickup && address.isNotEmpty) lines.add(_line(address, icon: MgIcons.pin));
    return MgDarkHero(
      rankAura: true,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _CoTopRow(),
        const SizedBox(height: 12),
        Text(heading, style: MgType.h3.copyWith(color: MgColors.onDark)),
        ...lines,
        if ((state == ResCoState.upcoming || state == ResCoState.unpaid || state == ResCoState.verifying) &&
            res.pickupAllDayLegacy)
          _line(tr.tr('ssPickupAnyTime'), icon: MgIcons.clock),
        // Jako dnes: poznámka o výdeji od 12:00 kdykoli platí (bez ohledu na stav).
        ..._lateGateLines(context, tr),
        // Kódy a postup — stejné podmínky zobrazení jako dnes (karta i postup
        // se samy skryjí mimo termín / mimo samoobsluhu).
        ResAccessCodesCard(res: res, doorCodesAsync: doorCodesAsync),
        if (showOps)
          ResPickupProcedure(res: res, codes: doorCodesAsync.valueOrNull, cta: kind == ResCoCta.procedure),
        if (state == ResCoState.active && res.sosAllowed) ...[
          const SizedBox(height: 16),
          MgFabAvoid(
            kind: MgAvoidKind.sos,
            child: MgBtnSos(label: tr.sosTitle, onTap: () => context.push(Routes.sos)),
          ),
        ],
        if (state == ResCoState.done && rating != null) ...[const SizedBox(height: 16), rating!],
        if (label != null && action != null && kind != ResCoCta.release && kind != ResCoCta.procedure) ...[
          const SizedBox(height: 16),
          MgFabAvoid(child: MgCta(label: label, onTap: action, loop: true, arrow: true)),
        ],
      ]),
    );
  }

  String _activeHeading(AppTranslations tr) {
    final n = res.dayCount;
    final now = DateTime.now();
    final d = (calendarDaysInclusive(res.startDate, DateTime(now.year, now.month, now.day))).clamp(1, n < 1 ? 1 : n);
    return tr.trArgs('v2ResCoActiveH', {'d': d, 'n': n, 'date': tripShortDate(tr, res.endDate)});
  }

  String _pickupHeading(AppTranslations tr) {
    final date = tripShortDate(tr, res.startDate);
    if (res.pickupAllDayLegacy || res.pickupHm == null) return tr.trArgs('v2ResCoPickupOn', {'date': date});
    return tr.trArgs('v2ResCoPickupAt', {'date': date, 'time': res.pickupHm});
  }

  List<Widget> _lateGateLines(BuildContext context, AppTranslations tr) => [
        // Sleva za vyzvednutí od 12:00 (samoobsluha): kiosk vydá až od 12:00 —
        // vysvětlení + cesta k dřívějšímu času (jen nevyzvednutá 'reserved').
        if (res.kioskReleasePending) ...[
          _line(tr.trArgs('v2ResLateGate', {'date': fmtReleaseDate(pragueWallClock(res.startDate))}), half: true),
          if (res.status == 'reserved')
            Align(
              alignment: Alignment.centerLeft,
              child: MgBtnText(
                label: tr.tr('ssLateGateCta'),
                dark: true,
                icon: MgIcons.clock,
                onTap: () => context.push('/reservations/${res.id}/edit'),
              ),
            ),
        ],
      ];

  Widget _line(String text, {String? icon, bool half = false}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (half)
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 8, top: 1),
              decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('½', style: MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon)),
            )
          else if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: MgIcon(icon, size: 18, color: MgColors.neon),
            ),
          Expanded(child: Text(text, style: MgType.body.copyWith(color: MgColors.onDarkLead))),
        ]),
      );
}

/// CO TEĎ top row (Reservation board): the logo in the tier ring with the
/// level badge, the "CO TEĎ" eyebrow and the dark rank chip
/// ("Motorkář · −3 %") — rank material on the dark carrier only (V22 §1.4).
class _CoTopRow extends ConsumerWidget {
  const _CoTopRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final label = status == null ? null : RankCopy.chip(tr, RankCopy.name(tr, status.level, status.rankName), status.percent);
    final chip = status == null
        ? null
        : MgRankChip(
            label: label!,
            semanticLabel: RankCopy.aria(tr, status.level, RankCopy.name(tr, status.level, status.rankName), status.percent),
          );
    return LayoutBuilder(builder: (context, c) {
      // Čip vedle loga, když se vejde celý (uk „Мотоцикліст · −3 %" na
      // 320 dp s velkým písmem) — jinak pod logem přes celou šířku.
      final room = c.maxWidth - 52 - 12 - 40;
      final beside = label == null ||
          mgLineFits(context, label, MgType.meta.copyWith(fontWeight: FontWeight.w800, height: 1), room);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const MgLogoRing(size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgEyebrowDark(tr.tr('v2ResCoEyebrow'), icon: MgIcons.target),
              if (chip != null && beside) ...[const SizedBox(height: 6), chip],
            ]),
          ),
        ]),
        if (chip != null && !beside) ...[const SizedBox(height: 8), chip],
      ]);
    });
  }
}
