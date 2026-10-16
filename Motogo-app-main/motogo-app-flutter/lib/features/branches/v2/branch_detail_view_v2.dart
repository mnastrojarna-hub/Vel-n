import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../branch_motos_section.dart';
import '../branch_photos_section.dart';
import '../branches_info_provider.dart';
import '../branches_widgets.dart' show BranchVideo, plainText, richText;
import 'branches_v2_parts.dart';

/// Pobočka in the v2 look (PLAN §2.5.2, seam view of `BranchDetailScreen`):
/// dark hero (badge, title, address, hours, Navigovat), "O pobočce" card
/// (text + gear), the existing video player, collapsible "Jak to probíhá",
/// the existing photo / moto sections (their v2 look) and the dark CTA box
/// (book here = today's `_bookHere`). All values come from the screen.
class BranchDetailViewV2 extends StatelessWidget {
  final Map<String, String> tx;
  final int index;
  final String video;
  final String stepsTitle;
  final List<BranchPhoto> photos;
  final String? branchId;
  final VoidCallback onBack;
  final VoidCallback onNavigate;
  final VoidCallback onBook;

  const BranchDetailViewV2({
    super.key,
    required this.tx,
    required this.index,
    required this.video,
    required this.stepsTitle,
    required this.photos,
    required this.branchId,
    required this.onBack,
    required this.onNavigate,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    String? v(String k) => tx['branches.$index.$k'];
    return MgPage(
      header: MgAppBar(title: plainText(v('title') ?? ''), onBack: onBack),
      overlapHero: false,
      sections: [
        MgDarkHero(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: MgEnter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(alignment: AlignmentDirectional.centerStart, child: BranchBadgeV2(html: v('badge'), dark: true)),
              const SizedBox(height: 12),
              Semantics(header: true, child: richText(v('title'), MgType.h2.copyWith(color: MgColors.onDark))),
              const SizedBox(height: 12),
              BranchLineV2(icon: MgIcons.pin, html: v('address'), dark: true),
              BranchLineV2(icon: MgIcons.clock, html: v('hours'), dark: true),
              const SizedBox(height: 8),
              MgBtnGhostDark(label: tr.tr('branchesNavigate'), icon: MgIcons.navigate, onTap: onNavigate),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: MgCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              richText(v('text'), MgType.body.copyWith(color: MgColors.body2)),
              const SizedBox(height: 12),
              BranchLineV2(icon: MgIcons.jacket, html: v('gear')),
              if (video.startsWith('https://')) ...[
                const SizedBox(height: 8),
                richText(v('video_title'), MgType.title.copyWith(color: MgColors.ink)),
                const SizedBox(height: 8),
                BranchVideo(key: ValueKey(video), url: video),
              ],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: BranchCollapsibleV2(
            icon: MgIcons.compass,
            title: stepsTitle.isNotEmpty ? stepsTitle : tr.tr('pickupProcedure'),
            children: [richText(v('steps'), MgType.body.copyWith(color: MgColors.body2))],
          ),
        ),
        if (photos.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: BranchPhotosSection(photos: photos)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: BranchMotosSection(branchId: branchId)),
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
      ],
    );
  }
}
