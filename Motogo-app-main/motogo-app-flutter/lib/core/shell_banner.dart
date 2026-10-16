import 'package:flutter/material.dart';

import 'theme.dart';

// Přesunuto beze změny z app_shell.dart (dřív `_HeaderBanner`) — sdílí ho
// stará i v2 lišta (PM-2).
/// Scrolling promo banner — matches .header-banner from CSS.
/// Height: 28px. Sits below status bar with bg color extending into safe area.
class ShellHeaderBanner extends StatelessWidget {
  final String text;
  final Color bg;
  final Color color;
  const ShellHeaderBanner({super.key, required this.text, required this.bg, required this.color});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: bg,
      padding: EdgeInsets.only(top: topPad),
      height: MotoGoDimens.bannerHeight + topPad,
      child: _MarqueeText(text: text, color: color),
    );
  }
}

/// Simple scrolling marquee — mirrors banner-scroll CSS @keyframes animation.
/// Duration: 18 seconds per full cycle (matches MotoGoDimens.marqueeSpeed).
class _MarqueeText extends StatefulWidget {
  final String text;
  final Color color;
  const _MarqueeText({required this.text, required this.color});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: MotoGoDimens.marqueeSpeed,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MotoGoDimens.bannerHeight,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final width = MediaQuery.of(context).size.width;
              final offset = _ctrl.value * width * 2;
              return Transform.translate(
                offset: Offset(width - offset, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildText(),
                    const SizedBox(width: 60),
                    _buildText(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildText() {
    return Text(
      widget.text,
      style: TextStyle(
        fontSize: MotoGoDimens.bannerFontSize,
        fontWeight: MotoGoTypo.w700,
        color: widget.color,
        letterSpacing: MotoGoTypo.lsNormal,
      ),
    );
  }
}
