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

/// Photo → video cross-fade (CB-15: an opaque night backdrop, never a light
/// flash). Sits over the photo pager and lets every touch through to it
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
                    : ColoredBox(
                        color: MgColors.night,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          alignment: alignment,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(width: size.width, height: size.height, child: p.view()),
                        ),
                      ),
              );
            },
          ),
        ),
      );
}

/// "▶ Pustit video" on the photo when the video does not start by itself
/// (mobile data, reduced motion, or the customer went through the photos);
/// a ring while it loads after the tap.
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
              child: Container(
                height: 48,
                padding: const EdgeInsets.fromLTRB(8, 0, 18, 0),
                decoration: BoxDecoration(
                  color: MgColors.nightA(0.8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.white(0.3)),
                  boxShadow: MgShadows.photoControl,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 34,
                    height: 34,
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
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark, height: 1)),
                  ),
                ]),
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
