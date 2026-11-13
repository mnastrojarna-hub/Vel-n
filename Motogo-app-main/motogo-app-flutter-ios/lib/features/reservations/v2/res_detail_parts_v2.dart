import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../reservation_models.dart';
import 'res_status_v2.dart';

/// v2 look of the parts of the old `ResDetailTabContent` that draw
/// themselves (owner 2026-11-07 "jen upgrade vzhledu": the detail keeps the
/// old blocks in the old order, only restyled). Display only.

/// Kinds of the old `ResDetailButton` (btn-g / btn-out / danger / sos).
enum ResDetailButtonKind { primary, outlined, danger, sos }

/// The old detail button in the v2 look: primary → rank CTA (no loop — the
/// page's one fx is elsewhere), outlined → light ghost, danger → red,
/// sos → SOS. Same label, same [onTap].
class ResDetailButtonV2 extends StatelessWidget {
  final ResDetailButtonKind kind;
  final String label;
  final VoidCallback onTap;
  const ResDetailButtonV2({super.key, required this.kind, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => switch (kind) {
        ResDetailButtonKind.primary => MgCta(label: label, onTap: onTap, arrow: true, showMarks: false),
        ResDetailButtonKind.outlined => MgBtnGhostLight(label: label, onTap: onTap),
        ResDetailButtonKind.danger => MgBtnDestructive(label: label, onTap: onTap),
        ResDetailButtonKind.sos => MgBtnSos(label: label, onTap: onTap),
      };
}

/// Top of the old detail card: bike, #ID, the status badge (+ the ride's
/// rating when it has one).
class ResDetailHeadV2 extends ConsumerWidget {
  final Reservation res;
  const ResDetailHeadV2({super.key, required this.res});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // P2-04: unpaid = the same amber pill as the hero / list card (AFT-02).
    final unpaid = resPayFlag(res, ref.watch(pendingBookingFabProvider).valueOrNull) == ResPayFlag.unpaid;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(header: true, child: Text(res.motoName, style: MgType.h3.copyWith(color: MgColors.ink))),
      const SizedBox(height: 2),
      Text(res.shortId, style: MgType.tab(MgType.small.copyWith(color: MgColors.meta))),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ResStatusPill(status: res.displayStatus, live: false, warn: unpaid),
        if ((res.rating ?? 0) > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: MgColors.warnBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.warnBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MgIcon(MgIcons.starFilled, size: 13, color: MgColors.star),
              const SizedBox(width: 3),
              Text('${res.rating}/5', style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.warn))),
            ]),
          ),
      ]),
      const SizedBox(height: 12),
    ]);
  }
}

/// The old 12:00 kiosk note (self-service release from 12:00) + its CTA.
class ResLateGateV2 extends StatelessWidget {
  final String text;
  final String? ctaLabel;
  final VoidCallback? onCta;
  const ResLateGateV2({super.key, required this.text, this.ctaLabel, this.onCta});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MgColors.warnBg,
          borderRadius: BorderRadius.circular(MgRadius.action),
          border: Border.all(color: MgColors.warnBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgIcon(MgIcons.clock, size: 18, color: MgColors.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.warn, height: 1.4)),
            ),
          ]),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 10),
            MgBtnInk(label: ctaLabel!, icon: MgIcons.clock, onTap: onCta),
          ],
        ]),
      );
}

/// Caps label / card title of the old detail ("Finanční souhrn",
/// "DOKUMENTY") in the v2 type.
class ResDetailLabelV2 extends StatelessWidget {
  final String text;
  final bool title;
  const ResDetailLabelV2(this.text, {super.key, this.title = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 8, top: title ? 0 : 4),
        child: Text(
          title ? text : text.toUpperCase(),
          style: title ? MgType.title.copyWith(color: MgColors.ink) : MgType.eyebrow.copyWith(color: MgColors.meta),
        ),
      );
}
