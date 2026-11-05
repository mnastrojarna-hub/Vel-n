import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../reservations/reservation_models.dart';
import '../../routes/ride_recorder.dart';
import 'home_state.dart';
import 'home_ticket_parts.dart';

/// "TÝM PRO TEBE" checklist of the ticket — only facts the booking already
/// carries (payment, documents, pickup / return place and time, the
/// automatic ride recording). No codes, no invented promises.
class HomeTicketChecklist extends ConsumerWidget {
  final HomeSnapshot snap;
  final bool? docsOk;
  const HomeTicketChecklist({super.key, required this.snap, required this.docsOk});

  String _when(AppTranslations tr, DateTime d, String? hm) =>
      '${tripShortDate(tr, d)}${hm == null || hm.isEmpty ? '' : ' $hm'}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final rec = ref.watch(rideRecorderProvider);
    final r = snap.res;
    final rows = <TkCheckRow Function(bool last)>[];

    switch (snap.ticket) {
      case HomeTicket.s1:
        rows.add((l) => TkCheckRow(node: TkNode.warn, text: tr.tr('v2HomeChkSos'), last: l));
      case HomeTicket.s2:
        final p = snap.pending!;
        rows.add((l) => TkCheckRow(
            node: TkNode.warn, text: tr.trArgs('v2HomeChkUnpaid', {'amount': Money.czk(p.totalPrice)}), last: l));
        if (!p.verifying) {
          rows.add((l) => TkCheckRow(node: TkNode.info, text: tr.trArgs('v2HomeChkTime', {'t': p.timeLabel}), last: l));
        }
      default:
        if (r == null) break;
        rows.add((l) => TkCheckRow(
            node: TkNode.done, text: tr.trArgs('v2HomeChkPaid', {'amount': Money.czk(r.totalPrice)}), last: l));
        if (docsOk == true) {
          rows.add((l) => TkCheckRow(node: TkNode.done, text: tr.tr('v2HomeChkDocsOk'), last: l));
        } else if (docsOk == false) {
          rows.add((l) => TkCheckRow(node: TkNode.warn, text: tr.tr('v2HomeChkDocsMissing'), last: l));
        }
        final running = snap.ticket == HomeTicket.s8 || snap.ticket == HomeTicket.s9;
        if (!running) {
          if (r.isSelfService && !homeIsDelivery(r)) {
            rows.add((l) => TkCheckRow(node: TkNode.info, text: tr.tr('v2HomeChkCodes'), last: l));
          }
          final when = _when(tr, r.startDate, r.pickupHm);
          rows.add((l) => homeIsDelivery(r)
              ? TkCheckRow(
                  node: TkNode.current,
                  text: tr.trArgs('v2HomeChkDelivery', {'place': (r.pickupAddress ?? '').trim()}),
                  sub: when,
                  last: l)
              : TkCheckRow(
                  node: TkNode.current,
                  text: tr.trArgs('v2HomeChkPickup', {'when': when, 'place': r.branchName ?? ''}),
                  sub: (r.branchAddress ?? '').trim().isEmpty ? null : r.branchAddress!.trim(),
                  last: l));
        } else {
          final rt = (r.returnTime ?? '').trim();
          final place = r.returnMethod == 'delivery'
              ? (r.returnAddress ?? '').trim()
              : (r.branchName ?? '').trim();
          rows.add((l) => TkCheckRow(
              node: TkNode.current,
              text: tr.trArgs('v2HomeChkReturn',
                  {'when': _when(tr, r.endDate, rt.length >= 5 ? rt.substring(0, 5) : null), 'place': place}),
              sub: snap.ticket == HomeTicket.s9 && r.returnMethod != 'delivery'
                  ? tr.tr(r.isSelfService ? 'v2HomeChkReturnSelf' : 'v2HomeChkReturnStaff')
                  : null,
              last: l));
        }
    }

    final autoRec = rec.recording && !rec.manual;
    final running = snap.ticket == HomeTicket.s8 || snap.ticket == HomeTicket.s9;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        header: true,
        child: Text(tr.tr('v2HomeTeam').toUpperCase(),
            style: MgType.eyebrow.copyWith(color: rank.accentOnDark)),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < rows.length; i++) rows[i](i == rows.length - 1),
      if (running && autoRec) ...[
        const SizedBox(height: 10),
        Row(children: [
          const MgPing(size: 8, color: MgColors.sosDot),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr.tr(rec.gpsLost ? 'v2HomeRecGpsLost' : 'v2HomeRecAuto'),
                style: MgType.small.copyWith(
                    fontWeight: FontWeight.w700, color: rec.gpsLost ? MgColors.warnDark : MgColors.onDark)),
          ),
        ]),
      ],
    ]);
  }
}

/// Days label "3 dny" for a reservation.
String homeDaysLabel(AppTranslations tr, Reservation r) => '${r.dayCount} ${tr.daysWord(r.dayCount)}';
