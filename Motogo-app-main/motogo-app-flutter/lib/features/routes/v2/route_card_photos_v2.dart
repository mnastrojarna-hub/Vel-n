import 'package:flutter/widgets.dart';

import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';

import '../poi_categories.dart' show poiCategoryOf;
import '../route_image.dart';
import '../routes_model.dart';

/// One photo of a route card's pager: the cover ([place] null) or a photo
/// of one of the route's points of interest.
class RtCardPhoto {
  final String url;
  final RoutePoi? place;
  const RtCardPhoto(this.url, [this.place]);
}

/// The photos the list card can show WITHOUT another query (5.0.1, owner:
/// "dvě zajímavé fotky z bodů zájmu, každá trochu z jiného soudku"): the
/// cover first, then one photo per point of interest that differs from the
/// cover — the places of different kinds (castle, lookout, water …) first,
/// in the route's own order, then the rest — then the route's other
/// `images[]`. At most [max] photos, every URL once.
List<RtCardPhoto> routeCardPhotos(RouteItem r, {int max = 8}) {
  final out = <RtCardPhoto>[];
  final seen = <String>{};
  void add(String? url, [RoutePoi? p]) {
    if (url == null || url.isEmpty || out.length >= max || !seen.add(url)) return;
    out.add(RtCardPhoto(url, p));
  }

  add(r.cover);
  final withPhoto = [for (final p in r.pois) if ((p.cover ?? '').isNotEmpty && !seen.contains(p.cover)) p];
  // The cover is usually one of the places' photos: its kind counts as
  // shown, so the tiles start with places of OTHER kinds.
  final kinds = <String>{
    for (final p in r.pois)
      if (p.cover != null && p.cover == r.cover) poiCategoryOf(p),
  };
  final later = <RoutePoi>[];
  for (final p in withPhoto) {
    if (kinds.add(poiCategoryOf(p))) {
      add(p.cover, p);
    } else {
      later.add(p);
    }
  }
  for (final p in later) {
    add(p.cover, p);
  }
  for (final u in r.images) {
    add(u);
  }
  return out;
}

/// The two "interesting" photos shown as tiles under the card's media:
/// the first two photos after the cover (different places first).
List<RtCardPhoto> routeCardPicks(List<RtCardPhoto> photos) => photos.skip(1).take(2).toList();

/// Target widths of the card photos (logical px; RouteImage × dpr).
const int kRtCardCoverWidth = 900;
const int kRtCardTileWidth = 320;

/// Warms the photos of the routes NEXT to the one on screen (the list
/// calls it for the neighbours of every card it builds): the cover and the
/// two tiles — never the whole list's photos. [done] dedups per screen.
void precacheRouteCard(BuildContext context, RouteItem r, Set<String> done) {
  if (RtCardImage.debugBuilder != null) return; // render tests: no network
  final photos = routeCardPhotos(r);
  if (photos.isEmpty) return;
  if (done.add('c:${photos.first.url}')) {
    precacheRouteImage(context, photos.first.url, targetWidth: kRtCardCoverWidth);
  }
  for (final p in routeCardPicks(photos)) {
    if (done.add('t:${p.url}')) precacheRouteImage(context, p.url, targetWidth: kRtCardTileWidth);
  }
}

/// A route / place photo of the card. [debugBuilder] lets the render
/// tests draw a stand-in (network images never load there).
class RtCardImage extends StatelessWidget {
  final String url;
  final int targetWidth;
  final Widget Function(BuildContext) fallback;
  const RtCardImage({
    super.key,
    required this.url,
    required this.targetWidth,
    required this.fallback,
  });

  static Widget Function(String url)? debugBuilder;

  @override
  Widget build(BuildContext context) {
    final d = debugBuilder;
    if (d != null) return d(url);
    // Slow network: a dark shimmer in the photo's place; failed: [fallback].
    return RouteImage(url: url, targetWidth: targetWidth, placeholder: (_) => const RtPhotoLoading(), error: fallback);
  }
}

/// The night shimmer of a photo that is still loading.
class RtPhotoLoading extends StatelessWidget {
  const RtPhotoLoading({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: MgColors.panel,
        child: MgSkeleton(dark: true, radius: 0, height: double.infinity, width: double.infinity),
      );
}
