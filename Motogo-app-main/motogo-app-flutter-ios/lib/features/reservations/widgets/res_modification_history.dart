import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import 'res_detail_card.dart';
import 'res_detail_row.dart';

/// Comprehensive reservation history — shows ALL changes and events:
/// date modifications, motorcycle changes, location/method changes,
/// SOS incidents, timeline, cancellation details.
/// Visible for ALL reservation statuses.
class ResModificationHistory extends StatelessWidget {
  final Reservation res;
  final List<SosIncident> sosIncidents;
  const ResModificationHistory({
    super.key,
    required this.res,
    this.sosIncidents = const [],
  });

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '–';
    return '${d.day}. ${d.month}. ${d.year}';
  }

  String _fmtDT(DateTime dt) {
    return '${dt.day}.${dt.month}.${dt.year} '
        '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _methodLabel(BuildContext context, String? m) =>
      m == 'delivery' ? t(context).tr('deliveryLabel') : t(context).tr('branchPickupLabel');

  @override
  Widget build(BuildContext context) {
    final hasDateMod = res.originalStartDate != null &&
        res.originalEndDate != null &&
        _datesChanged;
    final hasHistory = res.modificationHistory.isNotEmpty;
    final hasSos = sosIncidents.isNotEmpty ||
        res.endedBySos || res.sosReplacement;
    final hasCancellation = res.displayStatus == ResStatus.cancelled;
    final hasTimeline = true; // always show timeline

    if (!hasDateMod && !hasHistory && !hasSos && !hasCancellation) {
      // Still show timeline for any reservation
      return _buildTimeline(context);
    }

    return Column(children: [
      // === DATE MODIFICATION SUMMARY ===
      if (hasDateMod) _buildDateModCard(context),
      if (hasDateMod) const SizedBox(height: 12),

      // === MODIFICATION HISTORY TIMELINE ===
      if (hasHistory) _buildHistoryCard(context),
      if (hasHistory) const SizedBox(height: 12),

      // === SOS INCIDENTS ===
      if (hasSos) _buildSosCard(context),
      if (hasSos) const SizedBox(height: 12),

      // === CANCELLATION DETAILS ===
      if (hasCancellation) _buildCancellationCard(context),
      if (hasCancellation) const SizedBox(height: 12),

      // === EVENT TIMELINE ===
      _buildTimeline(context),
    ]);
  }

  bool get _datesChanged {
    if (res.originalStartDate == null || res.originalEndDate == null) {
      return false;
    }
    final os = DateTime(res.originalStartDate!.year,
        res.originalStartDate!.month, res.originalStartDate!.day);
    final oe = DateTime(res.originalEndDate!.year,
        res.originalEndDate!.month, res.originalEndDate!.day);
    final cs = DateTime(
        res.startDate.year, res.startDate.month, res.startDate.day);
    final ce =
        DateTime(res.endDate.year, res.endDate.month, res.endDate.day);
    return os != cs || oe != ce;
  }

  // ============================================================
  // DATE MODIFICATION BANNER
  // ============================================================
  Widget _buildDateModCard(BuildContext context) {
    final origStart = res.originalStartDate!;
    final origEnd = res.originalEndDate!;
    final desc = ModDescription.describe(
      origStart.toIso8601String().substring(0, 10),
      origEnd.toIso8601String().substring(0, 10),
      res.startDate.toIso8601String().substring(0, 10),
      res.endDate.toIso8601String().substring(0, 10),
    );

    final Color bannerBg;
    if (desc.color == const Color(0xFF2563EB)) {
      bannerBg = const Color(0xFFDBEAFE);
    } else if (desc.color == const Color(0xFFDC2626)) {
      bannerBg = const Color(0xFFFEE2E2);
    } else {
      bannerBg = const Color(0xFFFEF3C7);
    }

    final osFmt = _fmtDate(origStart.toIso8601String().substring(0, 10));
    final oeFmt = _fmtDate(origEnd.toIso8601String().substring(0, 10));
    final csFmt = _fmtDate(res.startDate.toIso8601String().substring(0, 10));
    final ceFmt = _fmtDate(res.endDate.toIso8601String().substring(0, 10));

    return ResDetailCard(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bannerBg,
          border: Border.all(color: desc.color, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              desc.type[0].toUpperCase() + desc.type.substring(1),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: desc.color),
            ),
            const SizedBox(height: 4),
            Text(
              '$osFmt – $oeFmt → $csFmt – $ceFmt',
              style: const TextStyle(fontSize: 12, color: Color(0xFF4A6357)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      ResDetailRow(
        label: t(context).tr('originalTerm'),
        value: '$osFmt – $oeFmt (${desc.origDays} dní)',
        valueColor: const Color(0xFFB45309),
      ),
      ResDetailRow(
        label: t(context).tr('newTerm'),
        value: '$csFmt – $ceFmt (${desc.newDays} dní)',
        valueColor: desc.color,
      ),
    ]);
  }

  // ============================================================
  // FULL MODIFICATION HISTORY
  // ============================================================
  Widget _buildHistoryCard(BuildContext context) {
    return ResDetailCard(children: [
      Text(
        '${t(context).tr('modificationHistory')} (${res.modificationHistory.length}×)',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: MotoGoColors.g400,
        ),
      ),
      const SizedBox(height: 6),
      ...res.modificationHistory.asMap().entries.map((e) {
        final idx = e.key;
        final mod = e.value;
        return _buildHistoryEntry(context, idx, mod);
      }),
    ]);
  }

  Widget _buildHistoryEntry(BuildContext context, int idx, ModificationEntry mod) {
    final hm = ModDescription.describe(
        mod.fromStart, mod.fromEnd, mod.toStart, mod.toEnd);
    final source = mod.source == 'admin' ? 'admin' : t(context).tr('customerLabel');
    final changes = <Widget>[];

    // Date change detail
    if (mod.hasDateChange) {
      // Start date change
      final fromS = DateTime.tryParse(mod.fromStart);
      final toS = DateTime.tryParse(mod.toStart);
      if (fromS != null && toS != null) {
        final startDiff = DateTime(toS.year, toS.month, toS.day)
            .difference(DateTime(fromS.year, fromS.month, fromS.day))
            .inDays;
        if (startDiff != 0) {
          changes.add(_changeRow(
            t(context).tr('startLabel'),
            _fmtDate(mod.fromStart),
            _fmtDate(mod.toStart),
            startDiff > 0 ? '+$startDiff d' : '${startDiff} d',
            startDiff > 0
                ? const Color(0xFF2563EB)
                : const Color(0xFFDC2626),
          ));
        }
      }
      // End date change
      final fromE = DateTime.tryParse(mod.fromEnd);
      final toE = DateTime.tryParse(mod.toEnd);
      if (fromE != null && toE != null) {
        final endDiff = DateTime(toE.year, toE.month, toE.day)
            .difference(DateTime(fromE.year, fromE.month, fromE.day))
            .inDays;
        if (endDiff != 0) {
          changes.add(_changeRow(
            t(context).tr('endLabel'),
            _fmtDate(mod.fromEnd),
            _fmtDate(mod.toEnd),
            endDiff > 0 ? '+$endDiff d' : '${endDiff} d',
            endDiff > 0
                ? const Color(0xFF2563EB)
                : const Color(0xFFDC2626),
          ));
        }
      }
    }

    // Motorcycle change
    if (mod.hasMotoChange) {
      changes.add(_changeRow(
        t(context).tr('motorcycle'),
        mod.fromMoto!,
        mod.toMoto!,
        null,
        const Color(0xFF7C3AED),
      ));
    }

    // Pickup method change
    if (mod.hasPickupMethodChange) {
      changes.add(_changeRow(
        t(context).tr('pickupLabel'),
        _methodLabel(context, mod.fromPickupMethod),
        _methodLabel(context, mod.toPickupMethod),
        null,
        const Color(0xFF0891B2),
      ));
    }

    // Return method change
    if (mod.hasReturnMethodChange) {
      changes.add(_changeRow(
        t(context).tr('returnPlaceLabel'),
        _methodLabel(context, mod.fromReturnMethod),
        _methodLabel(context, mod.toReturnMethod),
        null,
        const Color(0xFF0891B2),
      ));
    }

    // Pickup address change
    if (mod.hasPickupAddressChange) {
      changes.add(_changeRow(
        t(context).tr('pickupPlace'),
        mod.fromPickupAddress!,
        mod.toPickupAddress!,
        null,
        const Color(0xFF0891B2),
      ));
    }

    // Return address change
    if (mod.hasReturnAddressChange) {
      changes.add(_changeRow(
        t(context).tr('returnPlace'),
        mod.fromReturnAddress!,
        mod.toReturnAddress!,
        null,
        const Color(0xFF0891B2),
      ));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hm.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hm.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: number + timestamp + type + source
          Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: hm.color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '${idx + 1}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_fmtDT(mod.at)} · $source',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.g400),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: hm.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                hm.type,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: hm.color),
              ),
            ),
          ]),
          if (changes.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...changes,
          ],
        ],
      ),
    );
  }

  Widget _changeRow(
    String label,
    String from,
    String to,
    String? badge,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.g400)),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: from,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                      decoration: TextDecoration.lineThrough),
                ),
                const TextSpan(
                  text: ' → ',
                  style: TextStyle(fontSize: 10, color: MotoGoColors.g400),
                ),
                TextSpan(
                  text: to,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
                if (badge != null)
                  TextSpan(
                    text: '  $badge',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: color),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SOS INCIDENTS
  // ============================================================
  Widget _buildSosCard(BuildContext context) {
    return ResDetailCard(children: [
      Row(children: [
        const Text('🆘', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(
          t(context).tr('sosEvents'),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: MotoGoColors.g400,
          ),
        ),
      ]),
      const SizedBox(height: 8),
      // SOS replacement badge
      if (res.sosReplacement)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF16A34A)),
          ),
          child: Row(children: [
            const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF16A34A)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                t(context).tr('replacementForSos'),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A)),
              ),
            ),
          ]),
        ),
      // Ended by SOS badge
      if (res.endedBySos)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MotoGoColors.red),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber, size: 14, color: MotoGoColors.red),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${t(context).tr('endedBySos')}'
                    '${res.sosIncidentId != null ? ' (${res.sosIncidentId!.substring(res.sosIncidentId!.length - 8).toUpperCase()})' : ''}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.red),
              ),
            ),
          ]),
        ),
      // SOS incident list
      ...sosIncidents.map((inc) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(inc.shortId,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: MotoGoColors.red)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: MotoGoColors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(inc.typeLabel,
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: MotoGoColors.red)),
                  ),
                  const Spacer(),
                  Text(inc.statusLabel,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: inc.status == 'resolved' ||
                                  inc.status == 'closed'
                              ? MotoGoColors.greenDarker
                              : MotoGoColors.red)),
                ]),
                const SizedBox(height: 4),
                Text(
                  '${_fmtDT(inc.createdAt)}'
                  '${inc.resolvedAt != null ? ' → ${t(context).tr('resolvedAt')} ${_fmtDT(inc.resolvedAt!)}' : ''}',
                  style: const TextStyle(
                      fontSize: 10, color: MotoGoColors.g400),
                ),
                if (inc.title != null && inc.title!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(inc.title!,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MotoGoColors.black)),
                  ),
              ],
            ),
          )),
    ]);
  }

  // ============================================================
  // CANCELLATION DETAILS
  // ============================================================
  Widget _buildCancellationCard(BuildContext context) {
    final source = res.cancelledBySource == 'admin'
        ? 'admin'
        : res.cancelledBySource == 'system'
            ? t(context).tr('systemLabel')
            : t(context).tr('customerLabel');
    return ResDetailCard(children: [
      Row(children: [
        const Text('🗑️', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(t(context).tr('cancellationSection'), style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w800,
          letterSpacing: 0.5, color: MotoGoColors.g400)),
      ]),
      const SizedBox(height: 6),
      if (res.cancelledAt != null)
        ResDetailRow(
          label: t(context).tr('cancelledLabel'),
          value: _fmtDT(res.cancelledAt!),
          valueColor: MotoGoColors.red,
        ),
      ResDetailRow(label: t(context).tr('cancelledBy'), value: source),
      if (res.cancellationReason != null &&
          res.cancellationReason!.isNotEmpty)
        ResDetailRow(label: t(context).tr('reasonLabel'), value: res.cancellationReason!),
      if (res.stornoFee != null && res.stornoFee! > 0)
        ResDetailRow(
          label: t(context).tr('stornoFeeLabel'),
          value: '${res.stornoFee!.toStringAsFixed(0)} Kč',
        ),
      if (res.refundAmount != null && res.refundAmount! > 0)
        ResDetailRow(
          label: t(context).tr('refundedLabel'),
          value: '${res.refundAmount!.toStringAsFixed(0)} Kč',
          valueColor: MotoGoColors.greenDarker,
        ),
    ]);
  }

  // ============================================================
  // EVENT TIMELINE
  // ============================================================
  Widget _buildTimeline(BuildContext context) {
    final events = <_TimelineEvent>[];

    events.add(_TimelineEvent(
      t(context).tr('timelineCreated'), res.createdAt, MotoGoColors.g400, Icons.add_circle));
    if (res.confirmedAt != null) {
      events.add(_TimelineEvent(
          t(context).tr('timelineConfirmed'), res.confirmedAt!, MotoGoColors.greenDarker, Icons.check_circle));
    }
    if (res.pickedUpAt != null) {
      events.add(_TimelineEvent(
          t(context).tr('timelineIssued'), res.pickedUpAt!, const Color(0xFF2563EB), Icons.motorcycle));
    }
    if (res.returnedAt != null) {
      events.add(_TimelineEvent(
          t(context).tr('timelineReturned'), res.returnedAt!, MotoGoColors.greenDarker, Icons.assignment_return));
    }
    if (res.actualReturnDate != null && res.returnedAt == null) {
      events.add(_TimelineEvent(
          t(context).tr('timelineActualReturn'), res.actualReturnDate!, MotoGoColors.greenDarker, Icons.event_available));
    }
    if (res.cancelledAt != null) {
      events.add(_TimelineEvent(
          t(context).tr('timelineCancelled'), res.cancelledAt!, MotoGoColors.red, Icons.cancel));
    }
    if (res.ratedAt != null) {
      events.add(_TimelineEvent(
          '${t(context).tr('timelineRated')} (${res.rating ?? 0}/5)', res.ratedAt!, const Color(0xFFF59E0B), Icons.star));
    }

    return ResDetailCard(children: [
      Row(children: [
        const Text('📋', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(t(context).tr('reservationTimeline'),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: MotoGoColors.g400)),
      ]),
      const SizedBox(height: 8),
      ...events.asMap().entries.map((e) {
        final idx = e.key;
        final ev = e.value;
        final isLast = idx == events.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(children: [
              Icon(ev.icon, size: 16, color: ev.color),
              if (!isLast)
                Container(
                    width: 2,
                    height: 20,
                    color: MotoGoColors.g200),
            ]),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(ev.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ev.color)),
                    Text(_fmtDT(ev.at),
                        style: const TextStyle(
                            fontSize: 10, color: MotoGoColors.g400)),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    ]);
  }
}

class _TimelineEvent {
  final String label;
  final DateTime at;
  final Color color;
  final IconData icon;
  const _TimelineEvent(this.label, this.at, this.color, this.icon);
}
