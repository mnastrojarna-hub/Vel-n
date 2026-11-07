import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import 'poi_cat_icon_v2.dart';

/// Place detail sheet head (light): stop number (route stops only), name
/// and the category chip with its line icon (V of the old name row + emoji
/// chip in `route_poi_sheet.dart`).
class PoiSheetHeadV2 extends StatelessWidget {
  final int? index;
  final String name;
  final String catKey;
  final String catLabel;
  const PoiSheetHeadV2({super.key, required this.index, required this.name, required this.catKey, required this.catLabel});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (index != null) ...[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: MgColors.panel,
              shape: BoxShape.circle,
              border: Border.all(color: MgColors.neon, width: 1.5),
            ),
            child: Center(
              child: Text('${index! + 1}', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon))),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: Semantics(header: true, child: Text(name, style: MgType.h2.copyWith(color: MgColors.ink)))),
      ]),
      const SizedBox(height: 10),
      Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PoiCatIconV2(catKey, size: 16, color: MgColors.link),
          const SizedBox(width: 6),
          Flexible(child: Text(catLabel, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
        ]),
      ),
    ]);
  }
}

/// "3 / 12" counter of the sibling swipe (light sheet).
class PoiSheetCounterV2 extends StatelessWidget {
  final String text;
  const PoiSheetCounterV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: MgColors.nightA(0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.white(0.25)),
        ),
        child: Text(text, style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark))),
      );
}

/// "Přidat do mé cesty" / "Odebrat z mé cesty" — the same toggle. Not yet
/// added = the sheet's one primary: rank CTA in a dark dock (board TrasyHub
/// "Detail místa", V21 T4); added = light ghost "✓ Odebrat z mé cesty".
class PoiTripButtonV2 extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const PoiTripButtonV2({super.key, required this.selected, required this.onTap});

  /// Height the sheet content keeps free under its last line.
  static const double inset = 92;

  @override
  Widget build(BuildContext context) {
    final label = t(context).tr(selected ? 'poiRemoveFromTrip' : 'poiAddToTrip');
    if (selected) {
      return DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: MgShadows.sticky),
        child: MgBtnGhostLight(label: label, icon: MgIcons.checkCircle, onTap: onTap, height: 52),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: MgGradients.dark,
        borderRadius: BorderRadius.circular(20),
        boxShadow: MgShadows.sticky,
      ),
      child: MgCta(label: label, leadingIcon: MgIcons.pinPlus, onTap: onTap),
    );
  }
}

/// ‹ › 44 discs of the sibling swipe (board "1 / 12 ‹ ›") — the same `_go`
/// as the swipe; disabled at the ends.
class PoiSheetNavV2 extends StatelessWidget {
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const PoiSheetNavV2({super.key, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget disc(String icon, VoidCallback? tap, String label) => Opacity(
          opacity: tap == null ? 0.45 : 1,
          child: MgIconButton(icon: icon, onTap: tap, semanticLabel: label, style: MgIconButtonStyle.photo),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      disc(MgIcons.chevronLeft, onPrev, tr.tr('v2UxRrPrevPlace')),
      const SizedBox(width: 8),
      disc(MgIcons.chevronRight, onNext, tr.tr('v2UxRrNextPlace')),
      const SizedBox(width: 8),
    ]);
  }
}

/// The 44 px ✕ over the place photo (V22 §6.1, photo style) — the same
/// `maybePop` as the old 32 px cross.
class PoiSheetCloseV2 extends StatelessWidget {
  const PoiSheetCloseV2({super.key});

  @override
  Widget build(BuildContext context) =>
      MgV2Back(close: true, style: MgBackStyle.photo, onTap: () => Navigator.of(context).maybePop());
}

/// v2 look of the photo-credit sheet: the credit sentence and "Zobrazit
/// zdroj" ([onOpen] null = not a Commons photo, no link).
class PoiPhotoCreditV2 extends StatelessWidget {
  final String text;
  final String openLabel;
  final VoidCallback? onOpen;
  const PoiPhotoCreditV2({super.key, required this.text, required this.openLabel, required this.onOpen});

  @override
  Widget build(BuildContext context) => MgSheetFrame(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const MgIcon(MgIcons.camera, size: 20, color: MgColors.meta),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: MgType.body.copyWith(color: MgColors.body2))),
          ]),
          if (onOpen != null) ...[
            const SizedBox(height: 8),
            MgBtnText(label: openLabel, icon: MgIcons.external, onTap: onOpen),
          ],
        ]),
      );
}
