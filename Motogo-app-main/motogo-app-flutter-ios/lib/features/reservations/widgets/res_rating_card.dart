import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/booking_rules.dart' show fmtReleaseDate;
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/moto_fx.dart';
import '../../auth/widgets/toast_helper.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../ride_feedback.dart';
import 'res_rating_widgets.dart';
import 'ride_feedback_sheet.dart';
import '../../../core/friendly_error.dart';
import '../../home/v2/home_review_card_v2.dart' show HomeReviewLightView;

/// Vzhled karty hodnocení: původní tmavá / světlá na Domů (v2).
enum RatingLook { classic, light }

/// Karta „Hodnocení jízdy“ (dokončená rezervace). Hvězdy 1–5 se ukládají do
/// `bookings.rating/rated_at` a lze je kdykoli změnit. Po ohodnocení KAŽDÝ
/// zákazník — bez ohledu na počet hvězd — vidí stejné dvě rovnocenné volby ve
/// stejném pořadí (Google zakazuje „review gating“, zadání majitele 2026-10-15):
///   1. „Napiš nám recenzi“ → Google recenze (`googleReviewUrlProvider`)
///   2. „Napiš nám přímo, co máme zlepšit“ → zpráva týmu do Velína (nezveřejní se)
class ResRatingCard extends ConsumerStatefulWidget {
  final Reservation res;

  /// v2 vzhled (PLAN §2.1, varianta V): `light` = bílá karta na Domů. Stav,
  /// zápis hodnocení i obě volby zůstávají tady — mění se jen vykreslení.
  final RatingLook look;

  /// Jen pro `light`: ✕ „Skrýt" (lokální volba Domů).
  final VoidCallback? onHide;
  const ResRatingCard({super.key, required this.res, this.look = RatingLook.classic, this.onHide});

  @override
  ConsumerState<ResRatingCard> createState() => _ResRatingCardState();
}

class _ResRatingCardState extends ConsumerState<ResRatingCard> {
  /// Optimistické hodnocení, dokud ho nepotvrdí znovu načtená rezervace
  /// (dřív hvězdy po klepnutí na chvíli „skočily“ zpět na starou hodnotu).
  int? _pending;
  int _seq = 0;
  int _popTick = 0;
  String? _sentThreadId;
  Future<void> _chain = Future.value();

  int get _rating => _pending ?? widget.res.rating ?? 0;

  @override
  void didUpdateWidget(covariant ResRatingCard old) {
    super.didUpdateWidget(old);
    if (_pending != null && widget.res.rating == _pending) _pending = null;
  }

  void _rate(int star) {
    if (star == _rating) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pending = star;
      _popTick++;
    });
    final seq = ++_seq;
    // Zápisy jdou za sebou → při rychlém překlikání vyhraje poslední klepnutí.
    _chain = _chain.then((_) async {
      final err = await rateBooking(widget.res.id, star);
      if (!mounted) return;
      final tr = t(context);
      if (err != null) {
        if (seq == _seq) setState(() => _pending = null);
        // Důvod + rada (dřív jen „Hodnocení se nepodařilo uložit").
        showMotoGoToast(context,
            icon: '⚠️',
            title: tr.tr('ratingFailed'),
            message: FriendlyError.of(err).compose(tr, tr.tr('ratingFailed')),
            duration: const Duration(seconds: 6));
        return;
      }
      ref.invalidate(reservationByIdProvider(widget.res.id));
      if (seq == _seq) {
        showMotoGoToast(context, icon: '⭐', title: tr.tr('thanks'),
            message: tr.tr('starsCount').replaceAll('{n}', '$star'));
      }
    });
  }

  Future<void> _openGoogle() async {
    final url = ref.read(googleReviewUrlProvider).valueOrNull ?? kGoogleReviewFallbackUrl;
    final ok = await openGoogleReview(url);
    if (!ok && mounted) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('rfGoogleBtn'), message: t(context).tr('rfLinkFailed'));
    }
  }

  Future<void> _openFeedback() async {
    final id = await showRideFeedbackSheet(context, res: widget.res, rating: _rating);
    if (id == null || !mounted) return;
    setState(() => _sentThreadId = id);
    showMotoGoToast(context, icon: '💬', title: t(context).tr('rfSentTitle'), message: t(context).tr('rfSentLine'));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(googleReviewUrlProvider); // přednačti odkaz na recenze
    final tr = t(context);
    final rating = _rating;
    final ratedAt = widget.res.ratedAt;
    final subtitle = rating == 0
        ? tr.tr('rfHowWasRide')
        : tr.tr('rfYourRating').replaceAll('{n}', '$rating') +
            (ratedAt != null && _pending == null ? ' · ${fmtReleaseDate(ratedAt.toLocal())}' : '');

    if (widget.look == RatingLook.light) {
      return HomeReviewLightView(
        res: widget.res,
        rating: rating,
        question: subtitle,
        popTick: _popTick,
        sentThreadId: _sentThreadId,
        onRate: _rate,
        onGoogle: _openGoogle,
        onFeedback: _openFeedback,
        onOpenThread: () => context.push('/messages/$_sentThreadId'),
        onHide: widget.onHide,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MotoGoColors.dark, MotoGoColors.gradientTop],
        ),
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            RatingHeaderBadge(pulse: rating == 0),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('ratingTitle'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(subtitle, key: ValueKey(subtitle),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.g300)),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => RatingStar(
              index: i,
              selected: i < rating,
              popTick: _popTick,
              onTap: () => _rate(i + 1),
            )),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              rating == 0 ? tr.tr('rfTapToRate') : tr.tr('rfChangeHint'),
              key: ValueKey(rating == 0),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: rating == 0 ? 12 : 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: rating == 0 ? 0.8 : 0.55),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: rating == 0 ? const SizedBox(width: double.infinity) : _followUp(context),
          ),
        ],
      ),
    );
  }

  /// Stejné dvě volby pro 1★ i 5★ — stejný vzhled, stejné pořadí.
  Widget _followUp(BuildContext context) {
    final tr = t(context);
    const delay = Duration(milliseconds: 120);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
        const SizedBox(height: 14),
        StaggeredReveal(
          baseDelay: delay,
          child: Row(children: [
            const Text('🙏', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('rfThanksTitle'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 2),
                Text(tr.tr('rfThanksSub'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        StaggeredReveal(
          index: 1,
          baseDelay: delay,
          child: RatingFollowUpTile(
            leading: const GoogleGBadge(),
            title: tr.tr('rfGoogleBtn'),
            caption: tr.tr('rfGoogleCaption'),
            onTap: _openGoogle,
          ),
        ),
        const SizedBox(height: 8),
        StaggeredReveal(
          index: 2,
          baseDelay: delay,
          child: RatingFollowUpTile(
            leading: const Text('✍️', style: TextStyle(fontSize: 19)),
            title: tr.tr('rfImproveBtn'),
            caption: tr.tr('rfImproveCaption'),
            onTap: _openFeedback,
          ),
        ),
        if (_sentThreadId != null) ...[
          const SizedBox(height: 10),
          StaggeredReveal(
            baseDelay: Duration.zero,
            child: RatingSentNote(
              text: tr.tr('rfSentLine'),
              action: tr.tr('rfOpenThread'),
              onAction: () => context.push('/messages/$_sentThreadId'),
            ),
          ),
        ],
      ],
    );
  }
}
