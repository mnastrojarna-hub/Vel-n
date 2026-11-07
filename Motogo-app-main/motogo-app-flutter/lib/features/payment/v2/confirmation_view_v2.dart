import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_disclosure.dart';
import '../../../core/v2/widgets/mg_emoji_map.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/widgets/pickup_location_link.dart';
import '../card_minimum.dart';
import 'pay_parts_v2.dart';
import 'pay_steps_v2.dart';

/// Documents state of the thank-you page (the screen's own `_DocsStatus`).
enum PayDocsV2 { unknown, verified, child, missing }

/// v2 look of the thank-you page `/success` (Stavy 1.1): dark rank hero
/// with ✕ top-left (the screen's own close → Rezervace), the ✓ disc and
/// "Rezervace je (znovu) potvrzená"; the white summary card (number,
/// bike, dates, pickup, times; "Zaplaceno" only from the in-memory form);
/// "CO BUDE DÁL" (e-mail, documents, pickup + map + kiosk 12:00 note);
/// "Bezpečnostní pokyny" collapsed; dock = the old CTA(s) with the same
/// destinations. One CTA loop, no flying bike, no support row. Values are
/// the screen's (DB row first, the draft only when it is this booking's).
class ConfirmationViewV2 extends StatelessWidget {
  final bool restored;
  final String? shortId;
  final String? motoName;
  final DateTime? start;
  final DateTime? end;
  final PickupInfo? pickup;
  final String? branchName;
  final String? pickupTime;
  final String? returnTime;
  final String? lateGateDate;
  final PayDocsV2 docs;
  final String? missingReason;
  final bool noDetails;
  final bool loadFailed;
  /// The booking form's total — only when the in-memory form IS this
  /// booking (never a new query); shown only for a normal card charge.
  final double? paidTotal;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final VoidCallback onDocs;

  const ConfirmationViewV2({
    super.key,
    required this.restored,
    required this.shortId,
    required this.motoName,
    required this.start,
    required this.end,
    required this.pickup,
    required this.branchName,
    required this.pickupTime,
    required this.returnTime,
    required this.lateGateDate,
    required this.docs,
    required this.missingReason,
    required this.noDetails,
    required this.loadFailed,
    required this.paidTotal,
    required this.onRetry,
    required this.onClose,
    required this.onDocs,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = start, e = end;
    final range = s != null && e != null ? mgRange(s, e, tr.lang) : null;
    // "{bike} · {range}" on its own line: a date ending with "." must not
    // run into the next sentence.
    final why = [
      if (motoName != null && range != null) '${motoName!} · $range',
      tr.tr('v2UxPsHoldBike'),
    ].join('\n');
    final missing = docs == PayDocsV2.missing;
    return MgStateScreen(
      tone: MgTone.ok,
      title: tr.tr(restored ? 'v2UxPsReconfirmedTitle' : 'v2UxPsConfirmedTitle'),
      why: why,
      onClose: onClose,
      support: false,
      summary: noDetails ? _noDetails(tr) : _summary(context, tr, range),
      primary: missing
          ? MgStateAction(mgStripEmoji(tr.tr('uploadDocumentsCta')), onDocs)
          : MgStateAction(tr.tr('successCta'), onClose),
      secondary: missing ? MgStateAction(tr.tr('successCta'), onClose) : null,
      children: [
        PayStepsCardV2(title: tr.tr('v2UxPsNext'), steps: _steps(tr)),
        PayCardV2(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: MgDisclosure(
            label: tr.tr('successSafetyTitle'),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(tr.tr('v2UxPsSafetyTips'), style: MgType.body.copyWith(color: MgColors.body2)),
            ),
          ),
        ),
        Text(tr.tr('v2UxPsSynced'), textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta)),
      ],
    );
  }

  Widget _noDetails(AppTranslations tr) => loadFailed
      ? MgStateBanner(
          tone: MgTone.info,
          icon: MgIcons.signalOff,
          plain: true,
          title: tr.tr('fxConfirmLoadFail'),
          text: tr.tr('fxConfirmLoadFailBody'),
          actions: [MgBtnText(label: tr.tr('eoRetry'), icon: MgIcons.refresh, onTap: onRetry)],
        )
      : const MgSkeletonRow(thumb: 44, lines: 2);

  Widget _summary(BuildContext context, AppTranslations tr, String? range) {
    final p = pickup;
    final branch = (p?.name ?? branchName ?? '').trim();
    final address = (p?.address ?? '').trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: MgWordFit(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${tr.tr('v2UxPsBookingEyebrow').toUpperCase()} '),
              if (shortId != null) TextSpan(text: shortId, style: const TextStyle(color: MgColors.ink)),
            ]), style: MgType.tab(MgType.eyebrow.copyWith(color: MgColors.meta))),
          ),
        ),
        const SizedBox(width: 8),
        MgMeaningChip(label: tr.tr('v2UxPsConfirmedChip'), tone: MgTone.ok),
      ]),
      const SizedBox(height: MgSpace.s10),
      if (motoName != null) MgWordFit(child: Text(motoName!, style: MgType.title.copyWith(color: MgColors.ink))),
      if (range != null) Text(range, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
      if (branch.isNotEmpty) ...[
        const SizedBox(height: MgSpace.s10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: MgIcon(MgIcons.pin, size: 18, color: MgColors.link)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p != null ? '${tr.tr('confirmPickupTitle')} · $branch' : branch,
                  style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
              if (address.isNotEmpty) Text(address, style: MgType.small.copyWith(color: MgColors.meta)),
            ]),
          ),
        ]),
      ],
      const SizedBox(height: MgSpace.s8),
      if (pickupTime != null) PayFactRowV2(label: tr.tr('pickupTimeLabel'), value: pickupTime!),
      if (returnTime != null) PayFactRowV2(label: tr.tr('returnTimeLabel'), value: returnTime!),
      if (paidTotal != null && cardCharge(paidTotal!).kind == CardChargeKind.normal)
        PayFactRowV2(label: tr.tr('v2UxPsPaidLabel').toUpperCase(), value: Money.czk(paidTotal!)),
    ]);
  }

  List<PayStep> _steps(AppTranslations tr) {
    final s = start;
    final p = pickup;
    String? when;
    if (s != null) {
      when = [mgDayShort(s, tr.lang), if (pickupTime != null) pickupTime!].join(' ');
      if (p != null && (p.name ?? '').isNotEmpty) when = '$when · ${p.name}';
    }
    return [
      PayStep(tr.tr('v2UxPsStepEmail')),
      if (docs != PayDocsV2.unknown) PayStep(tr.tr('v2UxPsStepDocs'), [_docsBanner(tr)]),
      if (when != null)
        PayStep(tr.trArgs(p != null ? 'v2UxPsStepPickup' : 'v2UxPsStepStart', {'when': when}), [
          if (p != null) PayPickupActionsV2(info: p),
          if (lateGateDate != null)
            MgStateBanner(tone: MgTone.info, icon: MgIcons.clock, title: tr.trArgs('v2UxPsKioskNote', {'datum': lateGateDate!})),
        ]),
    ];
  }

  Widget _docsBanner(AppTranslations tr) {
    if (docs == PayDocsV2.missing) {
      final reason = missingReason;
      return MgStateBanner(
        tone: MgTone.warn,
        title: tr.tr('docsMissingTitle'),
        text: reason != null ? '$reason\n\n${tr.tr('docsMissingBody')}' : tr.tr('docsMissingBody'),
      );
    }
    final child = docs == PayDocsV2.child;
    return MgStateBanner(
      tone: MgTone.ok,
      title: tr.tr(child ? 'docsChildBikeTitle' : 'docsVerifiedTitle'),
      text: tr.tr(child ? 'docsChildBikeBody' : 'docsVerifiedBody'),
    );
  }
}
