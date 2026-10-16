import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/widgets/error_feedback.dart' show callMotoGo, kMotoGoPhoneLabel;
import 'home_reveal.dart';

/// "Tvoje linka MotoGo24" (V22 §2.4 #13): Zavolat (existing `callMotoGo`)
/// and Napsat (Zprávy) as light ghost buttons — the screen's primary stays
/// the hero CTA.
class HomeLineCardV2 extends ConsumerWidget {
  const HomeLineCardV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: HomeReveal(
        sessionKey: 'home-line',
        child: MgCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: rank.uiLight, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/logo.webp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                        color: MgColors.panel, child: Center(child: MgIcon(MgIcons.moto, size: 20, color: MgColors.neon)))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr.tr('v2HomeLineKicker').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
                  const SizedBox(height: 4),
                  Text(tr.tr('v2HomeLineTitle'), style: MgType.title.copyWith(color: MgColors.ink)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _Ghost(
                    icon: MgIcons.phone,
                    title: tr.tr('v2StCall'),
                    sub: kMotoGoPhoneLabel.replaceAll(' ', '\u00A0'),
                    onTap: callMotoGo,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Ghost(
                    icon: MgIcons.chat,
                    title: tr.tr('v2StWrite'),
                    sub: tr.tr('v2HomeLineWriteSub'),
                    onTap: () => mgPushOrGo(context, Routes.messages),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(tr.tr('v2HomeLineSos'), style: MgType.small.copyWith(color: MgColors.lead)),
          ]),
        ),
      ),
    );
  }
}

class _Ghost extends StatelessWidget {
  final String icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _Ghost({required this.icon, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$title, $sub',
        excludeSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MgColors.link, width: 1.5),
            ),
            child: Row(children: [
              MgIcon(icon, size: 20, color: MgColors.link),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(title, style: MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.25, color: MgColors.link)),
                  Text(sub, style: MgType.tab(MgType.meta.copyWith(color: MgColors.lead))),
                ]),
              ),
            ]),
          ),
        ),
      );
}
