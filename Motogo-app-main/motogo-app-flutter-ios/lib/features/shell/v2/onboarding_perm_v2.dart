import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'onboarding_parts_v2.dart';

/// Permission priming in the v2 look (board Prihlaseni "Oprávnění"): dark
/// header (‹ 44 at 16,55 when [onBack] is set, logo tile 40, "Vítej v
/// MotoGo24" 22/800, sub 14/600), a white sheet r22 with one row per
/// permission (dark icon tile 40 + 15/800 title + 12.5/600 text) and a dark
/// dock: the brand CTA [allowLabel] + "Přeskočit – nastavím později" when
/// [onSkip] is set. iOS passes no [onSkip] / [onBack] and its own label →
/// ONE button, App Store 5.1.1(iv) unchanged. Every callback is the old
/// overlay's; [busy] = its `_requesting` (spinner inside, no double tap).
class OnboardingPermV2 extends StatelessWidget {
  /// (titleKey, descKey) in the old overlay's order.
  final List<(String, String)> perms;
  final String allowLabel;
  final VoidCallback? onAllow;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;
  final bool busy;
  const OnboardingPermV2({
    super.key,
    required this.perms,
    required this.allowLabel,
    required this.onAllow,
    this.onSkip,
    this.onBack,
    this.busy = false,
  });

  static String iconFor(String titleKey) => switch (titleKey) {
        'permLocationTitle' => MgIcons.pin,
        'permCameraTitle' => MgIcons.camera,
        'permMicTitle' => MgIcons.ai,
        'permNotifTitle' => MgIcons.bell,
        'permPhotosTitle' => MgIcons.image,
        'obBiometricTitle' => MgIcons.finger,
        _ => MgIcons.shield,
      };

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    return OnbDarkPage(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
          child: SizedBox(
            height: 44,
            child: Row(children: [
              if (onBack != null) MgV2Back(onTap: busy ? null : onBack, style: MgBackStyle.dark),
              const Spacer(),
              const OnbLogoTile(size: 36, glow: 0.25),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: MgEnter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: MgWordFit(
                  minScale: 0.8,
                  child: Text(tr.tr('v2UxShPermTitle'), style: MgType.h2.copyWith(color: MgColors.onDark)),
                ),
              ),
              const SizedBox(height: 6),
              Text(tr.tr('v2UxShPermSub'), style: MgType.body.copyWith(color: MgColors.onDarkLead)),
            ]),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: ColoredBox(
              color: MgColors.surface,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: perms.length,
                separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: MgColors.line),
                itemBuilder: (context, i) => _PermRow(
                  icon: iconFor(perms[i].$1),
                  title: tr.tr(perms[i].$1),
                  text: tr.tr(perms[i].$2),
                ),
              ),
            ),
          ),
        ),
        ColoredBox(
          color: MgColors.surface,
          child: MgDock(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MgCta(
                key: const ValueKey('onb-perm-allow'),
                label: allowLabel,
                onTap: onAllow,
                busy: busy,
                loop: true,
                arrow: true,
                rank: RankTokens.brand,
              ),
              if (onSkip != null) ...[
                const SizedBox(height: 4),
                Center(
                  child: MgBtnText(
                    key: const ValueKey('onb-perm-skip'),
                    label: tr.tr('skipSetupLater'),
                    onTap: busy ? null : onSkip,
                    dark: true,
                  ),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PermRow extends StatelessWidget {
  final String icon, title, text;
  const _PermRow({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgIconTileDark(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: MgType.title.copyWith(color: MgColors.ink)),
                const SizedBox(height: 2),
                Text(text, style: MgType.small.copyWith(color: MgColors.meta)),
              ]),
            ),
          ]),
        ),
      );
}
