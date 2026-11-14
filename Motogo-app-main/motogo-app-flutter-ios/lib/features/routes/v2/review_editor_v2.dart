import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_haptic.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Scrim of the v2 sheets opened by the old review / rating code
/// (night@.55, V22 §5.2).
const rtSheetScrimV2 = Color(0x8C0A1F14);

/// One tappable star 44 × 44: pops when it turns on / off, selection haptic.
class RtStarButtonV2 extends StatelessWidget {
  final int index;
  final bool on;
  final double size;
  final VoidCallback? onTap;
  const RtStarButtonV2({super.key, required this.index, required this.on, required this.onTap, this.size = 32});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: '$index / 5',
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap == null
              ? null
              : () {
                  MgHaptic.select();
                  onTap!();
                },
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: MgPop(
                trigger: on,
                child: MgIcon(on ? MgIcons.starFilled : MgIcons.star,
                    size: size, color: on ? MgColors.star : MgColors.lineInput),
              ),
            ),
          ),
        ),
      );
}

/// Review editor (board TrasaDetail "napsat recenzi"): light sheet, title,
/// 5 × 44 stars, text area, "Přidat fotky (n)", pinned "Odeslat recenzi".
/// Every value / callback is the old editor state's.
class ReviewEditorV2 extends StatelessWidget {
  final String title;
  final int rating;
  final ValueChanged<int> onRate;
  final TextEditingController controller;
  final int photoCount;
  final VoidCallback onPick;
  final bool busy;
  final VoidCallback onSubmit;
  const ReviewEditorV2({
    super.key,
    required this.title,
    required this.rating,
    required this.onRate,
    required this.controller,
    required this.photoCount,
    required this.onPick,
    required this.busy,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgSheetFrame(
      title: title,
      footer: MgBtnInk(label: tr.tr('routeReviewSend'), busy: busy, onTap: busy ? null : onSubmit),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 1; i <= 5; i++) RtStarButtonV2(index: i, on: rating >= i, onTap: () => onRate(i)),
        ]),
        const SizedBox(height: MgSpace.s12),
        TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          style: MgType.body.copyWith(color: MgColors.ink),
          decoration: mgInputDecoration(context, hint: tr.tr('routeReviewTextHint')),
        ),
        const SizedBox(height: MgSpace.s12),
        MgBtnGhostLight(
          label: '${tr.tr('routeReviewPhotos')}${photoCount > 0 ? ' ($photoCount)' : ''}',
          icon: MgIcons.camera,
          onTap: onPick,
        ),
      ]),
    );
  }
}

/// Place rating (board Zazitky "Detail místa · hodnocení"): text block
/// (14/800 line + "Klepni na hvězdy a ohodnoť") left, 5 tappable 44 px
/// stars right (mine first, else the average); stacked under 320 px.
/// Taps = the old `_rate`; spinner while saving.
class PoiRatingV2 extends StatelessWidget {
  final double shown;
  final double? avg;
  final int count;
  final int? mine;
  final bool busy;
  final ValueChanged<int> onRate;
  const PoiRatingV2({
    super.key,
    required this.shown,
    required this.avg,
    required this.count,
    required this.mine,
    required this.busy,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final line = mine != null
        ? tr.tr('poiRateYours')
        : (count == 0 ? tr.tr('poiNoRatings') : '${mgRating(avg ?? 0, tr.lang)} · $count');
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      MgWordFit(child: Text(line, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)))),
      if (mine != null && count > 0)
        Text('${mgRating(avg ?? 0, tr.lang)} · $count', style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta)))
      else
        MgWordFit(child: Text(tr.tr('poiRateHint'), style: MgType.meta.copyWith(color: MgColors.meta))),
    ]);
    final stars = Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++) RtStarButtonV2(index: i, on: shown >= i - 0.25, size: 26, onTap: () => onRate(i)),
    ]);
    return LayoutBuilder(builder: (context, c) {
      final row = c.maxWidth >= 340;
      return Row(children: [
        if (row) Expanded(child: text) else Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, stars])),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link)),
          ),
        if (row) stars,
      ]);
    });
  }
}
