import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/chrome/mg_to_top.dart' show kMgToTopSlot;
import '../../../core/v2/gestures/mg_zone_snap.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/widgets/state_views.dart';
import '../shop_models.dart';
import 'product_card_full_v2.dart';
import 'product_card_parts_v2.dart';
import 'shop_bag_button_v2.dart';
import 'shop_screen_list_v2.dart';
import 'shop_voucher_hero_v2.dart';

export 'shop_bag_button_v2.dart';

/// v2 look of the e-shop: compact dark app bar (the screen's back) with the
/// bag button, the gift voucher as the one dark hero (rank CTA "KOUPIT
/// POUKAZ" → the voucher route), "MOTOGO SHOP" and — browsed like the bikes
/// (owner 2026-11-27) — ONE PRODUCT PER SCREEN: full-screen photo cards the
/// page snaps on, one product per swipe, "n / total", the round arrow back
/// to the top. Loading = skeletons in the card geometry, error / empty as v2
/// states; pull-to-refresh = the existing retry. Products / cart / routes
/// are the screen's.
class ShopViewV2 extends StatefulWidget {
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
  State<ShopViewV2> createState() => _ShopViewV2State();
}

class _ShopViewV2State extends State<ShopViewV2> {
  /// One product per screen: the cards the page scroll settles on.
  final MgSnapZone _zone = MgSnapZone();

  /// The "back to the top" arrow is shown (the captions ride above it).
  final ValueNotifier<bool> _topShown = ValueNotifier(false);

  @override
  void dispose() {
    _topShown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final w = widget;
    final h = shopScreenHeight(context);
    final top = MediaQuery.paddingOf(context).top;
    Widget boxed(Widget child) => SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: MgSpace.gutter), child: child),
        );
    final Widget list = w.products.when(
      data: (list) {
        if (list.isEmpty) {
          return boxed(MgStateBanner(tone: MgTone.info, icon: MgIcons.bag, plain: true, title: tr.tr('shopEmpty')));
        }
        return ShopScreenListV2(
          products: list,
          zone: _zone,
          height: h,
          card: (context, i) => ValueListenableBuilder<bool>(
            valueListenable: _topShown,
            builder: (_, toTop, __) => ProductCardFullV2(
              key: ValueKey('shop-card-${list[i].id}'),
              product: list[i],
              index: i,
              total: list.length,
              cartCount: w.cartCount,
              // The old card's tap: the screen's own product route.
              onOpen: () => w.onProduct(list[i]),
              onBack: w.onBack,
              onCart: w.onCart,
              height: h,
              topInset: top,
              liftExtra: toTop ? kMgToTopSlot : 0,
            ),
          ),
        );
      },
      loading: () => SliverToBoxAdapter(child: ShopListSkeletonV2(cardHeight: h)),
      error: (e, _) =>
          boxed(MgErrorView(error: e, what: tr.tr('eoProductsLoadFail'), onRetry: w.onRetry, contact: false, compact: true)),
    );
    return MgPage(
      header: MgAppBar(
        title: tr.tr('shopTitle'),
        subtitle: tr.tr('shopSubtitle'),
        onBack: w.onBack,
        actions: [ShopBagButtonV2(count: w.cartCount, onTap: w.onCart)],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MgSpace.gutter, MgSpace.s16, MgSpace.gutter, MgSpace.s12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ShopVoucherHeroV2(onVoucher: w.onVoucher),
              const SizedBox(height: MgSpace.s20),
              const Align(alignment: Alignment.centerLeft, child: MgEyebrowDark('MOTOGO SHOP')),
            ]),
          ),
        ),
        list,
      ],
      overlapHero: false,
      overscrollColor: MgColors.night,
      onRefresh: () async => w.onRetry(),
      snap: _zone,
      toTop: true,
      toTopShown: _topShown,
    );
  }
}
