import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/shell/mg_origin_chip.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'catalog_mode.dart';
import 'catalog_mode_switch_v2.dart';

/// Dark rank header of the v2 Motorky tab (board `.hd`), with the OLD search
/// header's controls (owner 2026-11-07 "jen upgrade vzhledu"): the always
/// visible back (tab root → Domů, as `MgBackArrow` there) and the title (no
/// profile button: it doubled the Profil tab, owner 2026-11-14), then the
/// calculator mode switch (V21 #2). The Velín banner is the shell's band
/// above it (5.0.1, as on every page). The dates, the filter panel and the
/// count are in the page (inline, as on the old screen), not here. A jump
/// with a hint (Rezervace → "Nová rezervace") says it under the title.
class MotorkyHeaderV2 extends StatelessWidget {
  final CatalogMode mode;
  final ValueChanged<CatalogMode> onMode;
  final VoidCallback onBack;

  const MotorkyHeaderV2({
    super.key,
    required this.mode,
    required this.onMode,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Semantics(
                header: true,
                child: MgWordFit(
                  minScale: 0.8,
                  child: Text(tr.tr('v2TabBikes'), style: MgType.h2.copyWith(color: MgColors.onDark, height: 1)),
                ),
              ),
              // "Vyber si motorku" after Rezervace → "Nová rezervace" (5.0.3).
              const MgOriginHint(tab: 1),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        CatalogModeSwitchV2(mode: mode, onChanged: onMode),
      ]),
    );
  }
}
