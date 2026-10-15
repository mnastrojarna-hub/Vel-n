import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/moto_fx.dart';

/// Stavební prvky karty hodnocení jízdy (`res_rating_card.dart`).
const Color kRatingStarColor = Color(0xFFF59E0B);
const Color _starOff = Color(0x40FFFFFF);

/// Hvězda s pružným „popem“: po každém klepnutí ([popTick] +1) vybuchnou
/// vybrané hvězdy postupně zleva (vlna), nevybrané jen ztlumí barvu.
class RatingStar extends StatefulWidget {
  final int index;
  final bool selected;
  final int popTick;
  final VoidCallback onTap;
  const RatingStar({super.key, required this.index, required this.selected, required this.popTick, required this.onTap});

  @override
  State<RatingStar> createState() => _RatingStarState();
}

class _RatingStarState extends State<RatingStar> with SingleTickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.42).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.42, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 70),
  ]).animate(_pop);
  Timer? _delay;

  @override
  void didUpdateWidget(covariant RatingStar old) {
    super.didUpdateWidget(old);
    if (widget.popTick != old.popTick && widget.selected) {
      _delay?.cancel();
      _delay = Timer(Duration(milliseconds: 60 * widget.index), () {
        if (mounted) _pop.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final star = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.selected ? kRatingStarColor : _starOff),
      duration: const Duration(milliseconds: 220),
      builder: (context, color, _) => Icon(
        Icons.star_rounded,
        size: 40,
        color: color,
        shadows: widget.selected
            ? [Shadow(color: kRatingStarColor.withValues(alpha: 0.65), blurRadius: 16)]
            : null,
      ),
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '★ ${widget.index + 1}/5',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: AnimatedBuilder(
            animation: _scale,
            builder: (context, child) => Transform.scale(
              scale: _scale.value * (widget.selected ? 1.1 : 1.0),
              child: child,
            ),
            child: star,
          ),
        ),
      ),
    );
  }
}

/// Jedna z voleb po ohodnocení. Obě volby používají TENTO widget → stejná
/// velikost, barva i důraz (žádné zvýhodnění Googlu ani zprávy).
class RatingFollowUpTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String caption;
  final VoidCallback onTap;
  const RatingFollowUpTile({super.key, required this.leading, required this.title, required this.caption, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.96,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 66),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(MotoGoRadius.xxl),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: leading,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25)),
              const SizedBox(height: 2),
              Text(caption,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.6))),
            ]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: MotoGoColors.green, size: 22),
        ]),
      ),
    );
  }
}

/// Písmeno „G“ v barvách Googlu (bez loga — jen rozpoznatelný odkaz).
class GoogleGBadge extends StatelessWidget {
  const GoogleGBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const SweepGradient(
        colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4)],
      ).createShader(r),
      child: const Text('G', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
    );
  }
}

/// Potvrzení odeslané zprávy + odkaz do konverzace (odpověď obsluhy).
class RatingSentNote extends StatelessWidget {
  final String text;
  final String action;
  final VoidCallback onAction;
  const RatingSentNote({super.key, required this.text, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: MotoGoColors.green.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(MotoGoRadius.xl),
        border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: MotoGoColors.green, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, height: 1.3)),
        ),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(foregroundColor: MotoGoColors.green, padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text(action, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}
