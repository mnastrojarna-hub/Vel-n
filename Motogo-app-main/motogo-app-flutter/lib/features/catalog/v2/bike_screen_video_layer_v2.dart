import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import 'bike_screen_video_stage_v2.dart';
import 'detail/video_chrome_v2.dart';

/// Photo → video cross-fade (CB-15: never a light flash): the video, fitted
/// whole, fades in over the photo's blurred backdrop while [BikePhotoFade]
/// fades the sharp photo out, so the card keeps its rich band around the
/// 16:9 frame. Sits over the photo pager and lets every touch through to it
/// (tap = open / gallery, swipe = next photo, which goes back to photos).
class BikeVideoLayer extends StatelessWidget {
  final BikeVideoHandle video;
  final Alignment alignment;
  const BikeVideoLayer({super.key, required this.video, this.alignment = Alignment.center});

  static const Duration fade = Duration(milliseconds: 450);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: ListenableBuilder(
            listenable: video,
            builder: (context, _) {
              final p = video.player;
              final on = video.showing && p != null;
              final size = p == null || p.size.isEmpty ? const Size(16, 9) : p.size;
              return AnimatedOpacity(
                key: const ValueKey('bike-video-layer'),
                opacity: on ? 1 : 0,
                duration: MgMotion.of(context, fade),
                curve: MgMotion.out,
                child: p == null
                    ? const SizedBox.expand()
                    : FittedBox(
                        fit: BoxFit.contain,
                        alignment: alignment,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(width: size.width, height: size.height, child: p.view()),
                      ),
              );
            },
          ),
        ),
      );
}

/// The sharp photo (pager) under [BikeVideoLayer]: fades out while the video
/// shows (touches still reach it), back in when the photo returns.
class BikePhotoFade extends StatelessWidget {
  final BikeVideoHandle video;
  final Widget child;
  const BikePhotoFade({super.key, required this.video, required this.child});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: video,
        builder: (context, child) => AnimatedOpacity(
          opacity: video.showing && video.player != null ? 0 : 1,
          duration: MgMotion.of(context, BikeVideoLayer.fade),
          curve: MgMotion.out,
          child: child,
        ),
        child: child,
      );
}

/// "▶ Pustit video" when the video does not start by itself (mobile data,
/// reduced motion, or the customer went through the photos); a ring while it
/// loads after the tap. A compact 40 px pill (48 px touch area) placed in the
/// photo's top-right corner under the branch chip — never on the bike.
class BikeVideoPlayButton extends StatelessWidget {
  final BikeVideoHandle video;
  const BikeVideoPlayButton({super.key, required this.video});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: video,
        builder: (context, _) {
          if (video.showing || (!video.canTap && !video.loading)) return const SizedBox.shrink();
          final label = t(context).tr('bikeVideoPlay');
          final loading = video.loading;
          return Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            onTap: loading ? null : video.tapPlay,
            child: MgPress(
              key: const ValueKey('bike-video-play'),
              scale: 0.95,
              onTap: loading ? null : video.tapPlay,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.fromLTRB(5, 0, 14, 0),
                  decoration: BoxDecoration(
                    color: MgColors.nightA(0.8),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MgColors.white(0.3)),
                    boxShadow: MgShadows.photoControl,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(gradient: MgGradients.neon, shape: BoxShape.circle),
                      child: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: MgColors.onNeon),
                            )
                          : const MgIcon(MgIcons.playFilled, size: 16, color: MgColors.onNeon),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark, height: 1)),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

/// The detail hero's video controls while the video plays: "▶ n / m"
/// (several videos) + the mute disc; [otherwise] (the photo counter) when
/// the photo is shown.
class BikeVideoHeroControls extends StatelessWidget {
  final BikeVideoHandle video;
  final Widget otherwise;
  const BikeVideoHeroControls({super.key, required this.video, required this.otherwise});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: video,
        builder: (context, _) {
          if (!video.showing) return otherwise;
          return Row(key: const ValueKey('bike-video-controls'), mainAxisSize: MainAxisSize.min, children: [
            if (video.count > 1) ...[
              VideoCountPillV2(index: video.index, count: video.count),
              const SizedBox(width: 8),
            ],
            VideoMuteDiscV2(muted: video.muted, onTap: video.toggleMute),
          ]);
        },
      );
}
