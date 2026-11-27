import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_chrome_lift.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/gestures/mg_one_step.dart' show MgOnePagePhysics;
import '../../../core/v2/gestures/mg_zone_snap.dart' show MgSwipeAnchor, MgSwipeAnchorListener;
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../catalog/v2/bike_screen_card_parts_v2.dart' show BikeCaptionMeasure, BikeCardPriceBlock, BikeCardTag;
import '../../catalog/v2/catalog_fit.dart';
import '../shop_models.dart';
import 'product_card_parts_v2.dart';
import 'shop_bag_button_v2.dart';

/// One product per screen (owner 2026-11-27, "jako motorky"): a night card
/// as tall as the folded viewport. The WHOLE photo (contain) over its dimmed
/// cover copy in the room above the caption — several photos = a sideways
/// pager, one photo per swipe, segments and side tap zones as the bike card;
/// then the name, the first lines of the description, the sizes it is sold
/// in, the price in the bike card's words ("Skladem" / "Vyprodáno" under
/// it) and "DETAIL". Every tap opens the product page through [onOpen] —
/// the old card's tap. Top row: the screen's own back and cart actions
/// (the header is scrolled away here) and "n / total".
class ProductCardFullV2 extends StatefulWidget {
  final Product product;
  final int index;
  final int total;
  final int cartCount;
  final VoidCallback onOpen;
  final VoidCallback onBack;
  final VoidCallback onCart;
  final double height;

  /// Status-bar inset over the card's top edge (0 = none).
  final double topInset;

  /// Slot under the caption shown only with the bars out (the arrow up).
  final double liftExtra;

  const ProductCardFullV2({
    super.key,
    required this.product,
    required this.index,
    required this.total,
    required this.cartCount,
    required this.onOpen,
    required this.onBack,
    required this.onCart,
    this.height = 600,
    this.topInset = 0,
    this.liftExtra = 0,
  });

  @override
  State<ProductCardFullV2> createState() => _ProductCardFullV2State();
}

class _ProductCardFullV2State extends State<ProductCardFullV2> {
  final PageController _pc = PageController();
  final MgSwipeAnchor _swipe = MgSwipeAnchor();
  int _page = 0;

  /// Caption height: the photo keeps the room above it.
  double _capH = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _flip(int delta) {
    final n = widget.product.images.length;
    if (n < 2 || !_pc.hasClients) return;
    final next = (_page + delta).clamp(0, n - 1);
    if (next == _page) return;
    if (MgMotion.reduced(context)) {
      _pc.jumpToPage(next);
    } else {
      _pc.animateToPage(next, duration: MgMotion.sheet, curve: MgMotion.out);
    }
  }

  Widget _photo(String url) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: Padding(
          padding: EdgeInsets.only(top: widget.topInset),
          child: MgPhoto(url: url, thumbWidth: 900, fit: BoxFit.contain, dark: true, glyph: MgIcons.bag),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final p = widget.product;
    final top = widget.topInset;
    final h = widget.height;
    final imgs = p.images.isNotEmpty ? p.images : [p.displayImage];
    final multi = imgs.length > 1;
    final page = _page.clamp(0, imgs.length - 1);
    final name = p.nameFor(tr.lang);
    final desc = p.descriptionFor(tr.lang)?.trim();
    final price = productCardPrice(tr, p);
    final cta = tr.tr('motoCardDetail');
    // The photo ends where the caption starts (bars folded — the way the
    // list is browsed); a caption grown by large text leaves it ≥ 38 %.
    final pad = (_capH == 0 ? h * 0.36 : _capH).clamp(0.0, h * 0.62);

    final text = Semantics(
      button: true,
      label: [name, price.value, price.sub, if (p.needsSize) '${tr.tr('sizeLabel')}: ${p.sizes.join(', ')}'].join(', '),
      excludeSemantics: true,
      onTap: widget.onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!p.inStock) ...[BikeCardTag(tr.tr('soldOut').toUpperCase(), bad: true), const SizedBox(height: 8)],
        Text(name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: MgType.h2.copyWith(color: MgColors.onDark, shadows: [Shadow(color: MgColors.black(0.45), blurRadius: 16)])),
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
        ],
        if (p.needsSize) ...[const SizedBox(height: 10), ProductSizeChipsV2(sizes: p.sizes)],
        const SizedBox(height: 12),
      ]),
    );
    final foot = LayoutBuilder(builder: (context, c) {
      // Price + button side by side only when both fit on one line.
      final narrow = _priceWidth(context, price.value) + 12 + _ctaWidth(context, cta) > c.maxWidth;
      Widget button(bool expand) => MgFabAvoid(
            child: MgCta(
              key: ValueKey('shop-v2-open-${p.id}'),
              label: cta,
              onTap: widget.onOpen,
              size: MgCtaSize.sm48,
              expand: expand,
              arrow: true,
              semanticLabel: '$cta · $name',
            ),
          );
      if (narrow) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          BikeCardPriceBlock(price: price),
          const SizedBox(height: 12),
          button(true),
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: BikeCardPriceBlock(price: price)),
        const SizedBox(width: 12),
        button(false),
      ]);
    });
    // The caption on the night: free room for the top controls (a card grown
    // by large text never climbs over them), a fade, then the texts.
    final caption = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: top + 68),
      IgnorePointer(
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [MgColors.nightA(0), MgColors.night],
            ),
          ),
        ),
      ),
      BikeCaptionMeasure(
        onHeight: (v) {
          if (mounted && (v - _capH).abs() > 0.5) setState(() => _capH = v);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          child: ColoredBox(
            color: MgColors.night,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [text, foot]),
            ),
          ),
        ),
      ),
    ]);

    return Semantics(
      container: true,
      label: name,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: h),
        child: ColoredBox(
          color: MgColors.night,
          child: Stack(alignment: AlignmentDirectional.bottomStart, children: [
            // Under the caption's lift space: the same open as the photo.
            Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onOpen)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: pad,
              child: Stack(fit: StackFit.expand, children: [
                // Dimmed cover copy behind the whole (contain) photo — no
                // blur filter in lists; 180 ms cross-fade per photo.
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Stack(fit: StackFit.expand, children: [
                      AnimatedSwitcher(
                        duration: MgMotion.of(context, MgMotion.color),
                        child: KeyedSubtree(
                          key: ValueKey(page),
                          child: MgPhoto(
                              url: imgs[page],
                              thumbWidth: 400,
                              width: double.infinity,
                              height: double.infinity,
                              dark: true,
                              glyph: MgIcons.bag),
                        ),
                      ),
                      ColoredBox(color: MgColors.nightA(0.7)),
                    ]),
                  ),
                ),
                if (multi)
                  MgSwipeAnchorListener(
                    anchor: _swipe,
                    axis: Axis.horizontal,
                    child: PageView.builder(
                      controller: _pc,
                      itemCount: imgs.length,
                      pageSnapping: false,
                      physics: MgOnePagePhysics(anchor: _swipe),
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => KeyedSubtree(key: ValueKey('shop-photo-${p.id}-$i'), child: _photo(imgs[i])),
                    ),
                  )
                else
                  _photo(imgs.first),
                // Light controls stay readable on a white product photo.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [MgColors.nightA(0.6), MgColors.nightA(0), MgColors.nightA(0), MgColors.nightA(0.5)],
                        stops: const [0, 0.24, 0.82, 1],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            if (multi) ...[
              Positioned(top: top + 4, left: 14, right: 14, child: ShopPhotoSegmentsV2(count: imgs.length, index: page)),
              _zone(left: true, label: tr.tr('v2CatPhotoPrev'), bottom: pad),
              _zone(left: false, label: tr.tr('v2CatPhotoNext'), bottom: pad),
            ],
            MgChromeLift(room: h, extra: widget.liftExtra, child: caption),
            Positioned(
              top: top + 12,
              left: 14,
              right: 10,
              child: Row(children: [
                MgV2Back(onTap: widget.onBack, style: MgBackStyle.photo),
                if (widget.total > 1) ...[
                  const SizedBox(width: 8),
                  ShopPosPillV2(index: widget.index, total: widget.total),
                ],
                const Spacer(),
                ShopBagButtonV2(
                    key: ValueKey('shop-v2-card-bag-${p.id}'), count: widget.cartCount, onTap: widget.onCart, photo: true),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  static double _priceWidth(BuildContext context, String value) =>
      catLineWidth(context, value, DefaultTextStyle.of(context).style.merge(MgType.tab(MgType.h1)));

  /// MgCta sm48: label caps + 2 × 12 padding + border + arrow (+ a rank
  /// glyph allowance) — the bike card's rule.
  static double _ctaWidth(BuildContext context, String label) =>
      catLineWidth(context, label.toUpperCase(), DefaultTextStyle.of(context).style.merge(MgType.ctaCompact)) + 24 + 3 + 26 + 26;

  /// Side tap zone of the photo pager (the tap twin of the swipe).
  Widget _zone({required bool left, required String label, required double bottom}) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: widget.topInset + 68,
        bottom: bottom + 24,
        width: 64,
        child: Semantics(
          button: true,
          label: label,
          child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _flip(left ? -1 : 1)),
        ),
      );
}
