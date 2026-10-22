import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/widgets/net_image.dart';
import '../branches_info_provider.dart';
import '../branches_widgets.dart' show plainText, richText;
import 'branches_v2_parts.dart';
import 'branch_texts_v2.dart';

/// Pobočky in the v2 look (PLAN §2.5.2, seam view of `BranchesInfoScreen`):
/// the same CMS texts (h1, intro, per-branch badge / title / address /
/// hours, detail button, CTA box) as white cards with the branch photo, the
/// dark CTA box (rank CTA = the screen's one loop) and "Motorky na
/// pobočkách" (existing sheet). Pull-to-refresh = today's refresh.
class BranchesViewV2 extends StatelessWidget {
  final Map<String, String> tx;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final ValueChanged<int> onOpen;
  final VoidCallback onBook;
  final VoidCallback onMotosSheet;

  const BranchesViewV2({
    super.key,
    required this.tx,
    required this.onBack,
    required this.onRefresh,
    required this.onOpen,
    required this.onBook,
    required this.onMotosSheet,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    // Popisky z CMS; v cizím jazyce bez překladu (offline) appové texty.
    final tx = v2BranchTexts(tr, this.tx);
    return MgPage(
      header: MgAppBar(title: tr.tr('branchesLabel'), onBack: onBack),
      overlapHero: false,
      onRefresh: onRefresh,
      sections: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: MgEnter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: richText(tx['h1'], MgType.h2.copyWith(color: MgColors.ink))),
              const SizedBox(height: 8),
              richText(tx['intro'], MgType.body.copyWith(color: MgColors.body2)),
            ]),
          ),
        ),
        for (var i = 0; i < branchesInfoMapQueries.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: MgReveal(index: i, child: _BranchCard(tx: tx, i: i, onOpen: () => onOpen(i))),
          ),
        MgDarkHero(
          margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            richText(tx['cta.title'], MgType.section.copyWith(color: MgColors.onDark)),
            const SizedBox(height: 6),
            richText(tx['cta.text'], MgType.small.copyWith(color: MgColors.onDarkLead)),
            const SizedBox(height: 16),
            MgFabAvoid(child: MgCta(label: plainText(tx['cta.button'] ?? ''), loop: true, onTap: onBook)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: MgFabAvoid(
            kind: MgAvoidKind.tap,
            child: MgBtnGhostLight(label: tr.tr('branchesMotos'), icon: MgIcons.moto, onTap: onMotosSheet),
          ),
        ),
      ],
    );
  }
}

class _BranchCard extends StatelessWidget {
  final Map<String, String> tx;
  final int i;
  final VoidCallback onOpen;
  const _BranchCard({required this.tx, required this.i, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    String? v(String k) => tx['branches.$i.$k'];
    final photos = i < branchesInfoGallery.length ? branchesInfoGallery[i] : const <BranchPhoto>[];
    final band = Container(
      decoration: const BoxDecoration(gradient: MgGradients.dark),
      child: const Center(child: MgIcon(MgIcons.pin, size: 40, color: MgColors.neon)),
    );
    return MgFabAvoid(
      kind: MgAvoidKind.tap,
      child: Semantics(
        button: true,
        child: MgPress(
          scale: 0.985,
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: MgColors.line),
              boxShadow: MgShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 132,
                child: Stack(fit: StackFit.expand, children: [
                  photos.isEmpty
                      ? band
                      : MgImage(photos.first.thumbUrl, thumbWidth: 640, fit: BoxFit.cover, error: band, placeholder: band),
                  Positioned(left: 12, top: 12, child: BranchBadgeV2(html: v('badge'))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  richText(v('title'), MgType.h3.copyWith(color: MgColors.ink)),
                  const SizedBox(height: 10),
                  BranchLineV2(icon: MgIcons.pin, html: v('address')),
                  BranchLineV2(icon: MgIcons.clock, html: v('hours')),
                  const SizedBox(height: 4),
                  MgBtnInk(label: plainText(tx['detail_button'] ?? ''), icon: MgIcons.arrowRight, onTap: onOpen),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
