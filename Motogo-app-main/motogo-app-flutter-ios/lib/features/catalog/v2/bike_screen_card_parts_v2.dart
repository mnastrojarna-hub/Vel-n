import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../moto_model.dart';
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
