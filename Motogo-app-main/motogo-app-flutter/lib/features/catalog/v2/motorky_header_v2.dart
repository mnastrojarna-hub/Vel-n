import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/banner_provider.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/shell/mg_origin_chip.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'catalog_mode.dart';
import 'catalog_mode_switch_v2.dart';

/// Dark rank header of the v2 Motorky tab (board `.hd`), with the OLD search
/// header's controls (owner 2026-11-07 "jen upgrade vzhledu"): the always
/// visible back (tab root → Domů, as `MgBackArrow` there), the title and the
/// menu button (→ Profil, as the old hamburger), then the calculator mode
/// switch (V21 #2) and the CMS banner as its last line (the v2 shell does
/// not draw the banner on `/search`). The dates, the filter panel and the
/// count are in the page (inline, as on the old screen), not here.
class MotorkyHeaderV2 extends ConsumerWidget {
  final CatalogMode mode;
  final ValueChanged<CatalogMode> onMode;
  final VoidCallback onBack;
  final VoidCallback onMenu;

  const MotorkyHeaderV2({
    super.key,
    required this.mode,
    required this.onMode,
    required this.onBack,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final banner = ref.watch(bannerProvider).valueOrNull;
    return MgRankHero(
      ambientKey: 'motorky',
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // „‹ Domů / Pobočka" po skoku z jiné záložky (V22 §6.2).
        const MgOriginChip(tab: 1),
        Row(children: [
          MgV2Back(key: const ValueKey('motorky-back'), onTap: onBack, style: MgBackStyle.dark),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: MgWordFit(
                minScale: 0.8,
                child: Text(tr.tr('v2TabBikes'), style: MgType.h2.copyWith(color: MgColors.onDark, height: 1)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          MgIconButton(
            key: const ValueKey('motorky-menu'),
            icon: MgIcons.user,
            semanticLabel: tr.tr('v2TabProfile'),
            onTap: onMenu,
          ),
        ]),
        const SizedBox(height: 12),
        CatalogModeSwitchV2(mode: mode, onChanged: onMode),
        if (banner != null && banner.enabled && banner.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          // G-350: Velín colours as the old ShellHeaderBanner strip.
          Container(
            key: const ValueKey('motorky-banner-strip'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: banner.bg, borderRadius: BorderRadius.circular(8)),
            child: Semantics(
              liveRegion: false,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgIcon(MgIcons.info, size: 18, color: banner.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(banner.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: banner.color)),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
