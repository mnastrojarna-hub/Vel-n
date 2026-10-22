import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_anim_loops.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../../../core/widgets/net_image.dart';
import '../../moto_model.dart';
import '../catalog_text.dart';

/// Photo hero of the v2 detail (board `MotoDetail` `.hero`): the SAME photo
/// pager state the page owns ([pageCtrl] / [imageIndex] / [onImageChanged];
/// a single photo has no PageView so a horizontal swipe still moves the
/// bike pager, as before), tap → the existing `FullscreenGallery`
/// ([onOpenGallery]), segments, availability pill, photo counter, category
/// + licence tags, H1 and the branch line. [onBack] null = the pager
/// overlay draws the back control.
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
  });

  Widget _fallback() => Container(
        color: MgColors.panel,
        alignment: Alignment.center,
        child: MgIcon(MgIcons.moto, size: 64, color: MgColors.onDarkFloor),
      );

  Widget _photo(String url) => MgImage(
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
    Widget photo;
    if (multi) {
      photo = PageView.builder(
        controller: pageCtrl,
        itemCount: images.length,
        onPageChanged: onImageChanged,
        itemBuilder: (_, i) => _photo(images[i]),
      );
    } else if (images.isNotEmpty) {
      photo = _photo(images.first);
    } else {
      photo = _fallback();
    }
    return SizedBox(
      height: height + top,
      child: ColoredBox(
        color: MgColors.night,
        child: Stack(fit: StackFit.expand, children: [
          if (images.isNotEmpty)
            ExcludeSemantics(
              child: Stack(fit: StackFit.expand, children: [
                MgImage(images[idx], thumbWidth: 400, fit: BoxFit.cover, error: _fallback()),
                ColoredBox(color: MgColors.nightA(0.62)),
              ]),
            ),
          Padding(
            padding: EdgeInsets.only(top: top),
            child: Semantics(
              button: onOpenGallery != null,
              label: tr.trArgs('v2DetGalleryAria', {'n': idx + 1, 'total': images.length}),
              child: GestureDetector(onTap: onOpenGallery, child: photo),
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
          Positioned(
            left: 16,
            right: 16,
            bottom: 40,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                if (moto.availableToday == true) _pill(tr.tr('v2CatFreeToday'), live: true),
                const Spacer(),
                if (images.isNotEmpty)
                  Semantics(
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
                  ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (moto.category != null && moto.category!.isNotEmpty)
                  _tag(catCategoryLabel(tr, moto.category!).toUpperCase(), neon: true),
                if (lic.isNotEmpty) _tag(lic),
              ]),
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: Text(moto.model,
                    style: MgType.h1.copyWith(color: MgColors.onDark, shadows: [Shadow(color: MgColors.black(0.45), blurRadius: 18)])),
              ),
              if (branchInfo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  MgIcon(MgIcons.pin, size: 18, color: MgColors.neon),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${tr.tr('detailBranchLabel')}$branchInfo',
                        style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.white(0.94))),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
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

  Widget _tag(String text, {bool neon = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: neon ? MgColors.neon : MgColors.white(0.14),
          borderRadius: BorderRadius.circular(neon ? 6 : 999),
          border: neon ? null : Border.all(color: MgColors.white(0.24)),
        ),
        child: Text(text,
            style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: neon ? MgColors.onNeon : MgColors.onDark, letterSpacing: 0.4)),
      );
}
