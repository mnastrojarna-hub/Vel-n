import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import 'route_detail_parts_v2.dart' show RtSectionV2;
import 'rt_sheet_v2.dart' as sheet;
import 'rt_v2_text.dart';

/// Data of the reviews block — exactly what the old section / sheet state
/// holds (`get_route_reviews` / `get_poi_reviews`), nothing fetched here.
class RtReviewsData {
  final double? avg;
  final int count;
  final Map<String, dynamic>? my;
  final List<Map<String, dynamic>> reviews;
  final bool loading;
  const RtReviewsData({required this.avg, required this.count, required this.my, required this.reviews, required this.loading});
}

/// 5 stars with a fractional fill (board TrasaDetail "4,7 ★★★★☆").
class RtStarsV2 extends StatelessWidget {
  final double value;
  final double size;
  const RtStarsV2(this.value, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            Padding(
              padding: EdgeInsets.only(right: i < 5 ? size * 0.12 : 0),
              child: Stack(children: [
                MgIcon(MgIcons.starFilled, size: size, color: MgColors.starOffLight),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: (value - i + 1).clamp(0.0, 1.0),
                    child: MgIcon(MgIcons.starFilled, size: size, color: MgColors.star),
                  ),
                ),
              ]),
            ),
        ]),
      );
}

/// Summary card: "4,7" 32/900 + stars + "3 recenze".
class RtReviewSummaryV2 extends StatelessWidget {
  final double avg;
  final int count;
  const RtReviewSummaryV2({super.key, required this.avg, required this.count});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final value = mgRating(avg, tr.lang);
    final cnt = rtPlural(tr, 'v2UxRrReviews', count);
    return Semantics(
      label: '$value / 5 · $cnt',
      excludeSemantics: true,
      child: MgCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Text(value, style: MgType.tab(MgType.display.copyWith(color: MgColors.ink))),
          const SizedBox(width: 14),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              RtStarsV2(avg),
              const SizedBox(height: 4),
              Text(cnt, style: MgType.meta.copyWith(color: MgColors.meta)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// One review: stars 14 + author 14/800, text 14/600, photo thumbs 72.
class RtReviewCardV2 extends StatelessWidget {
  final Map<String, dynamic> review;
  const RtReviewCardV2(this.review, {super.key});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final r = review;
    final photos = (r['photos'] as List? ?? const []).map((e) => e.toString()).toList();
    final txt = r['review_text']?.toString() ?? '';
    final rating = r['rating'] is num ? (r['rating'] as num).toDouble() : double.tryParse('${r['rating']}') ?? 0;
    final author = r['is_mine'] == true ? tr.tr('routeReviewYours') : (r['author']?.toString() ?? tr.tr('routeReviewAnonymous'));
    return MgCard(
      margin: const EdgeInsets.only(bottom: MgSpace.s12),
      color: r['status'] == 'hidden' ? MgColors.errBg : MgColors.surface,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RtStarsV2(rating, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(author,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
          ),
        ]),
        if (txt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(txt, style: MgType.body.copyWith(color: MgColors.body2)),
        ],
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => MgPhoto(
                url: photos[i],
                thumbWidth: 200,
                width: 72,
                height: 72,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Summary + cards (or the T3 empty note) + "✎ Napsat recenzi" ghost +
/// "Smazat recenzi" — shared by route detail and the place sheet.
class RtReviewsBlockV2 extends StatelessWidget {
  final RtReviewsData data;
  final VoidCallback onWrite;
  final VoidCallback? onDelete;

  /// false = the pinned sheet footer carries the write button.
  final bool writeButton;

  /// Place sheet (board Zazitky): plain empty line, write button hugs.
  final bool compact;
  const RtReviewsBlockV2({
    super.key,
    required this.data,
    required this.onWrite,
    this.onDelete,
    this.writeButton = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final d = data;
    if (d.loading) {
      return const Column(children: [
        MgSkeletonRow(thumb: 0, lines: 2),
        SizedBox(height: MgSpace.s12),
        MgSkeletonRow(thumb: 0, lines: 3),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (d.count > 0) ...[RtReviewSummaryV2(avg: d.avg ?? 0, count: d.count), const SizedBox(height: MgSpace.s12)],
      if (d.reviews.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: MgSpace.s12),
          child: compact
              ? Text(tr.tr('routeReviewsNone'), style: MgType.body.copyWith(color: MgColors.body2))
              : const _EmptyCard(),
        )
      else
        for (final r in d.reviews) RtReviewCardV2(r),
      if (writeButton)
        Align(
          alignment: Alignment.centerLeft,
          child: MgBtnGhostLight(
            label: d.my != null ? tr.tr('routeReviewEdit') : tr.tr('routeReviewAdd'),
            icon: MgIcons.edit,
            expand: !compact,
            onTap: onWrite,
          ),
        ),
      if (d.my != null && onDelete != null)
        Center(child: MgBtnText(label: tr.tr('routeReviewDelete'), color: MgColors.err, onTap: onDelete)),
    ]);
  }
}

/// Board "Bez recenzí": white card, star disc + "Zatím žádné recenze".
class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) => MgCard(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: MgColors.warnBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const MgIcon(MgIcons.starFilled, size: 24, color: MgColors.star),
          ),
          const SizedBox(height: 12),
          Text(t(context).tr('routeReviewsNone'),
              textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
        ]),
      );
}

/// Route detail "Recenze" section (RtSectionV2 head with the count).
class RouteReviewsSectionV2 extends StatelessWidget {
  final RtReviewsData data;
  final VoidCallback onWrite;
  final VoidCallback onDelete;
  const RouteReviewsSectionV2({super.key, required this.data, required this.onWrite, required this.onDelete});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RtSectionV2(icon: MgIcons.star, title: t(context).tr('routeReviewsHeader'), count: data.loading ? null : data.count),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RtReviewsBlockV2(data: data, onWrite: onWrite, onDelete: onDelete),
        ),
      ]);
}

/// Reviews sheet from the route card ★: light sheet, route name as the
/// title, pinned "Napsat recenzi".
class RouteReviewsSheetV2 extends StatelessWidget {
  final String routeName;
  final RtReviewsData data;
  final VoidCallback onWrite;
  const RouteReviewsSheetV2({super.key, required this.routeName, required this.data, required this.onWrite});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return sheet.RtSheetV2(
      title: routeName,
      footer: MgBtnInk(
        label: data.my != null ? tr.tr('routeReviewEdit') : tr.tr('routeReviewAdd'),
        icon: MgIcons.edit,
        onTap: onWrite,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheet.RtSectionV2(tr.tr('routeReviewsHeader'), top: 4),
        RtReviewsBlockV2(data: data, onWrite: onWrite, writeButton: false),
      ]),
    );
  }
}
