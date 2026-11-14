import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_anim_loops.dart';
import '../../../../core/v2/motion/mg_hero_photo.dart';
import '../../../../core/v2/motion/mg_ken_burns.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/chrome/mg_status_bar.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../../../core/v2/widgets/mg_branch_chip.dart';
import '../../../../core/widgets/net_image.dart';
import '../../moto_model.dart';
import '../bike_screen_video_layer_v2.dart';
import '../bike_screen_video_stage_v2.dart';
import '../catalog_text.dart';

/// Photo hero of the v2 detail (board `MotoDetail` `.hero`): the SAME photo
/// pager state the page owns ([pageCtrl] / [imageIndex] / [onImageChanged];
/// a single photo has no PageView so a horizontal swipe still moves the
/// bike pager, as before), tap → the existing `FullscreenGallery`
/// ([onOpenGallery]), segments, availability pill, photo counter, category
/// + licence tags and H1. [onBack] null = the pager overlay draws the back
/// control. Photo first, then the bike's videos in their order (owner
/// v5.0.1, [BikeVideoStage]: settled ~5 s, Wi-Fi only, else "Pustit video"
/// under the chip; mute disc + "n / m" while it plays, instead of the photo
/// counter); the branch chip sits in the top-right corner. The full branch
/// line ("{name}, {city} · type") is the first section under the hero
/// (`DetailMoreV2` "Pobočka"), so the hero no longer repeats it.
class DetailHeroV2 extends StatelessWidget {
  final Motorcycle moto;
  final List<String> images;
  final String branchInfo;
  final int imageIndex;
  final PageController pageCtrl;
  final ValueChanged<int> onImageChanged;
  final VoidCallback? onOpenGallery;
  final VoidCallback? onBack;
  final double height;

  /// CB-13: dates chosen → the availability pill speaks about THEM:
  /// [rangeFree] true = loaded and free ("● Volná v tvém termínu", the
  /// detail's one live indicator); false / null (busy / still loading) =
  /// the old "Dnes volná" (when free today), as without dates.
  final bool hasDates;
  final bool? rangeFree;

  const DetailHeroV2({
    super.key,
    required this.moto,
    required this.images,
    required this.branchInfo,
    required this.imageIndex,
    required this.pageCtrl,
    required this.onImageChanged,
    required this.onOpenGallery,
    required this.onBack,
    required this.height,
    this.hasDates = false,
    this.rangeFree,
  });

  Widget _fallback() => Container(
        color: MgColors.panel,
        alignment: Alignment.center,
        child: MgIcon(MgIcons.moto, size: 64, color: MgColors.onDarkFloor),
      );

  /// CB-14: the first photo is the landing spot of the card photo's flight.
  Widget _photo(String url, int i) => MgHeroPhoto(
        tag: mgHeroTagMoto(moto.id),
        enabled: i == 0,
        child: _img(url),
      );

  Widget _img(String url) => MgImage(
        url,
        thumbWidth: 1000,
        // contain = celá fotka viditelná (jako ve Velíně) — jako dřív.
        fit: BoxFit.contain,
        width: double.infinity,
        placeholder: const SizedBox.expand(),
        error: _fallback(),
      );

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    final multi = images.length > 1;
    final idx = images.isEmpty ? 0 : imageIndex.clamp(0, images.length - 1);
    final lic = catLicenseLabel(tr, moto);
    final branchChip = mgBikeBranchChipLabel(tr, moto);
    Widget photo;
    if (multi) {
      photo = PageView.builder(
        controller: pageCtrl,
        itemCount: images.length,
        onPageChanged: onImageChanged,
        itemBuilder: (_, i) => _photo(images[i], i),
      );
    } else if (images.isNotEmpty) {
      photo = _photo(images.first, 0);
    } else {
      photo = _fallback();
    }
    return BikeVideoStage(
      videos: moto.videos,
      mode: BikeVideoMode.hero,
      minVisible: 0.75,
      builder: (context, video) => _build(context, photo, video, branchChip, lic, idx, multi, top),
    );
  }

  Widget _build(BuildContext context, Widget photo, BikeVideoHandle video, String? branchChip, String lic, int idx,
      bool multi, double top) {
    final tr = t(context);
    final counter = images.isEmpty
        ? const SizedBox.shrink()
        : Semantics(
            button: true,
            label: tr.trArgs('v2DetGalleryAria', {'n': idx + 1, 'total': images.length}),
            excludeSemantics: true,
            onTap: onOpenGallery,
            child: MgPress(
              onTap: onOpenGallery,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  child: _pill('${idx + 1} / ${images.length}', icon: MgIcons.camera),
                ),
              ),
            ),
          );
    // Room left of the chip: the back disc (+ the pager's "‹ n / m ›").
    final leftControls = onBack == null ? 16 + 44 + 8 + 124 : 16 + 44;
    return MgStatusBar(
      dark: true,
      extendAbove: MgStatusBar.bounce,
      child: SizedBox(
        height: height + top,
        child: ColoredBox(
          color: MgColors.night,
          child: Stack(fit: StackFit.expand, children: [
            // CB-15: dark placeholder (never a light flash) and a 180 ms
            // cross-fade when the photo page changes (instant when reduced).
            if (images.isNotEmpty)
              ExcludeSemantics(
                child: Stack(fit: StackFit.expand, children: [
                  AnimatedSwitcher(
                    duration: MgMotion.of(context, MgMotion.color),
                    child: KeyedSubtree(
                      key: ValueKey(idx),
                      child: MgImage(images[idx],
                          thumbWidth: 400,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: const ColoredBox(color: MgColors.panel),
                          error: _fallback()),
                    ),
                  ),
                  ColoredBox(color: MgColors.nightA(0.62)),
                ]),
              ),
            Padding(
              padding: EdgeInsets.only(top: top),
              child: Semantics(
                button: onOpenGallery != null,
                label: tr.trArgs('v2DetGalleryAria', {'n': idx + 1, 'total': images.length}),
                // CB-28: Ken Burns 8 s one-shot (once per session, off when reduced).
                child: GestureDetector(
                  onTap: onOpenGallery,
                  child: Stack(fit: StackFit.expand, children: [
                    if (moto.videos.isEmpty)
                      MgKenBurns(sessionKey: 'detail-hero-${moto.id}', child: photo)
                    else
                      BikePhotoFade(video: video, child: MgKenBurns(sessionKey: 'detail-hero-${moto.id}', child: photo)),
                    if (moto.videos.isNotEmpty) BikeVideoLayer(video: video),
                  ]),
                ),
              ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [MgColors.nightA(0.66), MgColors.nightA(0), MgColors.nightA(0), MgColors.nightA(0.72), MgColors.nightA(0.97)],
                    stops: const [0, 0.26, 0.48, 0.74, 1],
                  ),
                ),
              ),
            ),
            if (multi)
              Positioned(
                top: top + 4,
                left: 16,
                right: 16,
                child: ExcludeSemantics(
                  child: Row(children: [
                    for (var i = 0; i < images.length; i++)
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i == idx ? MgColors.onDark : MgColors.white(0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            if (onBack != null)
              Positioned(top: top + 12, left: 16, child: MgV2Back(onTap: onBack, style: MgBackStyle.photo)),
            // Where the bike is (owner v5.0.1): the neon chip, top right,
            // level with the back / pager controls.
            if (branchChip != null)
              Positioned(
                top: top + 21,
                right: 16,
                child: IgnorePointer(
                  child: MgBranchChip(
                    label: branchChip,
                    shortLabel: mgBranchShortName(moto.branchName, moto.branchCity),
                    maxWidth: mgBranchChipMaxWidth(MediaQuery.sizeOf(context).width, leftPill: leftControls - 8.0),
                  ),
                ),
              ),
            // Off the bike: top right, under the chip.
            if (moto.videos.isNotEmpty)
              Positioned(
                top: top + (branchChip == null ? 17 : 55),
                right: 16,
                child: BikeVideoPlayButton(video: video),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 40,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  if (hasDates && rangeFree == true)
                    _pill(tr.tr('v2CatFreeInRange'), live: true)
                  // Otherwise "Dnes volná" as the old hero always showed it
                  // (no dates, availability still loading, or not free in range).
                  else if (moto.availableToday == true)
                    _pill(tr.tr('v2CatFreeToday'), live: true),
                  const Spacer(),
                  BikeVideoHeroControls(video: video, otherwise: counter),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (moto.category != null && moto.category!.isNotEmpty)
                    _tag(catCategoryLabel(tr, moto.category!).toUpperCase(), neon: true),
                  // J4: a licence that does not cover the bike shows here
                  // already (red + "tvůj ŘP nestačí"), not only in the form.
                  if (lic.isNotEmpty)
                    Consumer(
                      builder: (context, ref, _) => catLicenceFails(ref, moto)
                          ? _tag('$lic · ${tr.tr('coLicNotEnough')}', bad: true)
                          : _tag(lic),
                    ),
                ]),
                const SizedBox(height: 8),
                Semantics(
                  header: true,
                  child: Text(moto.model,
                      style: MgType.h1.copyWith(color: MgColors.onDark, shadows: [Shadow(color: MgColors.black(0.45), blurRadius: 18)])),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pill(String text, {bool live = false, String? icon}) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: MgColors.nightA(0.8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.white(0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (live) RepaintBoundary(child: MgPing(size: 8, color: MgColors.neon)),
          if (icon != null) MgIcon(icon, size: 16, color: MgColors.onDark),
          const SizedBox(width: 6),
          Text(text, style: MgType.tab(MgType.meta.copyWith(color: MgColors.onDark, height: 1))),
        ]),
      );

  Widget _tag(String text, {bool neon = false, bool bad = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          // Solid dark ink (as the list card's tag): readable on a white tank.
          color: bad ? MgColors.err : (neon ? MgColors.neon : MgColors.nightA(0.85)),
          borderRadius: BorderRadius.circular(neon ? 6 : 999),
          border: neon ? null : Border.all(color: MgColors.white(0.24)),
        ),
        child: Text(text,
            style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: neon ? MgColors.onNeon : MgColors.onDark, letterSpacing: 0.4)),
      );
}
