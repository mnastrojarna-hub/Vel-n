import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_section.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/moto_model.dart';
import '../../catalog/v2/catalog_text.dart';
import 'booking_v2_parts.dart';

/// Recap ticket = the trip (Booking board `.tk`, CB-10): photo 96×64,
/// model 15/800, "pá 23. 10. → ne 25. 10." 14/800 + "3 dny" chip, then
/// "12:00 ½ → 19:00 · pobočka Mezná · s obsluhou" (delivery → "přistavení").
/// Without dates it offers "Vyber termín" ([onPickDates] = the form's own
/// date-card opener). Every value is the form's; nothing is computed here
/// except the labels. [footer] = a row drawn inside the card under a
/// divider (the express layout's "Termín a předání"). Only [moto] is
/// required (older callers stay source-compatible).
class BookingRecapV2 extends StatelessWidget {
  final Motorcycle moto;
  final DateTime? start;
  final DateTime? end;
  final int dayCount;
  final String? pickupTime;
  final String? returnTime;

  /// The first day is half price (the price breakdown's late-pickup
  /// discount is applied) → "½" after the pickup time.
  final bool half;
  final bool pickupDelivery;
  final VoidCallback? onPickDates;
  final Widget? footer;

  /// Optional: tap on the photo opens the bike's photos (the payment page's
  /// old swipeable gallery); [photoCount] > 1 shows a small count pill.
  final VoidCallback? onPhotoTap;
  final int photoCount;

  /// Branch place line with the city ("Mezná, Pelhřimov · s obsluhou"),
  /// as the payment page's old gallery card showed it.
  final bool withCity;

  const BookingRecapV2({
    super.key,
    required this.moto,
    this.start,
    this.end,
    this.dayCount = 0,
    this.pickupTime,
    this.returnTime,
    this.half = false,
    this.pickupDelivery = false,
    this.onPickDates,
    this.footer,
    this.onPhotoTap,
    this.photoCount = 0,
    this.withCity = false,
  });

  String _place(AppTranslations tr) {
    if (pickupDelivery) return tr.tr('v2UxCbDelivery');
    var b = catBranchLine(tr, moto);
    final city = (moto.branchCity ?? '').trim();
    final name = (moto.branchName ?? '').trim();
    if (b != null && withCity && name.isNotEmpty && city.isNotEmpty && !name.contains(city)) {
      b = b.replaceFirst(name, '$name, $city');
    }
    return b == null ? '' : tr.trArgs('v2UxCbAtBranch', {'branch': b});
  }

  Widget _photo(AppTranslations tr) {
    final photo = MgPhoto(
      url: moto.displayImage,
      thumbWidth: 240,
      width: 96,
      height: 64,
      glyph: MgIcons.moto,
      borderRadius: BorderRadius.circular(MgRadius.thumb),
    );
    final tap = onPhotoTap;
    if (tap == null) return photo;
    return Semantics(
      button: true,
      label: tr.trArgs('v2DetGalleryAria', {'n': 1, 'total': photoCount < 1 ? 1 : photoCount}),
      excludeSemantics: true,
      child: MgPress(
        key: const ValueKey('bk-recap-photo'),
        onTap: tap,
        child: Stack(children: [
          photo,
          if (photoCount > 1)
            PositionedDirectional(
              end: 4,
              bottom: 4,
              child: Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: MgColors.nightA(0.8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.white(0.22)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const MgIcon(MgIcons.camera, size: 12, color: MgColors.onDark),
                  const SizedBox(width: 3),
                  Text('$photoCount', style: MgType.tab(MgType.micro.copyWith(color: MgColors.onDark, height: 1))),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = start, e = end;
    final hasDates = s != null && e != null;
    final times = [
      if (pickupTime != null) '${pickupTime!}${half ? ' ½' : ''}',
      if (returnTime != null) returnTime!,
    ].join(' → ');
    final place = _place(tr);
    final line = [if (times.isNotEmpty) times, if (place.isNotEmpty) place].join(' · ');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.receipt),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _photo(tr),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgWordFit(minScale: 0.8, child: Text(moto.model, style: MgType.title.copyWith(color: MgColors.ink))),
              const SizedBox(height: 2),
              if (hasDates) ...[
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(catRange(tr, s, e).replaceAll(' ', ' ').replaceAll(' → ', ' → '),
                      style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
                  if (dayCount > 0) BkDaysChip(dayCount),
                ]),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(line, style: MgType.tab(MgType.small.copyWith(color: MgColors.lead))),
                ],
              ] else ...[
                Text(tr.tr('motoFromPrice').replaceAll('{price}', moto.priceLabel),
                    style: MgType.tab(MgType.small.copyWith(color: MgColors.lead))),
                if (place.isNotEmpty)
                  Text(place, style: MgType.small.copyWith(color: MgColors.lead)),
                if (onPickDates != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MgTextLink(label: tr.tr('v2UxCbPickDates'), onTap: onPickDates),
                  ),
              ],
            ]),
          ),
        ]),
        if (footer != null) ...[
          const SizedBox(height: MgSpace.s12),
          const Divider(height: 1, thickness: 1, color: MgColors.line),
          footer!,
        ],
      ]),
    );
  }
}
