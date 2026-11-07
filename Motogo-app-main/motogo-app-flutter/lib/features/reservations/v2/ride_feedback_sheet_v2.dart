import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../reservation_models.dart';

/// v2 look of the "Napiš nám přímo, co máme zlepšit" sheet (V21 §5.5):
/// light sheet (grabber, ✕ 44, swipe-down), pencil tile + title 20/800,
/// "{bike} · #ID" meta + the given stars, the lock note as a T3 info
/// banner, the textarea with its 0 / 2000 counter and "Odeslat" pinned
/// above the keyboard (spinner inside while sending). DUMB: controller,
/// sending / empty state and [onSend] stay in the old sheet state.
class RideFeedbackSheetV2 extends StatelessWidget {
  final Reservation res;
  final int rating;
  final TextEditingController controller;
  final bool sending;
  final bool emptyTried;
  final int maxLength;
  final VoidCallback onSend;

  const RideFeedbackSheetV2({
    super.key,
    required this.res,
    required this.rating,
    required this.controller,
    required this.sending,
    required this.emptyTried,
    required this.maxLength,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final empty = controller.text.trim().isEmpty;
    return MgSheetFrame(
      title: tr.tr('rfImproveBtn'),
      footer: MgBtnInk(
        label: tr.tr('send'),
        icon: MgIcons.send,
        neonLabel: !empty,
        busy: sending,
        // Prázdný text: tlačítko zůstává klepnutelné — klepnutí vysvětlí
        // pod polem, proč nic neodešlo (stejně jako dnes).
        onTap: sending ? null : onSend,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const MgIconTileLight(MgIcons.edit, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${res.motoName} · ${res.shortId}',
                style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta)),
          ),
          if (rating > 0) ...[
            const SizedBox(width: 8),
            Semantics(
              label: tr.trArgs('starsCount', {'n': rating}),
              excludeSemantics: true,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 5; i++)
                  MgIcon(i < rating ? MgIcons.starFilled : MgIcons.star,
                      size: 14, color: i < rating ? MgColors.star : MgColors.starOffLight),
              ]),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        MgStateBanner(tone: MgTone.info, icon: MgIcons.lock, title: tr.tr('rfSheetInfo')),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          autofocus: true,
          enabled: !sending,
          minLines: 4,
          maxLines: 8,
          maxLength: maxLength,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: MgType.body.copyWith(color: MgColors.ink),
          decoration: mgInputDecoration(
            context,
            hint: tr.tr('rfSheetHint'),
            error: emptyTried && empty ? tr.tr('rfEmpty') : null,
          ).copyWith(
            hintMaxLines: 6,
            counterStyle: MgType.tab(MgType.micro.copyWith(color: MgColors.meta)),
          ),
        ),
      ]),
    );
  }
}
