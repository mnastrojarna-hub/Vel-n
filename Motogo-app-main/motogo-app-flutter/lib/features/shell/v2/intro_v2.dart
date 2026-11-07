import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import 'onboarding_parts_v2.dart';

/// First-launch intro in the v2 look (board Prihlaseni "Úvod"): the logo in
/// its neon frame pops in, "MOTO GO 24" + "PŮJČOVNA MOTOREK" rise in, the
/// whole page fades out — 2.4 s like the old overlay, no ride-by bike. A
/// ghost pill "Přeskočit" (44) and a tap anywhere finish at once. [onDone]
/// runs exactly once. Reduced motion: the end frame for 600 ms, then done.
class IntroV2 extends StatefulWidget {
  final VoidCallback onDone;
  const IntroV2({super.key, required this.onDone});

  static const total = Duration(milliseconds: 2400);
  static const reducedHold = Duration(milliseconds: 600);

  @override
  State<IntroV2> createState() => _IntroV2State();
}

class _IntroV2State extends State<IntroV2> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: IntroV2.total);
  Timer? _hold;
  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MgMotion.reduced(context)) {
      _c.value = 0.86;
      _hold = Timer(IntroV2.reducedHold, _finish);
    } else {
      _c.addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      });
      _c.forward();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _hold?.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  double _seg(double from, double to, [Curve curve = Curves.easeOut]) =>
      curve.transform(((_c.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    const logo = OnbLogoTile(size: 104, frame: 6, glow: 0.45);
    final name = Column(mainAxisSize: MainAxisSize.min, children: [
      Text('MOTO GO 24',
          textAlign: TextAlign.center,
          style: MgType.h1.copyWith(fontWeight: FontWeight.w900, letterSpacing: 4, color: MgColors.neon)),
      const SizedBox(height: 6),
      Text(tr.tr('logoSubtitle').toUpperCase(),
          textAlign: TextAlign.center,
          style: MgType.micro.copyWith(letterSpacing: 4, color: MgColors.onDarkMeta)),
    ]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final logoIn = _seg(0.05, 0.40, MgMotion.spring);
          final logoOp = _seg(0.05, 0.22);
          final nameIn = _seg(0.28, 0.50);
          final fadeOut = _seg(0.86, 1.0);
          return Opacity(
            opacity: 1 - fadeOut,
            child: OnbDarkPage(
              child: Stack(children: [
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Opacity(
                      opacity: logoOp,
                      child: Transform.scale(scale: 0.6 + 0.4 * logoIn, child: logo),
                    ),
                    const SizedBox(height: 22),
                    Opacity(
                      opacity: nameIn,
                      child: Transform.translate(offset: Offset(0, 14 * (1 - nameIn)), child: name),
                    ),
                  ]),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottom + 40,
                  child: Center(child: _SkipPill(label: tr.tr('skip'), onTap: _finish)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _SkipPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SkipPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: Container(
            key: const ValueKey('intro-skip'),
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 26),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MgColors.white(0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: MgColors.white(0.22)),
            ),
            child: Text(label, style: MgType.button.copyWith(color: MgColors.onDarkBody)),
          ),
        ),
      );
}
