import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/i18n_provider.dart';
import '../../../features/loyalty/loyalty_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import 'rank_copy.dart';
import 'rank_frame.dart';
import 'rank_tokens.dart';

/// The MotoGo24 logo in the customer's tier ring (Home header, login,
/// catalog header…): `RankFrame` + the logo asset, screen-reader rank aria
/// from the existing loyalty status. [onTap] = the caller's existing action
/// (Home: the ranks screen); null = not tappable. [showBadge] = the level
/// badge of the frame.
class MgLogoRing extends ConsumerWidget {
  final double size;
  final bool showBadge;
  final VoidCallback? onTap;
  final RankTokens? rank;
  const MgLogoRing({super.key, this.size = 52, this.showBadge = true, this.onTap, this.rank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    Widget frame = RankFrame(
      size: size,
      rank: rank,
      showLevel: showBadge,
      semanticLabel: status == null
          ? null
          : RankCopy.aria(tr, status.level, RankCopy.name(tr, status.level, status.rankName), status.percent),
      child: Image.asset(
        'assets/logo.webp',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(
          color: MgColors.neon,
          child: Center(child: MgIcon(MgIcons.moto, size: size / 2, color: MgColors.onNeon)),
        ),
      ),
    );
    if (onTap != null) frame = MgPress(onTap: onTap, child: frame);
    return frame;
  }
}
