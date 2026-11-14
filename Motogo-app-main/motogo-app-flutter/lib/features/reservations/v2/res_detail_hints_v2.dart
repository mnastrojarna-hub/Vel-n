import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../documents/docs_gate_provider.dart';
import '../reservation_models.dart';
import '../widgets/res_pickup_procedure.dart';

/// Clarity hints of the v2 reservation detail (soupis pojistek 2026-11-12,
/// part "after"). Display only: every value comes from what the detail
/// already has; no rule, provider or target changes.

/// Upcoming self-service pickup before the rental term — the codes are
/// not shown yet (they appear only in the term, `ResAccessCodesCard`).
bool resBeforeTermSelfService(Reservation r) =>
    r.displayStatus == ResStatus.nadchazejici && !r.inRentalTerm && ResPickupProcedure.visibleFor(r);

/// AFT-02: payment row value of the detail's money card — translated and
/// coloured (amber unpaid, check + "Zaplaceno" paid) instead of the raw
/// `UNPAID` code; any other state keeps the old value.
class ResPayStatusValueV2 extends StatelessWidget {
  final Reservation res;
  const ResPayStatusValueV2({super.key, required this.res});

  @override
  Widget build(BuildContext context) {
    final tr = t(context).tr;
    final style = MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800));
    final s = res.paymentStatus;
    if (s == 'paid') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const MgIcon(MgIcons.check, size: 14, color: MgColors.link, stroke: 2.6),
        const SizedBox(width: 4),
        Text(tr('paid'), key: const ValueKey('res-pay-row-paid'), style: style.copyWith(color: MgColors.link)),
      ]);
    }
    if (s == 'unpaid') {
      return Container(
        key: const ValueKey('res-pay-row-unpaid'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: MgColors.warnBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.warnBorder),
        ),
        child: Text(tr('payStatusUnpaid'), style: style.copyWith(color: MgColors.warn)),
      );
    }
    final label = switch (s) {
      'refunded' => tr('payStatusRefunded'),
      'partial_refund' => tr('payStatusPartialRefund'),
      'refund_pending' => tr('payStatusRefundPending'),
      _ => s.toUpperCase(),
    };
    return Flexible(child: Text(label, textAlign: TextAlign.right, style: style.copyWith(color: MgColors.ink)));
  }
}

/// AFT-03b: before the term at a self-service branch with the documents
/// not complete — the codes are held back without them; one action to the
/// same documents screen as the codes card's "upload documents".
class ResDocsCodesBannerV2 extends ConsumerWidget {
  final Reservation res;
  const ResDocsCodesBannerV2({super.key, required this.res});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!resBeforeTermSelfService(res)) return const SizedBox.shrink();
    final complete = ref.watch(docsFabStatusProvider).valueOrNull?.isComplete ?? true;
    if (complete) return const SizedBox.shrink();
    final tr = t(context).tr;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MgStateBanner(
        key: const ValueKey('res-docs-codes-banner'),
        tone: MgTone.warn,
        icon: MgIcons.idCard,
        title: tr('claResDocsCodesHeld'),
        actions: [
          MgBtnInk(
            key: const ValueKey('res-docs-codes-btn'),
            label: tr('docsBlockingBtn'),
            icon: MgIcons.idCard,
            height: 44,
            expand: false,
            onTap: () => context.push(Routes.docs),
          ),
        ],
      ),
    );
  }
}

/// AFT-04: one muted line above the pickup steps — when the codes appear.
/// P2-06: with the documents not complete (the same check as the banner
/// above) it says the codes also wait for the documents.
class ResCodesWhenLineV2 extends ConsumerWidget {
  final Reservation res;
  const ResCodesWhenLineV2({super.key, required this.res});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!resBeforeTermSelfService(res)) return const SizedBox.shrink();
    final complete = ref.watch(docsFabStatusProvider).valueOrNull?.isComplete ?? true;
    return Padding(
      key: const ValueKey('res-codes-when'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: MgIcon(MgIcons.clock, size: 16, color: MgColors.meta),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(t(context).tr(complete ? 'claResCodesWhen' : 'jxCodesAfterDocs'), style: MgType.small.copyWith(color: MgColors.lead)),
        ),
      ]),
    );
  }
}
