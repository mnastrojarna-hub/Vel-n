import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'pay_ink_button_v2.dart';

/// Shape of the v2 card sheets (light, r22 top — V22 R5.10).
const ShapeBorder kCardSheetShapeV2 = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(MgRadius.sheet)),
);

/// The visible input frame around Stripe's native `CardField` (V22 §2.2
/// lineInput): white, 1.5 px `#7C958A`, r12, 56 high, card icon. Only the
/// frame is ours — the field inside is the caller's, unchanged.
class CardFieldFrameV2 extends StatelessWidget {
  final Widget child;
  const CardFieldFrameV2({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        height: 56,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(MgRadius.action),
          border: Border.all(color: MgColors.lineInput, width: 1.5),
        ),
        child: Row(children: [
          const MgIcon(MgIcons.card, size: 20, color: MgColors.meta),
          const SizedBox(width: 6),
          Expanded(child: child),
        ]),
      );
}

/// v2 chrome of the in-app card sheets (Booking board "wallet", Android +
/// iOS; also the Android "add card" sheet): grabber 42×5, title 20/800 +
/// sub, ✕ 44 (disabled while paying), the platform's OFFICIAL wallet
/// button with the divider label, the card field in [CardFieldFrameV2]
/// with the "whole frame is tappable" helper, an ink pay button (spinner
/// inside while paying), the status / reason as a small T3 note and the
/// lock line. The card field keeps ONE place in the tree (keyed frame) in
/// every state — re-creating the native view mid-confirm would lose it.
class CardSheetV2 extends StatelessWidget {
  final String title;
  final String? sub;
  final bool processing;
  final VoidCallback onClose;
  final Widget? wallet;
  final String? dividerLabel;
  final Widget cardField;
  final String? helper;
  final String payLabel;

  /// The amount inside [payLabel] — drawn in neon as on the board.
  final String? payAmount;
  final VoidCallback? onPay;
  final String? note;

  /// [note] is the "payment is running" status (pending tone), else a
  /// reason to act on (warn tone).
  final bool noteIsStatus;

  const CardSheetV2({
    super.key,
    required this.title,
    this.sub,
    required this.processing,
    required this.onClose,
    this.wallet,
    this.dividerLabel,
    required this.cardField,
    this.helper,
    required this.payLabel,
    this.payAmount,
    required this.onPay,
    this.note,
    this.noteIsStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final metaStyle = MgType.meta.copyWith(color: MgColors.meta);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: MgColors.grabberLight, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    header: true,
                    child: MgWordFit(minScale: 0.8, child: Text(title, style: MgType.h3.copyWith(color: MgColors.ink))),
                  ),
                  if (sub != null)
                    Text(sub!, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta))),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            // Locked while paying (the result would be lost) — visibly dimmed.
            Opacity(
              opacity: processing ? 0.4 : 1,
              child: MgV2Back(close: true, style: MgBackStyle.light, onTap: processing ? null : onClose),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: MgSpace.s16),
              if (wallet != null) ...[
                wallet!,
                const SizedBox(height: 14),
                Row(children: [
                  const Expanded(child: Divider(color: MgColors.line, height: 1)),
                  if (dividerLabel != null)
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(dividerLabel!, style: metaStyle)),
                  const Expanded(child: Divider(color: MgColors.line, height: 1)),
                ]),
                const SizedBox(height: 14),
              ],
              CardFieldFrameV2(key: const ValueKey('card-field-frame-v2'), child: cardField),
              if (helper != null) ...[const SizedBox(height: 6), Text(helper!, style: metaStyle)],
              const SizedBox(height: MgSpace.s16),
              PayInkButtonV2(label: payLabel, amount: payAmount, onTap: onPay, busy: processing),
              if (note != null) ...[
                const SizedBox(height: MgSpace.s8),
                MgStateBanner(tone: noteIsStatus ? MgTone.pending : MgTone.warn, title: note!),
              ],
              const SizedBox(height: MgSpace.s10),
              Row(children: [
                const MgIcon(MgIcons.lock, size: 14, color: MgColors.meta),
                const SizedBox(width: 6),
                Expanded(child: Text('${tr.tr('encryptedPayment')} · Stripe PCI DSS Level 1', style: metaStyle)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
