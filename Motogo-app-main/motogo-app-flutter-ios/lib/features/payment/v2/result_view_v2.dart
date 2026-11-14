import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_emoji_map.dart';
import '../../../core/widgets/pickup_location_link.dart';
import '../payment_provider.dart';
import 'pay_parts_v2.dart';
import 'pay_steps_v2.dart';

/// Tone of the universal payment result (the screen decides which).
enum PayResultKindV2 { success, pending, attention, failed }

/// v2 look of `/payment-result` (Stavy T1): success = dark rank hero;
/// pending = ring sweep (the screen's live loop) + "Ověřit znovu" with the
/// spinner inside (the screen's own verify); attention = warn; failed /
/// not paid = error (the ✕ disc shakes once). The detail lines become
/// summary rows with line icons, the pickup block keeps its map action,
/// the next-step note is "CO BUDE DÁL". ✕ top-left and both buttons call
/// the screen's own navigation. When the outcome flips pending → success
/// on the same screen the tone disc morphs into the ✓. No support row.
class ResultViewV2 extends StatelessWidget {
  final PayResultKindV2 kind;
  final String title;
  final String subtitle;
  final List<PaymentOutcomeLine> lines;
  final PickupInfo? pickup;
  final String? nextStep;
  final bool synced;
  final String ctaLabel;
  final VoidCallback onCta;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final VoidCallback onClose;
  final bool verifying;
  final VoidCallback? onVerify;

  const ResultViewV2({
    super.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.lines,
    required this.pickup,
    required this.nextStep,
    required this.synced,
    required this.ctaLabel,
    required this.onCta,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.onClose,
    required this.verifying,
    required this.onVerify,
  });

  MgTone get _tone => switch (kind) {
        PayResultKindV2.success => MgTone.ok,
        PayResultKindV2.pending => MgTone.pending,
        PayResultKindV2.attention => MgTone.warn,
        PayResultKindV2.failed => MgTone.err,
      };

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final p = pickup;
    final hasSummary = lines.isNotEmpty || p != null;
    return MgStateScreen(
      tone: _tone,
      title: mgStripEmoji(title),
      why: mgStripEmoji(subtitle),
      onClose: onClose,
      support: false,
      summary: hasSummary
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < lines.length; i++) _line(lines[i], i > 0),
              if (p != null) ...[
                if (lines.isNotEmpty) const SizedBox(height: 10),
                _pickup(tr, p),
              ],
            ])
          : null,
      primary: MgStateAction(mgStripEmoji(ctaLabel), onCta),
      secondary: secondaryLabel != null && onSecondary != null ? MgStateAction(secondaryLabel!, onSecondary) : null,
      children: [
        if (onVerify != null)
          MgBtnGhostLight(
            key: const ValueKey('pay-result-verify'),
            label: tr.tr('psVerifyAgain'),
            icon: MgIcons.refresh,
            busy: verifying,
            onTap: verifying ? null : onVerify,
          ),
        if (nextStep != null) PayStepsCardV2(title: tr.tr('v2UxPsNext'), steps: [PayStep(mgStripEmoji(nextStep!))]),
        if (synced)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const MgIcon(MgIcons.lock, size: 14, color: MgColors.meta),
            const SizedBox(width: 6),
            Flexible(child: Text(tr.tr('v2UxPsSynced'), textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta))),
          ]),
      ],
    );
  }

  Widget _line(PaymentOutcomeLine l, bool divider) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: divider ? const Border(top: BorderSide(color: MgColors.line)) : null),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: MgIcon(payIconFor(l.icon), size: 18, color: MgColors.link)),
          const SizedBox(width: 10),
          Expanded(child: Text(mgStripEmoji(l.text), style: MgType.body.copyWith(color: MgColors.ink))),
        ]),
      );

  Widget _pickup(AppTranslations tr, PickupInfo p) {
    final name = (p.name ?? '').trim();
    final address = (p.address ?? '').trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: MgIcon(MgIcons.pin, size: 18, color: MgColors.link)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? tr.tr('confirmPickupTitle') : '${tr.tr('confirmPickupTitle')} · $name',
                style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
            if (address.isNotEmpty) Text(address, style: MgType.small.copyWith(color: MgColors.meta)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      PayPickupActionsV2(info: p),
    ]);
  }
}
