import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_skeleton.dart';

/// v2 chrome of the detail video (CB-23): dark skeleton while loading (no
/// neon spinner), 44 px glass mute disc and a glass "n / m" pill. The
/// controller, autoplay, looping and mute logic stay `MotoVideoPlayer`'s.
/// The disc and the pill are also the detail hero's video controls.
class VideoChromeV2 extends StatelessWidget {
  final bool ready;
  final bool muted;
  final int index;
  final int count;
  final VoidCallback onToggleMute;
  final Widget video;

  const VideoChromeV2({
    super.key,
    required this.ready,
    required this.muted,
    required this.index,
    required this.count,
    required this.onToggleMute,
    required this.video,
  });

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: MgColors.night),
        if (ready) video else const MgSkeleton(dark: true, height: double.infinity, radius: 0),
        Positioned(bottom: 8, right: 8, child: VideoMuteDiscV2(muted: muted, onTap: onToggleMute)),
        if (count > 1) Positioned(bottom: 14, left: 8, child: VideoCountPillV2(index: index, count: count)),
      ]);
}

BoxDecoration _glass() => BoxDecoration(
      color: MgColors.nightA(0.8),
      border: Border.all(color: MgColors.white(0.22)),
      boxShadow: MgShadows.photoControl,
    );

/// 44 px glass mute disc of the bike video (detail player and hero).
class VideoMuteDiscV2 extends StatelessWidget {
  final bool muted;
  final VoidCallback onTap;
  const VideoMuteDiscV2({super.key, required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        toggled: !muted,
        label: t(context).tr(muted ? 'v2UxCbUnmute' : 'v2UxCbMute'),
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          scale: 0.92,
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: _glass().copyWith(shape: BoxShape.circle),
            // No volume glyph in the v2 icon set yet → the platform one.
            child: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 22, color: MgColors.onDark),
          ),
        ),
      );
}

/// Glass "▶ n / m" pill: which of the bike's videos plays.
class VideoCountPillV2 extends StatelessWidget {
  final int index;
  final int count;
  const VideoCountPillV2({super.key, required this.index, required this.count});

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: _glass().copyWith(borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MgIcon(MgIcons.playFilled, size: 14, color: MgColors.neon),
          const SizedBox(width: 6),
          Text('${index + 1} / $count', style: MgType.tab(MgType.meta.copyWith(color: MgColors.onDark, height: 1))),
        ]),
      );
}
