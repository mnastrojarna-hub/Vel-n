import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/gestures/mg_one_step.dart' show MgOnePagePhysics;
import '../../../core/v2/gestures/mg_zone_snap.dart' show MgSwipeAnchor, MgSwipeAnchorListener;
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../shop_models.dart';
import 'product_card_parts_v2.dart';

/// Photo height of the v2 product page (without the status-bar inset): as
/// tall as the screen is wide (+ the sheet's overlap), so a square product
/// photo fills the width; at most 55 % of the screen — the name, the price
/// and the dock stay on the first screen.
double productHeroHeight(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  final h = s.width + ProductHeroV2.sheetOverlap;
  final max = s.height * 0.55;
  return (h > max ? max : h).clamp(260.0, 560.0);
}

/// Photo hero of the v2 product page (owner 2026-11-27, "jako detail
/// motorky"): night, full width, under the status bar; the WHOLE photo
/// (contain) over its dimmed cover copy, a sideways pager for several
/// photos (one per swipe — [onPage] is the screen's own index setter),
/// segments, the photo-style ‹ = the screen's back, "● Skladem" /
/// "Vyprodáno" and the photo counter on the bottom scrim. The white sheet
/// of the page overlaps its last 24 px.
class ProductHeroV2 extends StatefulWidget {
  final Product product;
  final List<String> images;
  final int imageIndex;
  final ValueChanged<int> onPage;
  final VoidCallback onBack;
  final double height;

  /// The white sheet's overlap (`MgPage.overlap`): the photo stays above it.
  static const double sheetOverlap = 24;

  const ProductHeroV2({
    super.key,
    required this.product,
    required this.images,
    required this.imageIndex,
    required this.onPage,
    required this.onBack,
    required this.height,
  });

  @override
  State<ProductHeroV2> createState() => _ProductHeroV2State();
}

class _ProductHeroV2State extends State<ProductHeroV2> {
  final MgSwipeAnchor _swipe = MgSwipeAnchor();

  Widget _photo(String url) => MgPhoto(url: url, thumbWidth: 1000, fit: BoxFit.contain, dark: true, glyph: MgIcons.bag);

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final w = widget;
    final top = MediaQuery.paddingOf(context).top;
    final imgs = w.images;
    final multi = imgs.length > 1;
    final idx = w.imageIndex.clamp(0, imgs.length - 1);
    return MgStatusBar(
      dark: true,
      extendAbove: MgStatusBar.bounce,
      child: SizedBox(
        height: w.height + top,
        child: ColoredBox(
          color: MgColors.night,
          child: Stack(fit: StackFit.expand, children: [
            // Dark placeholder (never a light flash) and a 180 ms cross-fade
            // when the photo page changes (instant when reduced).
            ExcludeSemantics(
              child: Stack(fit: StackFit.expand, children: [
                AnimatedSwitcher(
                  duration: MgMotion.of(context, MgMotion.color),
                  child: KeyedSubtree(
                    key: ValueKey(idx),
                    child: MgPhoto(
                        url: imgs[idx],
                        thumbWidth: 400,
                        width: double.infinity,
                        height: double.infinity,
                        dark: true,
                        glyph: MgIcons.bag),
                  ),
                ),
                ColoredBox(color: MgColors.nightA(0.62)),
              ]),
            ),
            Padding(
              padding: EdgeInsets.only(top: top, bottom: ProductHeroV2.sheetOverlap),
              child: multi
                  ? MgSwipeAnchorListener(
                      anchor: _swipe,
                      axis: Axis.horizontal,
                      child: PageView.builder(
                        itemCount: imgs.length,
                        pageSnapping: false,
                        physics: MgOnePagePhysics(anchor: _swipe),
                        onPageChanged: w.onPage,
                        itemBuilder: (_, i) => _photo(imgs[i]),
                      ),
                    )
                  : _photo(imgs.first),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [MgColors.nightA(0.6), MgColors.nightA(0), MgColors.nightA(0), MgColors.nightA(0.7)],
                    stops: const [0, 0.24, 0.7, 1],
                  ),
                ),
              ),
            ),
            if (multi)
              Positioned(top: top + 4, left: 16, right: 16, child: ShopPhotoSegmentsV2(count: imgs.length, index: idx)),
            Positioned(top: top + 12, left: 16, child: MgV2Back(onTap: w.onBack, style: MgBackStyle.photo)),
            Positioned(
              left: 16,
              right: 16,
              bottom: ProductHeroV2.sheetOverlap + 12,
              child: Row(children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: w.product.inStock
                        ? ShopDarkPillV2(text: tr.tr('shopListInStock'), dot: true)
                        : ShopDarkPillV2(text: tr.tr('soldOut'), icon: MgIcons.ban, iconColor: MgColors.errDark),
                  ),
                ),
                const SizedBox(width: 8),
                if (multi)
                  Semantics(
                    label: tr.trArgs('v2UxCorePhotoOf', {'n': idx + 1, 'm': imgs.length}),
                    excludeSemantics: true,
                    child: ShopDarkPillV2(text: '${idx + 1} / ${imgs.length}', icon: MgIcons.camera),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
