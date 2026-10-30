import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../../core/v2/chrome/mg_dock.dart';
import '../../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../../moto_model.dart';
import '../catalog_text.dart';

/// The calculator's REZERVOVAT while it is enabled AND scrolled off-screen
/// (DESIGN_V22 §2.4 Kalkulačka "Sticky .kst", §7.6 #1; board: the dock
/// appears only when the total block's CTA is under the edge). [onBook] is
/// the very handler `CalcTotalV2` got (`startBookingFromSelection` with the
/// same bike and dates); equality ignores it (same values = same action).
@immutable
class CalcStickyData {
  final Motorcycle moto;
  final DateTime start;
  final DateTime end;
  final double total;
  final VoidCallback onBook;

  const CalcStickyData({
    required this.moto,
    required this.start,
    required this.end,
    required this.total,
    required this.onBook,
  });

  @override
  bool operator ==(Object other) =>
      other is CalcStickyData &&
      other.moto.id == moto.id &&
      other.start == start &&
      other.end == end &&
      other.total == total;

  @override
  int get hashCode => Object.hash(moto.id, start, end, total);
}

/// Published by `CalcBodyV2` (null = no dock); `MotorkyScreenV2` mounts
/// [CalcStickyV2] from it in calculator mode only.
final calcStickyProvider = StateProvider<CalcStickyData?>((_) => null);

/// Tracks whether the total block's CTA ([stickyCtaKey]) is fully inside
/// the enclosing scroll view and publishes [calcStickyProvider]. Checks run
/// after the frame (never while the tree builds / lays out).
mixin CalcStickyTracker<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final GlobalKey stickyCtaKey = GlobalKey();
  ScrollableState? _scrollable;
  CalcStickyData? _want;
  bool _queued = false;
  StateController<CalcStickyData?>? _sticky;

  /// Call from `didChangeDependencies`.
  void stickyAttach() {
    _sticky ??= ref.read(calcStickyProvider.notifier);
    final s = Scrollable.maybeOf(context);
    if (s == _scrollable) return;
    _scrollable?.position.removeListener(_queue);
    _scrollable = s;
    s?.position.addListener(_queue);
  }

  /// The enabled CTA of this build (null = no total / disabled).
  void stickyWant(CalcStickyData? d) {
    _want = d;
    _queue();
  }

  void _queue() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      _check();
    });
  }

  void _check() {
    if (!mounted) return;
    CalcStickyData? show;
    final want = _want;
    final cta = stickyCtaKey.currentContext?.findRenderObject();
    final view = _scrollable?.context.findRenderObject();
    if (want != null && cta is RenderBox && cta.attached && cta.hasSize && view is RenderBox && view.hasSize) {
      final top = cta.localToGlobal(Offset.zero).dy;
      final vt = view.localToGlobal(Offset.zero).dy;
      final inside = top >= vt - 0.5 && top + cta.size.height <= vt + view.size.height + 0.5;
      if (!inside) show = want;
    }
    final n = _sticky;
    if (n != null && n.mounted && n.state != show) n.state = show;
  }

  void stickyDetach() {
    _scrollable?.position.removeListener(_queue);
    _scrollable = null;
    final n = _sticky;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (n != null && n.mounted) n.state = null;
    });
  }
}

/// The dock itself: dates · days (as the detail dock), rank CTA "REZERVOVAT · price" (the
/// floating AI button stays and sits above the dock — on Motorky it is
/// never hidden, a docked disc would double it). Slides in (300 ms;
/// reduced motion = instant).
class CalcStickyV2 extends StatelessWidget {
  final CalcStickyData data;
  const CalcStickyV2({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final inShell = MgChromeScope.maybeOf(context)?.navVisible ?? false;
    final days = catDayCount(data.start, data.end);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: MgMotion.of(context, MgMotion.sticky),
      curve: MgMotion.out,
      builder: (_, v, child) => FractionalTranslation(translation: Offset(0, v), child: child),
      child: MgDock(
        safeArea: !inShell,
        contextLine: Text(
          '${catRange(tr, data.start, data.end)} · ${catDays(tr, days)}',
          maxLines: 2,
        ),
        child: MgFabAvoid(
          child: MgCta(
            label: tr.tr('v2CatCtaBook'),
            price: catMoney(data.total),
            onTap: data.onBook,
            size: MgCtaSize.lg60,
            loop: true,
          ),
        ),
      ),
    );
  }
}
