import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/widgets/state_views.dart';
import '../shop_models.dart';
import 'product_card_v2.dart';

/// Bag button of the dark shop headers: 44 disc + count badge that bumps
/// when the count rises (PS-20); tap = the screen's own cart route.
class ShopBagButtonV2 extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const ShopBagButtonV2({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => MgBump(
        trigger: count,
        child: MgIconButton(
          key: const ValueKey('shop-v2-bag'),
          icon: MgIcons.bag,
          badge: count,
          onTap: onTap,
          semanticLabel: '${t(context).tr('cartTitle')}${count > 0 ? ', $count' : ''}',
        ),
      );
}

/// v2 look of the e-shop (Profil board S11 "E-shop"): compact dark app bar
/// (the screen's back) with the bag button, the gift voucher as the one
/// dark hero (key sales offer, rank CTA "KOUPIT POUKAZ" → the voucher
/// route), "MOTOGO SHOP" and the product cards; loading = skeleton in the
/// card geometry, error / empty as v2 states; pull-to-refresh = the
/// existing retry. Products / cart / routes are the screen's.
class ShopViewV2 extends StatelessWidget {
  final AsyncValue<List<Product>> products;
  final int cartCount;
  final VoidCallback onBack;
  final VoidCallback onCart;
  final VoidCallback onVoucher;
  final void Function(Product) onProduct;
  final VoidCallback onRetry;

  const ShopViewV2({
    super.key,
    required this.products,
    required this.cartCount,
    required this.onBack,
    required this.onCart,
    required this.onVoucher,
    required this.onProduct,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    // The old voucher banner: the gift-voucher picture on top and the WHOLE
    // banner opens /voucher (the CTA inside is the same action).
    final hero = MgPress(
      key: const ValueKey('shop-v2-voucher-banner'),
      onTap: onVoucher,
      child: MgDarkHero(
      rankAura: true,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(MgRadius.hero)),
          child: Image.asset('assets/darkovy-poukaz.webp', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MgSpace.heroH, vertical: MgSpace.heroV),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MgIconTileDark(MgIcons.gift),
        const SizedBox(height: MgSpace.s12),
        MgWordFit(minScale: 0.75, child: Text(tr.tr('giftVoucher'), style: MgType.h2.copyWith(color: MgColors.onDark))),
        const SizedBox(height: 4),
        Text('${tr.tr('voucherDesc')} · ${tr.tr('voucherType')}', style: MgType.body.copyWith(color: MgColors.onDarkLead)),
        const SizedBox(height: MgSpace.s16),
        MgCta(key: const ValueKey('shop-v2-voucher'), label: tr.tr('buyVoucher'), onTap: onVoucher, size: MgCtaSize.md56),
          ]),
        ),
      ]),
      ),
    );
    final Widget grid = products.when(
      data: (list) {
        if (list.isEmpty) {
          return MgStateBanner(tone: MgTone.info, icon: MgIcons.bag, plain: true, title: tr.tr('shopEmpty'));
        }
        return Column(children: [
          for (var i = 0; i < list.length; i += 2) ...[
            if (i > 0) const SizedBox(height: MgSpace.s12),
            ProductRowV2(
              left: ProductCardV2(product: list[i], onTap: () => onProduct(list[i])),
              right: i + 1 < list.length ? ProductCardV2(product: list[i + 1], onTap: () => onProduct(list[i + 1])) : null,
            ),
          ],
        ]);
      },
      loading: () => const ProductGridSkeletonV2(),
      error: (e, _) => MgErrorView(error: e, what: tr.tr('eoProductsLoadFail'), onRetry: onRetry, contact: false, compact: true),
    );
    return MgPage(
      header: MgAppBar(
        title: tr.tr('shopTitle'),
        subtitle: tr.tr('shopSubtitle'),
        onBack: onBack,
        actions: [ShopBagButtonV2(count: cartCount, onTap: onCart)],
      ),
      overlapHero: false,
      overscrollColor: MgColors.night,
      onRefresh: () async => onRetry(),
      sections: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MgSpace.gutter, MgSpace.s16, MgSpace.gutter, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            hero,
            const SizedBox(height: MgSpace.s20),
            const Align(alignment: Alignment.centerLeft, child: MgEyebrowDark('MOTOGO SHOP')),
            const SizedBox(height: MgSpace.s12),
            grid,
          ]),
        ),
      ],
    );
  }
}
