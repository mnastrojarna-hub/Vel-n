import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../reservations/reservation_models.dart';
import '../../reservations/widgets/res_rating_widgets.dart' show GoogleGBadge;

/// Review cards the customer hid on Home ("Skrýt") — UI-only local pref
/// `mg_v2_home_review_hidden_<bookingId>` (PLAN §2.1, owner decision).
class HomeHiddenReviews extends StateNotifier<Set<String>> {
  static const prefix = 'mg_v2_home_review_hidden_';
  HomeHiddenReviews() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ids = p.getKeys().where((k) => k.startsWith(prefix)).map((k) => k.substring(prefix.length)).toSet();
      if (mounted && ids.isNotEmpty) state = {...state, ...ids};
    } catch (_) {}
  }

  Future<void> hide(String bookingId) async {
    state = {...state, bookingId};
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('$prefix$bookingId', true);
    } catch (_) {}
  }
}

final homeHiddenReviewsProvider =
    StateNotifierProvider<HomeHiddenReviews, Set<String>>((_) => HomeHiddenReviews());

/// Light look of `ResRatingCard` on Home (V21 §5.4 / V22 Main `.rvc`). DUMB:
/// the card's State keeps the optimistic rating, the write chain
/// (`rateBooking`), Google link and the private feedback sheet — this only
/// draws them. Same two options in the same order for 1–5★ (no gating).
class HomeReviewLightView extends StatelessWidget {
  final Reservation res;
  final int rating;
  final String question;
  final int popTick;
  final String? sentThreadId;
  final ValueChanged<int> onRate;
  final VoidCallback onGoogle;
  final VoidCallback onFeedback;
  final VoidCallback onOpenThread;
  final VoidCallback? onHide;

  const HomeReviewLightView({
    super.key,
    required this.res,
    required this.rating,
    required this.question,
    required this.popTick,
    required this.sentThreadId,
    required this.onRate,
    required this.onGoogle,
    required this.onFeedback,
    required this.onOpenThread,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dates = '${tripShortDate(tr, res.startDate)} – ${tripShortDate(tr, res.endDate)}';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.only(right: onHide == null ? 0 : 44),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: MgColors.panel, borderRadius: BorderRadius.circular(12)),
                child: const Center(child: MgIcon(MgIcons.starFilled, size: 20, color: MgColors.star)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    header: true,
                    child: Text(tr.tr('ratingTitle'), style: MgType.title.copyWith(color: MgColors.ink)),
                  ),
                  Text('${res.motoName} · $dates', style: MgType.meta.copyWith(color: MgColors.lead)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: MgMotion.of(context, MgMotion.pop),
            child: Text(question,
                key: ValueKey(question), style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink)),
          ),
          const SizedBox(height: 4),
          Row(children: [
            for (var i = 0; i < 5; i++)
              Semantics(
                button: true,
                selected: i < rating,
                label: tr.trArgs('starsCount', {'n': i + 1}),
                excludeSemantics: true,
                child: MgPress(
                  scale: 0.9,
                  onTap: () => onRate(i + 1),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: MgPop(
                        trigger: i < rating ? popTick : 0,
                        child: MgIcon(i < rating ? MgIcons.starFilled : MgIcons.star,
                            size: 36, color: i < rating ? MgColors.star : MgColors.starOffLight),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
          Text(tr.tr(rating == 0 ? 'rfTapToRate' : 'rfChangeHint'), style: MgType.meta.copyWith(color: MgColors.meta)),
          MgAnimatedSize(
            duration: const Duration(milliseconds: 380),
            curve: MgMotion.out,
            alignment: Alignment.topCenter,
            child: rating == 0 ? const SizedBox(width: double.infinity) : _followUp(context, tr),
          ),
        ]),
        if (onHide != null)
          Positioned(
            top: -6,
            right: -6,
            child: MgV2Back(onTap: onHide, close: true, style: MgBackStyle.light, label: tr.tr('v2HomeReviewHide')),
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
                constraints: const BoxConstraints(minHeight: 84),
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: BoxDecoration(
                  color: MgColors.well,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: MgColors.line),
                ),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: MgColors.surface, shape: BoxShape.circle, boxShadow: MgShadows.icon),
                    child: Center(child: leading),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.3, color: MgColors.ink)),
                      const SizedBox(height: 4),
                      Text(caption, style: MgType.meta.copyWith(color: MgColors.lead)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.link),
                ]),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.only(top: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MgColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: MgIcon(MgIcons.heart, size: 20, color: MgColors.link),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('rfThanksTitle'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                Text(tr.tr('rfThanksSub'), style: MgType.small.copyWith(color: MgColors.lead)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          tile(1, const GoogleGBadge(), tr.tr('rfGoogleBtn'), tr.tr('rfGoogleCaption'), onGoogle),
          const SizedBox(height: 8),
          tile(2, const MgIcon(MgIcons.edit, size: 20, color: MgColors.link), tr.tr('rfImproveBtn'),
              tr.tr('rfImproveCaption'), onFeedback),
          if (sentThreadId != null) ...[
            const SizedBox(height: 10),
            MgEnter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(
                  color: MgColors.tintOk,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: MgColors.tintOkBorder),
                ),
                child: Row(children: [
                  const MgIcon(MgIcons.checkCircle, size: 20, color: MgColors.link),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr.tr('rfSentLine'), style: MgType.small.copyWith(color: MgColors.onTintOk))),
                  Semantics(
                    button: true,
                    child: MgPress(
                      onTap: onOpenThread,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Center(
                          widthFactor: 1,
                          child: Text(tr.tr('rfOpenThread'),
                              style: MgType.ctaCompact.copyWith(letterSpacing: 0, color: MgColors.link)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
