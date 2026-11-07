import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';

/// S2 "Dokonči platbu" body of the Home ticket (board Main S2): the 72 px
/// countdown ring (draining neon arc + mm:ss on the provider's 1-s tick), "Zbývá na zaplacení" + "Motorku
/// ti držíme…", the pay CTA ([cta], the ticket's own) and the text link
/// "Zrušit nedokončenou rezervaci" → [onCancel] (the strip's ✕ flow).
/// Only the existing countdown of [pending] is shown — nothing new is timed.
class TkPayBlock extends StatelessWidget {
  final PendingBooking pending;
  final Widget cta;
  final VoidCallback onCancel;
  const TkPayBlock({super.key, required this.pending, required this.cta, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        container: true,
        label: '${tr.tr('v2UxShPayLeft')} ${pending.timeLabel}',
        excludeSemantics: true,
        child: Row(children: [
          TkCountdownRing(pending: pending),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.tr('v2UxShPayLeft'), style: MgType.title.copyWith(color: MgColors.onDark)),
              const SizedBox(height: 2),
              Text(tr.tr('v2UxShPayHold'), style: MgType.small.copyWith(color: MgColors.onDarkLead)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      cta,
      const SizedBox(height: 4),
      Center(
        child: MgBtnText(
          key: const ValueKey('tk-pay-cancel'),
          label: tr.tr('v2UxShPayCancel'),
          dark: true,
          onTap: onCancel,
        ),
      ),
    ]);
  }
}

/// 72 px ring: white track, neon arc = remaining part of the 30-min window
/// (`PendingBooking.remainingMs`), mm:ss 15/900 tabular in the middle. It
/// follows the provider's existing 1-s tick (no own ticker / loop), so it
/// keeps counting under reduced motion too — it is information.
class TkCountdownRing extends StatelessWidget {
  final PendingBooking pending;
  final double size;
  const TkCountdownRing({super.key, required this.pending, this.size = 72});

  static const _windowMs = 1800000;

  static double fraction(PendingBooking p) => (p.remainingMs / _windowMs).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            key: const ValueKey('tk-countdown-ring'),
            painter: _RingPainter(fraction(pending)),
            child: Center(
              child: Text(
                pending.timeLabel,
                maxLines: 1,
                softWrap: false,
                style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark)),
              ),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double value;
  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = MgColors.white(0.12),
    );
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = MgColors.neon,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}
