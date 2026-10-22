import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import 'booking_v2_parts.dart';

/// Mandatory consents (VOP + GDPR always, guardian for a kids' bike) with
/// the form's SAME setters; the hint stays while any is unticked (the CTA
/// is locked by the form's own rule). Under it the payment assurance line.
class BookingConsentsV2 extends StatelessWidget {
  final bool vop;
  final bool gdpr;
  final bool kids;
  final bool isKids;
  final ValueChanged<bool> onVop;
  final ValueChanged<bool> onGdpr;
  final ValueChanged<bool> onKids;

  const BookingConsentsV2({
    super.key,
    required this.vop,
    required this.gdpr,
    required this.kids,
    required this.isKids,
    required this.onVop,
    required this.onGdpr,
    required this.onKids,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final ok = vop && gdpr && (!isKids || kids);
    return BkCard(
      icon: MgIcons.docs,
      title: tr.tr('v2BkConsentsTitle'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgCheckRow(value: vop, onChanged: onVop, label: tr.tr('consentTermsVop')),
        const Divider(height: 1, color: MgColors.line),
        MgCheckRow(value: gdpr, onChanged: onGdpr, label: tr.tr('consentPersonalData')),
        if (isKids) ...[
          const Divider(height: 1, color: MgColors.line),
          MgCheckRow(value: kids, onChanged: onKids, label: tr.tr('consentKidsGuardian')),
        ],
        if (!ok)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: MgEnter(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgIcon(MgIcons.info, size: 16, color: MgColors.warn),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(tr.tr('v2BkConsentsNeed'),
                      style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.warn)),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          MgIcon(MgIcons.lock, size: 16, color: MgColors.link),
          const SizedBox(width: 6),
          Expanded(child: Text(tr.tr('v2BkAssure'), style: MgType.meta.copyWith(color: MgColors.meta))),
        ]),
      ]),
    );
  }
}
