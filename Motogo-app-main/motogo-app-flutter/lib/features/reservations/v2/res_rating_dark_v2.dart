import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../widgets/res_rating_widgets.dart' show GoogleGBadge;

/// Dark look of `ResRatingCard` inside CO TEĎ of a finished booking (V21
/// §5.3, Reservation board "Dokončeno"): star disc, "Hodnocení jízdy" +
/// question, five 40 px stars (`#F59E0B`), hint, then — once rated — the
/// same two options in the same order for 1–5★ (no gating) on glass tiles.
/// DUMB: the card's State keeps the optimistic rating, the write chain,
/// the Google link and the private feedback sheet.
class ResRatingDarkV2 extends StatelessWidget {
  final int rating;
  final String question;
  final int popTick;
  final String? sentThreadId;
  final ValueChanged<int> onRate;
  final VoidCallback onGoogle;
  final VoidCallback onFeedback;
  final VoidCallback onOpenThread;

  const ResRatingDarkV2({
    super.key,
    required this.rating,
    required this.question,
    required this.popTick,
    required this.sentThreadId,
    required this.onRate,
    required this.onGoogle,
    required this.onFeedback,
    required this.onOpenThread,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    // G-461/G-463: the only caller is the light reservation detail → a
    // solid dark board (a 6 % white tile was invisible on the light page).
    return Container(
      key: const ValueKey('res-rating-dark-v2'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: MgColors.night,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.white(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: MgColors.star, shape: BoxShape.circle),
            child: const Center(child: MgIcon(MgIcons.starFilled, size: 20, color: MgColors.panel)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: MgWordFit(
                  minScale: 0.75,
                  child: Text(tr.tr('ratingTitle'), style: MgType.title.copyWith(color: MgColors.onDark)),
                ),
              ),
              AnimatedSwitcher(
                duration: MgMotion.of(context, MgMotion.pop),
                child: Text(question,
                    key: ValueKey(question), style: MgType.small.copyWith(color: MgColors.onDarkSecondary)),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        // Pět stejných polí přes celou šířku (min. 44 px na 320 dp).
        Row(children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i < rating,
                label: tr.trArgs('starsCount', {'n': i + 1}),
                excludeSemantics: true,
                child: MgPress(
                  scale: 0.9,
                  onTap: () => onRate(i + 1),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: MgPop(
                        trigger: i < rating ? popTick : 0,
                        child: MgIcon(i < rating ? MgIcons.starFilled : MgIcons.star,
                            size: 40, color: i < rating ? MgColors.star : MgColors.starOffDark),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        Text(tr.tr(rating == 0 ? 'rfTapToRate' : 'rfChangeHint'),
            textAlign: TextAlign.center, style: MgType.meta.copyWith(color: MgColors.onDarkMeta)),
        MgAnimatedSize(
          duration: MgMotion.sheet,
          curve: MgMotion.out,
          alignment: Alignment.topCenter,
          child: rating == 0 ? const SizedBox(width: double.infinity) : _followUp(context, tr),
        ),
      ]),
    );
  }

  Widget _followUp(BuildContext context, AppTranslations tr) {
    Widget tile(int i, Widget leading, String title, String caption, VoidCallback onTap) => MgReveal(
          index: i,
          child: Semantics(
            button: true,
            label: '$title, $caption',
            excludeSemantics: true,
            child: MgPress(
              scale: 0.98,
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 72),
                padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                decoration: BoxDecoration(
                  color: MgColors.white(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MgColors.white(0.12)),
                ),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: MgColors.surface, shape: BoxShape.circle),
                    child: Center(child: leading),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Dlouhé slovo (es „directamente", fr „directement" na
                      // 320 dp s velkým písmem) se zmenší, nikdy nerozdělí.
                      MgWordFit(
                        minScale: 0.75,
                        child: Text(title,
                            style: MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.3, color: MgColors.onDark)),
                      ),
                      const SizedBox(height: 2),
                      Text(caption, style: MgType.meta.copyWith(color: MgColors.onDarkMeta)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.neonText),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr.tr('rfThanksTitle'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
        Text(tr.tr('rfThanksSub'), style: MgType.small.copyWith(color: MgColors.onDarkSecondary)),
        const SizedBox(height: 10),
        tile(1, const GoogleGBadge(), tr.tr('rfGoogleBtn'), tr.tr('rfGoogleCaption'), onGoogle),
        const SizedBox(height: 8),
        tile(2, const MgIcon(MgIcons.edit, size: 20, color: MgColors.link), tr.tr('rfImproveBtn'),
            tr.tr('rfImproveCaption'), onFeedback),
        if (sentThreadId != null) ...[
          const SizedBox(height: 10),
          MgEnter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              decoration: BoxDecoration(
                color: MgColors.neonA(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MgColors.neonA(0.35)),
              ),
              child: Row(children: [
                const MgIcon(MgIcons.checkCircle, size: 20, color: MgColors.neon),
                const SizedBox(width: 8),
                Expanded(child: Text(tr.tr('rfSentLine'), style: MgType.small.copyWith(color: MgColors.onDarkLead))),
                Semantics(
                  button: true,
                  child: MgPress(
                    onTap: onOpenThread,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Center(
                        widthFactor: 1,
                        child: Text(tr.tr('rfOpenThread'),
                            style: MgType.ctaCompact.copyWith(letterSpacing: 0, color: MgColors.neonText)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
