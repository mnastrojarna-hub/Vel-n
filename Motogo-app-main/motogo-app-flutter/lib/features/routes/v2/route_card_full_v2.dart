import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_chrome_lift.dart';
import '../../../core/v2/gestures/mg_zone_snap.dart' show MgSwipeAnchor, MgSwipeAnchorListener;
import '../../../core/v2/gestures/mg_one_step.dart' show MgOnePagePhysics;
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../routes_model.dart';
import 'route_card_full_parts_v2.dart';
import 'route_card_photos_v2.dart';
import 'route_card_v2.dart' show RouteDiffPillV2;
import 'rt_v2_text.dart';

/// One route per screen (owner 5.0.1, "jako motorka"): a night card as tall
/// as the folded viewport. The media pager (one page per swipe, "1 / n"):
/// the cover photo with the small road sketch → the LARGE road preview →
/// the photos of the route's places (different kinds first). Under it two
/// place tiles (tap = show that photo), the name, start branch, km · time ·
/// places · difficulty, "Od tebe", ★ (the reviews sheet) and "Detail
/// trasy". Every other tap opens the detail through [onTap] — the old
/// card's open. The route type pill left the list card (stays in the detail).
class RouteCardFullV2 extends StatefulWidget {
  final RouteItem route;
  final RouteBranch? branch;
  final String lang;
  final ({double km, int min})? approach;
  final VoidCallback onTap;
  final VoidCallback onReviews;
  final double height;
  final double topInset;

  /// Slot under the caption shown only with the bars out (the arrow up).
  final double liftExtra;

  /// Always covered at the bottom (the record dock).
  final double bottomReserve;

  const RouteCardFullV2({
    super.key,
    required this.route,
    required this.branch,
    required this.lang,
    required this.approach,
    required this.onTap,
    required this.onReviews,
    this.height = 600,
    this.topInset = 0,
    this.liftExtra = 0,
    this.bottomReserve = 0,
  });

  @override
  State<RouteCardFullV2> createState() => _RouteCardFullV2State();
}

class _RouteCardFullV2State extends State<RouteCardFullV2> {
  final PageController _pc = PageController();
  final MgSwipeAnchor _swipe = MgSwipeAnchor();
  int _page = 0;
  late List<RtCardPhoto> _photos = routeCardPhotos(widget.route);

  @override
  void didUpdateWidget(RouteCardFullV2 old) {
    super.didUpdateWidget(old);
    if (!identical(old.route, widget.route)) _photos = routeCardPhotos(widget.route);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  /// Media pager height (the caption rides over its lower part).
  double get _mediaH => math.max(300.0, widget.height * 0.64);

  /// No photo at all: the LARGE road preview is the card's only page.
  bool get _noPhoto => _photos.isEmpty;

  /// Pages: 0 = cover, 1 = road preview, 2.. = the other photos.
  int get _count => _noPhoto ? 1 : 2 + math.max(0, _photos.length - 1);

  /// Short phone / large text: the caption drops the tiles and the branch
  /// line so the photo stays big (the tiles' photos stay pager pages).
  bool _compact(BuildContext context) => widget.height < 720 || MediaQuery.textScalerOf(context).scale(10) > 11.5;

  void _go(int page) {
    final next = page.clamp(0, _count - 1);
    if (next == _page || !_pc.hasClients) return;
    if (MgMotion.reduced(context)) {
      _pc.jumpToPage(next);
    } else {
      _pc.animateToPage(next, duration: MgMotion.sheet, curve: MgMotion.out);
    }
  }

  Widget _pageAt(int i) {
    final top = widget.topInset;
    if (_noPhoto || i == 1) {
      return GestureDetector(
        onTap: widget.onTap,
        // Down to just above the place tiles (they start ~a quarter above
        // the media's end): the road fills the page, not its top third.
        child: RtSketchPage(
            route: widget.route,
            topInset: top,
            labelTop: _noPhoto ? 20 : 56,
            // No photo (no tiles): down to just above the name (FV-05).
            bottom: _mediaH * (_compact(context) ? 0.42 : (_noPhoto ? 0.1 : 0.22))),
      );
    }
    final k = i == 0 ? 0 : i - 1;
    final img = k < _photos.length
        ? RtCardImage(url: _photos[k].url, targetWidth: kRtCardCoverWidth, fallback: rtCardFallback)
        : rtCardFallback(context);
    return GestureDetector(onTap: widget.onTap, child: img);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final r = widget.route;
    final top = widget.topInset;
    final w = MediaQuery.sizeOf(context).width;
    final mediaH = _mediaH;
    final name = r.nameFor(widget.lang);
    final meta = <(String, String)>[
      if (r.distanceKm != null) (MgIcons.ruler, '${mgNum(r.distanceKm!, tr.lang)} km'),
      if (r.durationMin != null) (MgIcons.clock, rtDur(r.durationMin!)),
      if (r.pois.isNotEmpty) (MgIcons.pin, '${r.pois.length} ${tr.tr('routePoiShort')}'),
    ];
    final a = widget.approach;
    final fromMe = a == null ? null : '${tr.tr('routeFromMe')} ~${a.km.round()} km · ~${rtDur(a.min)}';
    final rating = r.reviewCount > 0 ? '${mgRating(r.reviewAvg ?? 0, tr.lang)} (${r.reviewCount})' : '(0)';
    final compact = _compact(context);
    final picks = compact ? const <RtCardPhoto>[] : routeCardPicks(_photos);
    // The place pill only when no tile below already names that photo.
    final shownPlace =
        _page >= 2 && _page - 1 < _photos.length && _page - 2 >= picks.length ? _photos[_page - 1].place : null;
    final nameStyle =
        MgType.h2.copyWith(color: MgColors.onDark, shadows: [Shadow(color: MgColors.black(0.45), blurRadius: 16)]);
    // Two name lines reserved: the caption grid stays put from card to card.
    final nameMin = MediaQuery.textScalerOf(context).scale(nameStyle.fontSize ?? 24) * (nameStyle.height ?? 1.2) * 2;
    final branch = widget.branch;
    final open = tr.tr('rtListOpen');

    final caption = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (picks.isNotEmpty) ...[
        Row(children: [
          for (var i = 0; i < picks.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: RtPlaceTile(
                key: ValueKey('rt-tile-${r.id}-$i'),
                photo: picks[i],
                on: _page == i + 2,
                onTap: () => _go(i + 2),
              ),
            ),
          ],
          if (picks.length == 1) const Expanded(child: SizedBox()),
        ]),
        const SizedBox(height: 14),
      ],
      Semantics(
        button: true,
        label: [name, if (branch != null) branch.name, ...meta.map((m) => m.$2), if (fromMe != null) fromMe].join(', '),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: nameMin),
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                heightFactor: 1,
                child: Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, style: nameStyle),
              ),
            ),
            if (branch != null && !compact) ...[
              const SizedBox(height: 6),
              Row(children: [
                const MgIcon(MgIcons.flag, size: 15, color: MgColors.neon),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(branch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            RtCardMeta(items: meta),
            // Difficulty in its own fixed row (the caption never jumps).
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 24),
              child: r.difficulty == null
                  ? const SizedBox(height: 24)
                  : Align(
                      alignment: AlignmentDirectional.centerStart, child: RouteDiffPillV2(difficulty: r.difficulty!)),
            ),
            if (fromMe != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const MgIcon(MgIcons.navigate, size: 15, color: MgColors.neonText),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(fromMe,
                      style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText))),
                ),
              ]),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Semantics(
            button: true,
            label: '${tr.tr('routeReviewsHeader')}: $rating',
            excludeSemantics: true,
            child: MgPress(
              onTap: widget.onReviews,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  MgIcon(r.reviewCount > 0 ? MgIcons.starFilled : MgIcons.star, size: 18, color: MgColors.star),
                  const SizedBox(width: 5),
                  Text(rating,
                      style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark))),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: RtOpenButton(label: open, semantic: '$open · $name', onTap: widget.onTap),
          ),
        ),
      ]),
    ]);

    return Semantics(
      container: true,
      label: name,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.height),
        child: ColoredBox(
          color: MgColors.night,
          child: Stack(alignment: AlignmentDirectional.bottomStart, children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: mediaH,
              child: MgSwipeAnchorListener(
                anchor: _swipe,
                axis: Axis.horizontal,
                child: PageView.builder(
                  controller: _pc,
                  itemCount: _count,
                  pageSnapping: false,
                  physics: MgOnePagePhysics(anchor: _swipe),
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => KeyedSubtree(key: ValueKey('rt-page-${r.id}-$i'), child: _pageAt(i)),
                ),
              ),
            ),
            // The photo melts into the night under it (caption over it).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: mediaH + 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        MgColors.nightA(0.5),
                        MgColors.nightA(0),
                        MgColors.nightA(0),
                        MgColors.nightA(0.75),
                        MgColors.night
                      ],
                      stops: const [0, 0.16, 0.45, 0.8, 1],
                    ),
                  ),
                ),
              ),
            ),
            _zone(left: true, label: tr.tr('v2CatPhotoPrev'), mediaH: mediaH),
            _zone(left: false, label: tr.tr('v2CatPhotoNext'), mediaH: mediaH),
            if (!_noPhoto) Positioned(top: top + 12, left: 12, child: RtCountPill(index: _page, total: _count)),
            if (shownPlace != null)
              Positioned(top: top + 50, left: 12, child: RtPlacePill(name: shownPlace.name, maxWidth: w * 0.7)),
            if (_page == 0 && !_noPhoto)
              Positioned(
                  top: top + 12, right: 12, child: RtSmallSketch(route: r, compact: compact, onTap: () => _go(1))),
            MgChromeLift(
              room: widget.height,
              extra: widget.liftExtra,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, top + 120, 16, 14 + widget.bottomReserve),
                child: caption,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _zone({required bool left, required String label, required double mediaH}) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: widget.topInset + 96,
        height: math.max(0.0, mediaH * 0.5 - widget.topInset - 96 + 60),
        width: 64,
        child: Semantics(
          button: true,
          label: label,
          child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _go(_page + (left ? -1 : 1))),
        ),
      );
}
