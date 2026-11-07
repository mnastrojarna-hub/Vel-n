import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import 'res_detail_bits_v2.dart';
import 'res_fit_v2.dart';
import 'res_history_parts_v2.dart';

/// v2 look of `ResModificationHistory` ("Historie rezervace" in the
/// detail): the SAME blocks under the SAME conditions and order — date
/// change summary, edit history, SOS, cancellation, the event timeline —
/// with the same texts; v2 surfaces, tone banners and line icons instead
/// of emoji and the old palette, D4 dates.
class ResHistoryV2 extends StatelessWidget {
  final Reservation res;
  final List<SosIncident> sosIncidents;
  const ResHistoryV2({super.key, required this.res, this.sosIncidents = const []});

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  bool get _datesChanged {
    if (res.originalStartDate == null || res.originalEndDate == null) return false;
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    return day(res.originalStartDate!) != day(res.startDate) || day(res.originalEndDate!) != day(res.endDate);
  }

  @override
  Widget build(BuildContext context) {
    final hasDateMod = res.originalStartDate != null && res.originalEndDate != null && _datesChanged;
    final hasHistory = res.modificationHistory.isNotEmpty;
    final hasSos = sosIncidents.isNotEmpty || res.endedBySos || res.sosReplacement;
    final hasCancellation = res.displayStatus == ResStatus.cancelled;
    if (!hasDateMod && !hasHistory && !hasSos && !hasCancellation) return _timeline(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasDateMod) ...[_dateMod(context), const SizedBox(height: 12)],
      if (hasHistory) ...[ResHistoryListV2(entries: res.modificationHistory), const SizedBox(height: 12)],
      if (hasSos) ...[ResHistorySosV2(res: res, incidents: sosIncidents), const SizedBox(height: 12)],
      if (hasCancellation) ...[_cancellation(context), const SizedBox(height: 12)],
      _timeline(context),
    ]);
  }

  Widget _dateMod(BuildContext context) {
    final tr = t(context);
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    final os = iso(res.originalStartDate!), oe = iso(res.originalEndDate!);
    final cs = iso(res.startDate), ce = iso(res.endDate);
    final desc = ModDescription.describe(os, oe, cs, ce);
    String d(String x) => resHistDay(x, tr.lang);
    final tone = switch (desc.kind) {
      ModKind.extended => MgTone.ok,
      ModKind.shortened => MgTone.warn,
      _ => MgTone.info,
    };
    return ResDetailCardV2(children: [
      MgStateBanner(
        tone: tone,
        icon: MgIcons.history,
        title: _capitalize(desc.typeText(tr.tr)),
        text: '${d(os)} – ${d(oe)} → ${d(cs)} – ${d(ce)}',
      ),
      const SizedBox(height: 12),
      ResHistRowV2(
        label: tr.tr('originalTerm'),
        value: '${d(os)} – ${d(oe)} (${desc.origDays} ${tr.daysWord(desc.origDays)})',
        valueColor: MgColors.meta,
      ),
      ResHistRowV2(
        label: tr.tr('newTerm'),
        value: '${d(cs)} – ${d(ce)} (${desc.newDays} ${tr.daysWord(desc.newDays)})',
        bold: true,
      ),
    ]);
  }

  Widget _cancellation(BuildContext context) {
    final tr = t(context);
    final source = res.cancelledBySource == 'admin'
        ? 'admin'
        : res.cancelledBySource == 'system'
            ? tr.tr('systemLabel')
            : tr.tr('customerLabel');
    return ResDetailCardV2(children: [
      ResHistHeadV2(icon: MgIcons.calendarX, text: tr.tr('cancellationSection'), color: MgColors.err),
      const SizedBox(height: 10),
      if (res.cancelledAt != null)
        ResHistRowV2(label: tr.tr('cancelledLabel'), value: resHistAt(res.cancelledAt!, tr.lang), valueColor: MgColors.err),
      ResHistRowV2(label: tr.tr('cancelledBy'), value: source),
      if (res.cancellationReason != null && res.cancellationReason!.isNotEmpty)
        ResHistRowV2(label: tr.tr('reasonLabel'), value: res.cancellationReason!),
      if (res.stornoFee != null && res.stornoFee! > 0)
        ResHistRowV2(label: tr.tr('stornoFeeLabel'), value: Money.czk(res.stornoFee!)),
      if (res.refundAmount != null && res.refundAmount! > 0)
        ResHistRowV2(label: tr.tr('refundedLabel'), value: Money.czk(res.refundAmount!), valueColor: MgColors.link),
    ]);
  }

  Widget _timeline(BuildContext context) {
    final tr = t(context);
    // Same events, same order as today (vydáno až po kódu + protokolu).
    final events = <(String, DateTime, String, Color)>[
      (tr.tr('timelineCreated'), res.createdAt, MgIcons.plus, MgColors.meta),
      if (res.confirmedAt != null) (tr.tr('timelineConfirmed'), res.confirmedAt!, MgIcons.check, MgColors.link),
      if (res.issuedAt != null) (tr.tr('timelineIssued'), res.issuedAt!, MgIcons.moto, MgColors.petrol),
      if (res.returnedAt != null) (tr.tr('timelineReturned'), res.returnedAt!, MgIcons.checkCircle, MgColors.link),
      if (res.actualReturnDate != null && res.returnedAt == null)
        (tr.tr('timelineActualReturn'), res.actualReturnDate!, MgIcons.calendarCheck, MgColors.link),
      if (res.cancelledAt != null) (tr.tr('timelineCancelled'), res.cancelledAt!, MgIcons.close, MgColors.err),
      if (res.ratedAt != null)
        ('${tr.tr('timelineRated')} (${res.rating ?? 0}/5)', res.ratedAt!, MgIcons.starFilled, MgColors.star),
    ];
    return ResDetailCardV2(children: [
      ResHistHeadV2(icon: MgIcons.history, text: tr.tr('reservationTimeline')),
      const SizedBox(height: 10),
      for (var i = 0; i < events.length; i++)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              ResHistDiscV2(icon: events[i].$3, color: events[i].$4),
              if (i < events.length - 1)
                Container(width: 2, height: 18, margin: const EdgeInsets.only(top: 2), color: MgColors.line),
            ]),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 3, bottom: i == events.length - 1 ? 0 : 12),
                // Label wraps; the date moves under it when a word would not
                // fit beside it (nl / de at 320 dp, large text).
                child: resV2EventRow(
                      context,
                      Text(events[i].$1, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                      Text(resHistAt(events[i].$2, tr.lang), style: MgType.tab(MgType.micro.copyWith(color: MgColors.meta))),
                    ) ??
                    const SizedBox.shrink(),
              ),
            ),
          ]),
    ]);
  }
}
