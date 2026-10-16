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
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../widgets/res_access_codes_card.dart';
import '../widgets/res_pickup_procedure.dart';
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
      ResCoState.active => (_activeHeading(tr), <Widget>[], tr.tr('editReservation'), onEdit),
      ResCoState.upcoming => (_pickupHeading(tr), <Widget>[], tr.tr('editReservation'), onEdit),
    };
    final showOps = state != ResCoState.done && state != ResCoState.cancelled;
    return MgDarkHero(
      rankAura: true,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerLeft, child: MgEyebrowDark(tr.tr('v2ResCoEyebrow'), icon: MgIcons.target)),
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
        if (showOps) ResPickupProcedure(res: res, codes: doorCodesAsync.valueOrNull),
        if (state == ResCoState.active && res.sosAllowed) ...[
          const SizedBox(height: 16),
          MgFabAvoid(
            kind: MgAvoidKind.sos,
            child: MgBtnSos(label: tr.sosTitle, onTap: () => context.push(Routes.sos)),
          ),
        ],
        if (ctaLabel != null && cta != null) ...[
          const SizedBox(height: 16),
          MgFabAvoid(child: MgCta(label: ctaLabel, onTap: cta, loop: true, arrow: true)),
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
