import 'package:flutter/material.dart';

import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/gestures/mg_zone_snap.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../catalog/v2/bike_screen_list_v2.dart' show bikeScreenHeight, kBikeScreenGap;
import '../shop_models.dart';

/// Full card height of the shop list: the Motorky geometry (one item per
/// screen = the shell body with the hide-on-scroll chrome folded).
double shopScreenHeight(BuildContext context) => bikeScreenHeight(context);

/// The product list as one product per screen (owner 2026-11-27, "stejné
/// prohlížení jako motorky"): each card [height] tall + the bikes' gap, a
/// night status-bar region per card, in the [zone] the page physics snap on
/// (one product per swipe; a short settle under reduced motion). The page
/// keeps its place while a product page covers it, so Back lands on the
/// product the customer opened.
class ShopScreenListV2 extends StatelessWidget {
  final List<Product> products;
  final MgSnapZone zone;
  final double height;
  final Widget Function(BuildContext context, int index) card;

  const ShopScreenListV2({
    super.key,
    required this.products,
    required this.zone,
    required this.height,
    required this.card,
  });

  @override
  Widget build(BuildContext context) => MgSnapZoneSliver(
        zone: zone,
        extent: height + kBikeScreenGap,
        count: products.length,
        reduced: MgMotion.reduced(context),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              Widget c = MgStatusBar(dark: true, child: card(context, i));
              // The first two cards reveal once per session (as the routes).
              if (i < 2) c = MgReveal(index: i, sessionKey: 'shop-screen', child: c);
              return Padding(
                key: ValueKey('shop-screen-${products[i].id}'),
                padding: const EdgeInsets.only(bottom: kBikeScreenGap),
                child: c,
              );
            },
            childCount: products.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final i = products.indexWhere((p) => 'shop-screen-${p.id}' == key.value);
              return i < 0 ? null : i;
            },
          ),
        ),
      );
}
