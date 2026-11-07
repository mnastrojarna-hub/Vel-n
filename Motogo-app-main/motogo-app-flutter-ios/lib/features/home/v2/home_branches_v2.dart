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
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../branches/branches_info_provider.dart';
import '../../branches/branches_widgets.dart' show plainText;
import 'home_fit.dart';
import 'home_ticket_parts.dart';
import 'home_reveal.dart';
import '../../branches/v2/branch_texts_v2.dart';

/// Pobočky (V22 §2.4 #12, web P5): Mezná = white card, Velké Němčice =
/// dark card (the lower page's one dark block). Texts = the same CMS keys as
/// `/pobocky` (`branchesInfoProvider`, defaults offline); → `/pobocky/:i`.
class HomeBranchesV2 extends ConsumerWidget {
  const HomeBranchesV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final lang = tr.lang;
    // Popisky z CMS; v cizím jazyce bez překladu (offline) appové texty.
    final tx = v2BranchTexts(tr, ref.watch(branchesInfoProvider(lang)).valueOrNull ?? branchesInfoDefaults);
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
          // Vedle sebe, jen když se každé slovo názvu, štítku i tlačítka vejde
          // do půlky („Selbstbedienungsfiliale", „Vestigingsdetails") a
          // tlačítko má nejvýš 2 řádky; jinak karty pod sebou na celou šířku.
          child: LayoutBuilder(builder: (context, c) {
            Widget card(int i) => HomeReveal(
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
                );
            final inner = (c.maxWidth - 10) / 2 - 24 - 2;
            final side = [
              for (var i = 0; i < 2; i++) ...[
                (v('branches.$i.title'), _bcTitle, inner),
                (v('branches.$i.badge'), _bcBadge, inner - 16),
                (v('branches.$i.address'), _bcAddress, inner),
              ],
              (detail, _bcDetail, inner - 16 - 20),
            ].every((x) => homeWordsFitIn(context, x.$1, x.$2, x.$3)) &&
                // Tlačítko nejvýš na 2 řádky (ne „Détails / de / l'agence").
                homeLinesFitIn(context, detail, _bcDetail, inner - 16 - 20, 2);
            if (!side) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                IntrinsicHeight(child: card(0)),
                const SizedBox(height: 10),
                IntrinsicHeight(child: card(1)),
              ]);
            }
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: card(0)),
                const SizedBox(width: 10),
                Expanded(child: card(1)),
              ]),
            );
          }),
        ),
      ]),
    );
  }
}

final _bcTitle = MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.3);
const _bcAddress = MgType.meta;
const _bcBadge = MgType.micro;
final _bcDetail = MgType.small.copyWith(fontWeight: FontWeight.w800);

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
                  MgWordFit(minScale: 0.8, child: Text(title, style: _bcTitle.copyWith(color: dark ? MgColors.onDark : MgColors.ink))),
                  const SizedBox(height: 4),
                  MgWordFit(minScale: 0.85, child: Text(address, style: _bcAddress.copyWith(color: dark ? MgColors.onDarkLead : MgColors.meta))),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: dark ? MgColors.neonA(0.12) : MgColors.tintOk,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: MgWordFit(minScale: 0.85, child: Text(badge, style: _bcBadge.copyWith(color: dark ? MgColors.neonText : MgColors.link))),
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
                        child: MgWordFit(
                          minScale: 0.8,
                          alignment: Alignment.center,
                          child: Text(detail, textAlign: TextAlign.center, style: _bcDetail.copyWith(color: MgColors.onDark)),
                        ),
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
