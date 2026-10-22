import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_sheet.dart';
import '../../ride_share.dart' show RideShareTarget, RideShareTargetInfo, rideShareTap;

/// v2 "Sdílet jízdu" (light sheet, ✕): the same targets with the same
/// glyphs as today, the same text + map link and the same tap action
/// (`rideShareTap`: close, copy / open the app, failure snackbar).
Future<void> showRideShareSheetV2(BuildContext context, {required String text, required String link}) {
  return showMgSheet<void>(
    context,
    title: t(context).tr('rideShareTitle'),
    builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t(c).tr('rideShareSub'), style: MgType.body.copyWith(color: MgColors.body2)),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (c, box) {
        final cols = box.maxWidth >= 340 ? 3 : 2;
        final w = (box.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final target in RideShareTarget.values)
            SizedBox(width: w, child: _ShareTile(target: target, onTap: () => rideShareTap(c, target, text, link))),
        ]);
      }),
    ]),
  );
}

class _ShareTile extends StatelessWidget {
  final RideShareTarget target;
  final VoidCallback onTap;
  const _ShareTile({required this.target, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final copy = target == RideShareTarget.copy;
    final label = copy ? t(context).tr('rideShareCopy') : target.label;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: copy ? MgColors.ink : MgColors.well,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: copy ? MgColors.ink : MgColors.line),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            copy
                ? const MgIcon(MgIcons.copy, size: 22, color: MgColors.neon)
                : Text(target.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: copy ? MgColors.onDark : MgColors.ink)),
          ]),
        ),
      ),
    );
  }
}
