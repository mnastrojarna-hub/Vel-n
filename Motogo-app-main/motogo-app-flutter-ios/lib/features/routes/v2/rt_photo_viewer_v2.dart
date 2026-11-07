import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/gestures/mg_swipe.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../route_image.dart';

/// Route / place photo viewer in the v2 look — the foundation viewer
/// (`MgPhotoViewerView`: ✕ photo style top-left, "n / m" top-right, dots
/// for 2–7 photos, swipe = next, pinch 1–4×, double-tap 1× ↔ 2.5×,
/// swipe-down closes at scale ≤ 1.01) with the photos drawn by the EXISTING
/// [RouteImage] (Wikimedia needs its User-Agent headers + `?width=`; the
/// shared `MgImage` sends neither → 403 / full-size originals). [credit]
/// = the old © button (opens the existing credit sheet for the shown photo).
Future<void> showRtPhotoViewerV2(BuildContext context,
    {required List<String> urls, int initial = 0, required void Function(BuildContext, int) credit}) {
  final d = MgMotion.of(context, MgMotion.dialog);
  return Navigator.of(context, rootNavigator: true).push<void>(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: d,
    reverseTransitionDuration: d,
    pageBuilder: (ctx, _, __) =>
        RtPhotoViewerV2(urls: urls, initial: initial, credit: credit, onClose: () => Navigator.of(ctx).maybePop()),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class RtPhotoViewerV2 extends StatefulWidget {
  final List<String> urls;
  final int initial;
  final VoidCallback onClose;
  final void Function(BuildContext, int) credit;
  const RtPhotoViewerV2({super.key, required this.urls, this.initial = 0, required this.onClose, required this.credit});

  @override
  State<RtPhotoViewerV2> createState() => _RtPhotoViewerV2State();
}

class _RtPhotoViewerV2State extends State<RtPhotoViewerV2> with TickerProviderStateMixin {
  late int _page = widget.initial.clamp(0, widget.urls.isEmpty ? 0 : widget.urls.length - 1);
  late final PageController _pc = PageController(initialPage: _page);
  late final List<TransformationController> _tc = [
    for (var i = 0; i < widget.urls.length; i++) TransformationController()..addListener(_onTransform),
  ];
  late final AnimationController _zoom = AnimationController(vsync: this, duration: MgMotion.pager);
  late final AnimationController _back = AnimationController(vsync: this, duration: MgMotion.sheet)
    ..addListener(() => setState(() => _dy = _from * (1 - MgMotion.emphasized.transform(_back.value))));
  Animation<Matrix4>? _zoomAnim;
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;
  bool _closing = false;
  double _dy = 0;
  double _from = 0;

  @override
  void dispose() {
    for (final c in _tc) {
      c.dispose();
    }
    _pc.dispose();
    _zoom.dispose();
    _back.dispose();
    super.dispose();
  }

  void _onTransform() {
    if (_tc.isEmpty) return;
    final z = _tc[_page].value.getMaxScaleOnAxis() > 1.01;
    if (z != _zoomed && mounted) setState(() => _zoomed = z);
  }

  void _doubleTap() {
    final c = _tc[_page];
    const s = 2.5;
    final end = c.value.getMaxScaleOnAxis() > 1.01
        ? Matrix4.identity()
        : (Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1), 0));
    if (MgMotion.reduced(context)) {
      c.value = end;
      return;
    }
    _zoomAnim?.removeListener(_applyZoom);
    _zoomAnim = Matrix4Tween(begin: c.value.clone(), end: end).animate(CurvedAnimation(parent: _zoom, curve: MgMotion.out))
      ..addListener(_applyZoom);
    _zoom.forward(from: 0);
  }

  void _applyZoom() {
    final a = _zoomAnim;
    if (a != null) _tc[_page].value = a.value;
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dy.abs() > MgSwipe.dismissDistance || v.abs() > MgSwipe.dismissVelocity) {
      if (_closing) return;
      _closing = true;
      widget.onClose();
      return;
    }
    if (MgMotion.reduced(context) || _dy == 0) {
      setState(() => _dy = 0);
      return;
    }
    _from = _dy;
    _back.forward(from: 0);
  }

  Widget _photo(int i) => GestureDetector(
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: _doubleTap,
        child: InteractiveViewer(
          transformationController: _tc[i],
          minScale: 1,
          maxScale: 4,
          panEnabled: _zoomed,
          child: SizedBox.expand(
            child: RouteImage(
              url: widget.urls[i],
              fit: BoxFit.contain,
              targetWidth: 1600,
              placeholder: (_) => const SizedBox.expand(child: MgSkeleton(dark: true, height: double.infinity, radius: 0)),
              error: (_) => Center(child: MgIcon(MgIcons.image, size: 32, color: MgColors.white(0.24))),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;
    final mq = MediaQuery.paddingOf(context);
    final reduced = MgMotion.reduced(context);
    final k = reduced ? 0.0 : (_dy.abs() / 400).clamp(0.0, 1.0);
    final canDrag = !_zoomed;
    final tr = t(context);
    return MgStatusBar(
      dark: true,
      child: Material(
        color: MgColors.black(1 - 0.6 * k),
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: canDrag ? (_) => _back.stop() : null,
              onVerticalDragUpdate: canDrag ? (d) => setState(() => _dy += d.primaryDelta ?? 0) : null,
              onVerticalDragEnd: canDrag ? _dragEnd : null,
              child: Transform.translate(
                offset: Offset(0, reduced ? 0 : _dy),
                child: Transform.scale(
                  scale: 1 - 0.1 * k,
                  child: PageView.builder(
                    controller: _pc,
                    physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                    itemCount: n,
                    onPageChanged: (p) {
                      if (_page != p) _tc[_page].value = Matrix4.identity();
                      setState(() {
                        _page = p;
                        _zoomed = false;
                      });
                    },
                    itemBuilder: (_, i) => _photo(i),
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: 16, top: mq.top + 8, child: MgV2Back(onTap: widget.onClose, close: true, style: MgBackStyle.photo)),
          if (n > 1)
            Positioned(
              right: 16,
              top: mq.top + 8,
              height: 44,
              child: Center(
                child: Semantics(
                  label: tr.tr('v2UxCorePhotoOf').replaceAll('{n}', '${_page + 1}').replaceAll('{m}', '$n'),
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: MgColors.nightA(0.8),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: MgColors.white(0.25)),
                    ),
                    child: Text('${_page + 1} / $n',
                        style: MgType.tab(MgType.small.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: MgColors.onDark))),
                  ),
                ),
              ),
            ),
          if (n >= 2 && n <= 7)
            Positioned(
              left: 0,
              right: 0,
              bottom: mq.bottom + 20,
              child: ExcludeSemantics(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < n; i++)
                    Container(
                      key: ValueKey('rt-viewer-dot-$i'),
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? MgColors.neon : MgColors.white(0.4)),
                    ),
                ]),
              ),
            ),
          // Photo credit (Wikimedia licence): deliberately quiet, 44 px hit.
          Positioned(
            left: 8,
            bottom: mq.bottom + 8,
            child: Semantics(
              button: true,
              label: tr.tr('poiPhotoCredit'),
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('rt-viewer-credit'),
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.credit(context, _page),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(child: Text('©', style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.white(0.4)))),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
