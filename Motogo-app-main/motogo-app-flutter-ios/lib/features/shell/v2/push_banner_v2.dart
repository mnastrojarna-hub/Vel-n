import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// Foreground push banner in the v2 look (V22 §6.4 `shared/push-banner`):
/// door codes = night glass with a 1.5 px neon frame, key tile, title
/// 14/800, up to 4 lines, 8 s; message = night glass, chat tile, 2 lines,
/// 5 s. "Zobrazit" (44 high) → [onView] = the old banner action (the deep
/// link); ✕ 44 → [onClose] (hides it). It stays a SnackBar of the same
/// messenger as before (slot, timing and dismiss unchanged).
SnackBar pushBannerSnackV2({
  required String title,
  required String body,
  required bool doorCodes,
  required String viewLabel,
  required String closeLabel,
  required VoidCallback onView,
  required VoidCallback onClose,
  double lift = 0,
}) {
  return SnackBar(
    key: ValueKey(doorCodes ? 'push-v2-codes' : 'push-v2-msg'),
    behavior: SnackBarBehavior.floating,
    backgroundColor: MgColors.night.withValues(alpha: 0.96),
    elevation: 0,
    margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + lift),
    padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: doorCodes
          ? const BorderSide(color: MgColors.neon, width: 1.5)
          : BorderSide(color: MgColors.white(0.12)),
    ),
    duration: Duration(seconds: doorCodes ? 8 : 5),
    content: PushBannerV2(
      title: title,
      body: body,
      doorCodes: doorCodes,
      viewLabel: viewLabel,
      closeLabel: closeLabel,
      onView: onView,
      onClose: onClose,
    ),
  );
}

class PushBannerV2 extends StatelessWidget {
  final String title, body, viewLabel, closeLabel;
  final bool doorCodes;
  final VoidCallback onView, onClose;
  const PushBannerV2({
    super.key,
    required this.title,
    required this.body,
    required this.doorCodes,
    required this.viewLabel,
    required this.closeLabel,
    required this.onView,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: doorCodes ? MgColors.neonA(0.14) : MgColors.white(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: MgIcon(doorCodes ? MgIcons.key : MgIcons.chat, size: 20, color: doorCodes ? MgColors.neon : MgColors.onDark),
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        tile,
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: MgType.title.copyWith(fontSize: 14, color: doorCodes ? MgColors.neonText : MgColors.onDark)),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(body,
                    maxLines: doorCodes ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              ],
            ]),
          ),
        ),
        Semantics(
          button: true,
          label: closeLabel,
          excludeSemantics: true,
          onTap: onClose,
          child: MgPress(
            scale: 0.92,
            onTap: onClose,
            child: const SizedBox(
              key: ValueKey('push-v2-close'),
              width: 44,
              height: 44,
              child: Center(child: MgIcon(MgIcons.close, size: 18, color: MgColors.onDarkMeta)),
            ),
          ),
        ),
      ]),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Semantics(
          button: true,
          label: viewLabel,
          excludeSemantics: true,
          onTap: onView,
          child: MgPress(
            onTap: onView,
            child: Container(
              key: const ValueKey('push-v2-view'),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(viewLabel, style: MgType.button.copyWith(color: MgColors.neon)),
            ),
          ),
        ),
      ),
    ]);
  }
}
