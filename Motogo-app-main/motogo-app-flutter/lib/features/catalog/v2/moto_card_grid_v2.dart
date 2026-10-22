import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/widgets/net_image.dart';
import '../moto_model.dart';
import 'catalog_price.dart';
import 'catalog_text.dart';

/// Grid card of the v2 Motorky list (board `.gt`, light): photo 150 on
/// night, white body with "category · branch", name (2 lines), price in
/// `#0D6E0D` + struck list price. The whole card opens the detail through
/// [onOpen] (the caller's existing tap logic). Height = content (the list
/// pairs cards in rows of equal height, so long names / prices never clip).
class MotoCardGridV2 extends StatelessWidget {
  final Motorcycle moto;
  final CatCardPrice price;
  final String? availability;
  final VoidCallback onOpen;

  const MotoCardGridV2({
    super.key,
    required this.moto,
    required this.price,
    required this.availability,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final m = moto;
    final meta = [
      if (m.category != null && m.category!.isNotEmpty) catCategoryLabel(tr, m.category!),
      if ((m.branchName ?? m.branchCity) != null) (m.branchName ?? m.branchCity)!,
    ].join(' · ');
    final img = m.displayImage;
    return Semantics(
      button: true,
      label: '${m.model}, ${price.grid}',
      excludeSemantics: true,
      onTap: onOpen,
      child: MgPress(
        onTap: onOpen,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(MgRadius.card),
            border: Border.all(color: MgColors.line),
            boxShadow: MgShadows.card,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 150,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(
                  color: MgColors.night,
                  child: img.isEmpty
                      ? Center(child: MgIcon(MgIcons.moto, size: 40, color: MgColors.onDarkFloor))
                      : MgImage(
                          img,
                          thumbWidth: 500,
                          fit: BoxFit.cover,
                          placeholder: const ColoredBox(color: MgColors.night),
                          error: Center(child: MgIcon(MgIcons.moto, size: 40, color: MgColors.onDarkFloor)),
                        ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MgColors.nightA(0.45), MgColors.nightA(0)],
                      stops: const [0, 0.4],
                    ),
                  ),
                ),
                // Badge bounded by the card (left + right): a long label
                // ("Frei in deinem Zeitraum") scales a little to stay on 2
                // lines, else takes a 3rd ("Wolny w twoim terminie" at large
                // text, 320 dp) — never clipped, never cut.
                if (availability != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: MgColors.nightA(0.8), borderRadius: BorderRadius.circular(999)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: MgWordFit(
                              minScale: 0.8,
                              fitLines: 2,
                              child: Text(availability!, maxLines: 3, style: MgType.micro.copyWith(color: MgColors.onDark, height: 1.2)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (meta.isNotEmpty)
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MgType.micro.copyWith(color: MgColors.meta)),
                  const SizedBox(height: 4),
                  Text(m.model,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.title.copyWith(color: MgColors.ink, height: 1.2)),
                  const Spacer(),
                  Text(price.grid,
                      style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.price, height: 1.2))),
                  if (price.struck != null)
                    Text(price.struck!,
                        style: MgType.tab(MgType.meta.copyWith(
                            fontWeight: FontWeight.w600, color: MgColors.meta, decoration: TextDecoration.lineThrough))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
