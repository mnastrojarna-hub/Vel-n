import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import 'res_edit_sections_v2.dart';
import 'res_detail_bits_v2.dart';

/// A note line of the edit (V22 `.ed-nt`): ok = tint (move is free), warn =
/// amber (storno conditions), plain = well.
class ResEditNoteV2 extends StatelessWidget {
  final String text;
  final bool ok;
  final bool warn;
  const ResEditNoteV2(this.text, {super.key, this.ok = false, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color border, Color fg, String icon) = ok
        ? (MgColors.tintOk, MgColors.tintOkBorder, MgColors.onTintOk, MgIcons.checkCircle)
        : warn
            ? (MgColors.warnBg, MgColors.warnBorder, MgColors.warn, MgIcons.info)
            : (MgColors.well, MgColors.line, MgColors.body2, MgIcons.info);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MgIcon(icon, size: 18, color: fg),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: fg))),
      ]),
    );
  }
}

/// Today's dynamic storno warning (100 / 50 / 0 % — the screen computes the
/// % from the NEW start, as the server does).
class ResStornoWarningV2 extends StatelessWidget {
  final int pct;
  const ResStornoWarningV2({super.key, required this.pct});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final (MgTone tone, String key) = pct == 100
        ? (MgTone.ok, 'refund100')
        : pct == 50
            ? (MgTone.warn, 'refund50')
            : (MgTone.err, 'refund0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: MgStateBanner(tone: tone, title: tr.tr(key)),
    );
  }
}

/// A titled v2 card around an existing edit widget (address picker / time).
class ResEditGroupV2 extends StatelessWidget {
  final String title;
  final Widget child;
  const ResEditGroupV2({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => EditCardV2(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ResSectionEyebrowV2(title),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

/// Pickup time: the same legacy "any time on day one" line and the
/// self-service ½ hint as today, around the screen's own time picker.
class ResPickupTimeV2 extends StatelessWidget {
  final Widget picker;
  final bool legacyLine;
  final bool selfServiceHint;
  const ResPickupTimeV2({super.key, required this.picker, required this.legacyLine, required this.selfServiceHint});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (legacyLine) ...[
        Text('${tr.pickupTime}: ${tr.tr('ssPickupAnyTime')}', style: MgType.small.copyWith(color: MgColors.lead)),
        const SizedBox(height: 8),
      ],
      picker,
      if (selfServiceHint) ...[
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 8, top: 1),
            decoration: const BoxDecoration(color: MgColors.neonLo, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('½', style: MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon)),
          ),
          Expanded(child: Text(tr.tr('ssPickupHint'), style: MgType.small.copyWith(color: MgColors.body2))),
        ]),
      ],
    ]);
  }
}

/// Missing gear sizes (blocks the save, as today).
class ResMissingSizesV2 extends StatelessWidget {
  final List<String> missing;
  const ResMissingSizesV2({super.key, required this.missing});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: MgStateBanner(
        tone: MgTone.warn,
        title: tr.tr('fillGearSizesOnDelivery'),
        text: '${tr.tr('missingLabel')}: ${missing.join(', ')}',
      ),
    );
  }
}
