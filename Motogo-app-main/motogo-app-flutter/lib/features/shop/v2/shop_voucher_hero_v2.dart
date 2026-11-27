import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// The gift voucher of the v2 shop — the old voucher banner as the one dark
/// hero: the gift-voucher picture on top and the WHOLE banner opens
/// `/voucher` (the rank CTA "KOUPIT POUKAZ" inside is the same action).
class ShopVoucherHeroV2 extends StatelessWidget {
  final VoidCallback onVoucher;
  const ShopVoucherHeroV2({super.key, required this.onVoucher});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgPress(
      key: const ValueKey('shop-v2-voucher-banner'),
      onTap: onVoucher,
      child: MgDarkHero(
        rankAura: true,
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(MgRadius.hero)),
            child: Image.asset('assets/darkovy-poukaz.webp',
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MgSpace.heroH, vertical: MgSpace.heroV),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const MgIconTileDark(MgIcons.gift),
              const SizedBox(height: MgSpace.s12),
              MgWordFit(
                  minScale: 0.75,
                  child: Text(tr.tr('giftVoucher'), style: MgType.h2.copyWith(color: MgColors.onDark))),
              const SizedBox(height: 4),
              Text('${tr.tr('voucherDesc')} · ${tr.tr('voucherType')}',
                  style: MgType.body.copyWith(color: MgColors.onDarkLead)),
              const SizedBox(height: MgSpace.s16),
              MgCta(
                  key: const ValueKey('shop-v2-voucher'),
                  label: tr.tr('buyVoucher'),
                  onTap: onVoucher,
                  size: MgCtaSize.md56),
            ]),
          ),
        ]),
      ),
    );
  }
}
