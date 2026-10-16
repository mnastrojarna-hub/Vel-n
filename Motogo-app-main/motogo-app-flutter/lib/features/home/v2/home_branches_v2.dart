import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_section.dart';
import '../../branches/branches_info_provider.dart';
import '../../branches/branches_widgets.dart' show plainText;
import 'home_ticket_parts.dart';
import 'home_reveal.dart';

/// Pobočky (V22 §2.4 #12, web P5): Mezná = white card, Velké Němčice =
/// dark card (the lower page's one dark block). Texts = the same CMS keys as
/// `/pobocky` (`branchesInfoProvider`, defaults offline); → `/pobocky/:i`.
class HomeBranchesV2 extends ConsumerWidget {
  const HomeBranchesV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final lang = tr.lang;
    final tx = ref.watch(branchesInfoProvider(lang)).valueOrNull ?? branchesInfoDefaults;
    String v(String k) => plainText(tx[k] ?? branchesInfoDefaults[k] ?? '');
    final detail = v('detail_button');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgSectionHeader(
          title: tr.tr('v2HomeBranchesTitle'),
          trailingLabel: tr.tr('v2HomeAll'),
          onTrailing: () => mgPushOrGo(context, Routes.branchesInfo),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: HomeReveal(
                    index: i,
                    sessionKey: 'home-branches',
                    child: _BranchCard(
                      dark: i == 1,
                      badge: v('branches.$i.badge'),
                      title: v('branches.$i.title'),
                      address: v('branches.$i.address'),
                      detail: detail,
                      photo: branchesInfoGallery[i].isEmpty ? null : branchesInfoGallery[i].first.thumbUrl,
                      onTap: () => mgPushOrGo(context, '/pobocky/$i'),
                    ),
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

class _BranchCard extends StatelessWidget {
  final bool dark;
  final String badge;
  final String title;
  final String address;
  final String detail;
  final String? photo;
  final VoidCallback onTap;
  const _BranchCard({
    required this.dark,
    required this.badge,
    required this.title,
    required this.address,
    required this.detail,
    required this.photo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final top = SizedBox(
      height: 104,
      child: photo != null
          ? Stack(fit: StackFit.expand, children: [
              HomePhoto(url: photo, thumbWidth: 400),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [MgColors.nightA(0.1), MgColors.nightA(0.75)],
                  ),
                ),
              ),
            ])
          : ColoredBox(
              color: dark ? MgColors.night : MgColors.well,
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: MgColors.ink,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: MgColors.nightA(0.8), blurRadius: 16, offset: const Offset(0, 8), spreadRadius: -8)],
                  ),
                  child: const Center(child: MgIcon(MgIcons.pin, size: 20, color: MgColors.neon)),
                ),
              ),
            ),
    );
    return Semantics(
      button: true,
      label: '$title, $address, $detail',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: dark ? null : MgColors.surface,
            gradient: dark
                ? const RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.3,
                    colors: [MgColors.glow, MgColors.panel, MgColors.night],
                    stops: [0, 0.55, 1],
                  )
                : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dark ? MgColors.borderDark : MgColors.line),
            boxShadow: dark ? MgShadows.dark : MgShadows.card,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            top,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.3, color: dark ? MgColors.onDark : MgColors.ink)),
                  const SizedBox(height: 4),
                  Text(address, style: MgType.meta.copyWith(color: dark ? MgColors.onDarkLead : MgColors.meta)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: dark ? MgColors.neonA(0.12) : MgColors.tintOk,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(badge, style: MgType.micro.copyWith(color: dark ? MgColors.neonText : MgColors.link)),
                  ),
                  const Spacer(),
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: dark ? null : MgColors.ink,
                      borderRadius: BorderRadius.circular(12),
                      border: dark ? Border.all(color: MgColors.neon, width: 1.5) : null,
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(
                        child: Text(detail,
                            textAlign: TextAlign.center,
                            style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
                      ),
                      const SizedBox(width: 4),
                      const MgIcon(MgIcons.chevronRight, size: 16, color: MgColors.neon),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
