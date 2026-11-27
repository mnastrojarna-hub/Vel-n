import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../moto_model.dart';
import 'catalog_fit.dart';
import 'catalog_price.dart';

// Pieces of the full-screen bike card (`MotoCardFullV2`), split out so the
// card file stays under the size rule.

/// The branch mode as a caption tag ("samoobsluha" / "s obsluhou", the
/// chip's own words) when the branch chip has to drop it for room; null
/// when the branch type is unknown.
String? bikeCardModeTag(AppTranslations tr, Motorcycle m) {
  final type = (m.branchType ?? '').trim();
  if (type.isEmpty) return null;
  return tr.tr(type == 'samoobslužná' ? 'v2UxRpTypeSelf' : 'v2UxRpTypeStaffed');
}

/// "● Volná v termínu" / "● Dnes volná" over the card photo.
class BikeCardAvailabilityPill extends StatelessWidget {
  final String text;
  final bool live;

  /// Not free now ("Volná od 19. 11."): a calendar icon, no dot.
  final bool later;
  const BikeCardAvailabilityPill({super.key, required this.text, required this.live, this.later = false});

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: MgColors.nightA(0.8), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (later)
            MgIcon(MgIcons.calendarCheck, size: 14, color: MgColors.neon)
          else
            RepaintBoundary(child: MgPing(size: 8, color: MgColors.neon, active: live)),
          const SizedBox(width: 8),
          Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDark, height: 1)),
        ]),
      );
}

/// Category / licence / power tag of the card caption.
class BikeCardTag extends StatelessWidget {
  final String text;
  final bool neon;
  final bool bad;
  const BikeCardTag(this.text, {super.key, this.neon = false, this.bad = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bad ? MgColors.err : (neon ? MgColors.neon : MgColors.nightA(0.72)),
          borderRadius: BorderRadius.circular(6),
          border: neon ? null : Border.all(color: MgColors.white(0.18)),
        ),
        child: Text(text,
            style: MgType.micro.copyWith(
                fontWeight: FontWeight.w800, color: neon ? MgColors.onNeon : MgColors.onDark, letterSpacing: neon ? 0.4 : 0)),
      );
}

/// One "Základní údaje" chip.
class BikeCardSpecChip extends StatelessWidget {
  final String text;
  const BikeCardSpecChip(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: MgColors.white(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.white(0.14)),
        ),
        child: Text(text, maxLines: 1, style: MgType.meta.copyWith(color: MgColors.onDarkBody)),
      );
}

/// The card price (label, value + unit, struck list price, sub line).
class BikeCardPriceBlock extends StatelessWidget {
  final CatCardPrice price;
  const BikeCardPriceBlock({super.key, required this.price});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(price.label.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.neonText, fontSize: 11)),
        const SizedBox(height: 4),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, runSpacing: 2, children: [
          Text.rich(TextSpan(children: [
            TextSpan(
              text: price.value,
              style: MgType.tab(MgType.h1.copyWith(
                  color: MgColors.neon, height: 1, shadows: [Shadow(color: MgColors.neonA(0.25), blurRadius: 18)])),
            ),
            if (price.unit != null)
              TextSpan(text: ' ${price.unit}', style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
          ])),
          if (price.struck != null)
            Text(price.struck!,
                style: MgType.tab(MgType.small.copyWith(
                    color: MgColors.white(0.66), decoration: TextDecoration.lineThrough, decorationColor: MgColors.white(0.66)))),
        ]),
        const SizedBox(height: 4),
        MgWordFit(child: Text(price.sub, style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w600, color: MgColors.onDarkLead)))),
      ]);
}

/// The card's foot: the price and the action(s).
/// * One action ([onReserve] null): the price and the rank CTA [ctaLabel]
///   side by side when the price ("2 727 Kč /Tag") fits next to the button,
///   otherwise the button full width under it — as before 5.0.3.
/// * Two actions (owner 2026-11-27): the price on its own line, under it
///   [ctaLabel] ("Detail", secondary) and [reserveLabel] ("Rezervovat", the
///   rank CTA) in one row — "Detail" hugs its label while both fit, the two
///   share the row by their label widths when the labels need the 80 % fit
///   (`MgWordFit`), and they stack (Rezervovat first) when even that would
///   split a word (large text).
class BikeCardFoot extends StatelessWidget {
  final CatCardPrice price;
  final String model;
  final String ctaLabel;
  final VoidCallback onCta;
  final String? reserveLabel;
  final VoidCallback? onReserve;

  /// The looping fx of the primary (first card only).
  final bool live;

  const BikeCardFoot({
    super.key,
    required this.price,
    required this.model,
    required this.ctaLabel,
    required this.onCta,
    this.reserveLabel,
    this.onReserve,
    this.live = false,
  });

  static double _priceWidth(BuildContext context, CatCardPrice p) {
    final base = DefaultTextStyle.of(context).style;
    return catLineWidth(context, p.value, base.merge(MgType.tab(MgType.h1))) +
        (p.unit == null ? 0 : catLineWidth(context, ' ${p.unit}', base.merge(MgType.body.copyWith(fontWeight: FontWeight.w700))));
  }

  static double _ctaText(BuildContext context, String label) =>
      catLineWidth(context, label.toUpperCase(), DefaultTextStyle.of(context).style.merge(MgType.ctaCompact));

  /// MgCta sm48 around its label: 2 × 12 padding + border + arrow (+ a rank
  /// glyph allowance).
  static const double _ctaChrome = 24 + 3 + 26 + 26;

  /// MgBtnGhostDark around its label: 2 × 16 padding + border.
  static const double _ghostChrome = 32 + 3;

  Widget _primary(String label, VoidCallback onTap, bool expand) => MgFabAvoid(
        child: MgCta(
          label: label,
          onTap: onTap,
          size: MgCtaSize.sm48,
          expand: expand,
          arrow: true,
          loop: live,
          semanticLabel: '$label · $model',
        ),
      );

  @override
  Widget build(BuildContext context) {
    final reserve = reserveLabel;
    final onRes = onReserve;
    final block = IgnorePointer(child: BikeCardPriceBlock(price: price));
    return LayoutBuilder(builder: (context, c) {
      if (reserve == null || onRes == null) {
        // Price + CTA side by side only when the price fits next to the
        // button; otherwise the button goes full width under the price.
        final narrow = _priceWidth(context, price) + 12 + _ctaText(context, ctaLabel) + _ctaChrome > c.maxWidth;
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            block,
            const SizedBox(height: 12),
            _primary(ctaLabel, onCta, true),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: block),
          const SizedBox(width: 12),
          _primary(ctaLabel, onCta, false),
        ]);
      }
      final dText = catLineWidth(context, ctaLabel, DefaultTextStyle.of(context).style.merge(MgType.button));
      final rText = _ctaText(context, reserve);
      final dNat = dText + _ghostChrome, rNat = rText + _ctaChrome;
      Widget detail(bool expand) => Semantics(
            button: true,
            label: '$ctaLabel · $model',
            excludeSemantics: true,
            onTap: onCta,
            child: MgBtnGhostDark(
                key: const ValueKey('bike-card-detail'), label: ctaLabel, onTap: onCta, expand: expand),
          );
      final book = KeyedSubtree(key: const ValueKey('bike-card-reserve'), child: _primary(reserve, onRes, true));
      final List<Widget> actions;
      if (dNat + 8 + rNat <= c.maxWidth) {
        actions = [
          Row(children: [detail(false), const SizedBox(width: 8), Expanded(child: book)]),
        ];
      } else if (dText * 0.8 + _ghostChrome + 8 + rText * 0.8 + _ctaChrome <= c.maxWidth) {
        actions = [
          Row(children: [
            Expanded(flex: dNat.round(), child: detail(true)),
            const SizedBox(width: 8),
            Expanded(flex: rNat.round(), child: book),
          ]),
        ];
      } else {
        actions = [book, const SizedBox(height: 8), detail(true)];
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        block,
        const SizedBox(height: 12),
        ...actions,
      ]);
    });
  }
}

/// Reports [child]'s laid-out height after the frame (the card's caption
/// block: a short card keeps the sharp photo above it, 5.0.1 FV-02).
class BikeCaptionMeasure extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const BikeCaptionMeasure({super.key, required this.onHeight, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderBikeCaptionMeasure(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderBikeCaptionMeasure renderObject) => renderObject.onHeight = onHeight;
}

class RenderBikeCaptionMeasure extends RenderProxyBox {
  RenderBikeCaptionMeasure(this.onHeight);
  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(h);
    });
  }
}
