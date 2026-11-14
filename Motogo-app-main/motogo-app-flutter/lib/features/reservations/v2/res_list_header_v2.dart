import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_frame.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../loyalty/loyalty_provider.dart';
import 'res_fit_v2.dart';

/// Compact dark rank header of the Rezervace tab (V22 `.ls-h`) with the OLD
/// header's content (owner 2026-11-07 "jen upgrade vzhledu"): the always
/// visible back (tab root → Domů, as the old `MgBackArrow`), the logo (in
/// the tier ring, R1), "Moje rezervace" + "Přehled všech rezervací".
class ResListHeaderV2 extends ConsumerWidget {
  const ResListHeaderV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final frame = RankFrame(
      size: 44,
      showMarks: false,
      semanticLabel: status == null ? null : RankCopy.aria(tr, status.level, RankCopy.name(tr, status.level, status.rankName), status.percent),
      child: Image.asset(
        'assets/logo.webp',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: MgColors.neon,
          child: Center(child: MgIcon(MgIcons.moto, size: 22, color: MgColors.onNeon)),
        ),
      ),
    );
    return MgRankHero(
      ambientKey: 'reservations',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: LayoutBuilder(builder: (context, c) {
        final titleStyle = MgType.h2.copyWith(color: MgColors.onDark);
        // The logo only while the title keeps whole words beside it (de
        // "Reservierungen" at 320 / large text) — the back always stays.
        final logo = resWordsFit(context, tr.tr('myReservations'), titleStyle, c.maxWidth - 52 - 52 - 10, minScale: 0.75);
        return Row(children: [
          MgV2Back(key: const ValueKey('res-list-back'), onTap: () => context.go(Routes.home), style: MgBackStyle.dark),
          const SizedBox(width: 8),
          if (logo) ...[Padding(padding: const EdgeInsets.all(4), child: frame), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: MgWordFit(minScale: 0.75, child: Text(tr.tr('myReservations'), style: titleStyle)),
              ),
              const SizedBox(height: 2),
              Text(tr.tr('resOverview'), style: MgType.small.copyWith(color: MgColors.onDarkSecondary)),
            ]),
          ),
        ]);
      }),
    );
  }
}
