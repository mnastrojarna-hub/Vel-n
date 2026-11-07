import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../../widgets/net_image.dart';
import '../chrome/mg_status_bar.dart';
import '../gestures/mg_swipe.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import 'mg_back_v2.dart';
import 'mg_skeleton.dart';

/// Opens the v2 full-screen photo viewer over the current page (black, fade
/// 180 ms; design G6 / M1). [overlayBuilder] adds e.g. a © credit (return a
/// `Positioned` / `Align`).
Future<void> showMgPhotoViewer(
  BuildContext context, {
  required List<String> urls,
  int initial = 0,
  ValueChanged<int>? onPage,
  Widget Function(BuildContext, int)? overlayBuilder,
}) {
  final d = MgMotion.of(context, MgMotion.dialog);
  return Navigator.of(context, rootNavigator: true).push<void>(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: d,
    reverseTransitionDuration: d,
    pageBuilder: (ctx, _, __) => MgPhotoViewerView(
      urls: urls,
      initial: initial,
      onPage: onPage,
      overlayBuilder: overlayBuilder,
      onClose: () => Navigator.of(ctx).maybePop(),
    ),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

/// The viewer body (usable inside an existing route): swipe = next photo,
/// pinch 1–4×, double-tap 1× ↔ 2.5× (300 ms), swipe-down closes (100 px /
/// 800 px/s) — page swipe and swipe-down only at scale ≤ 1.01 and with one
/// finger: a second finger = pinch, even with the first one held still.
/// ✕ top-left, counter "n / m" top-right, dots when 2–7 photos.
class MgPhotoViewerView extends StatefulWidget {
  final List<String> urls;
  final int initial;
  final VoidCallback onClose;
  final ValueChanged<int>? onPage;
  final Widget Function(BuildContext, int)? overlayBuilder;

  const MgPhotoViewerView({
    super.key,
    required this.urls,
    this.initial = 0,
    required this.onClose,
    this.onPage,
    this.overlayBuilder,
  });

  @override
  State<MgPhotoViewerView> createState() => _MgPhotoViewerViewState();
}

class _MgPhotoViewerViewState extends State<MgPhotoViewerView> with TickerProviderStateMixin {
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

  /// Fingers on the photo. From the second one on, the swipe-down and the
  /// page drag step aside: their recognizers are removed (= rejected), so
  /// the pinch wins even when one finger stays still (G6); back when all
  /// fingers are up.
  final Set<int> _pointers = {};
  bool get _multi => _pointers.length >= 2;

  void _pointerDown(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (_pointers.length != 2 || !mounted) return;
    setState(() {
      // A swipe-down already under way springs back (never left offset).
      if (_dy == 0) return;
      if (MgMotion.reduced(context)) {
        _dy = 0;
      } else {
        _from = _dy;
        _back.forward(from: 0);
      }
    });
  }

  void _pointerUp(PointerEvent e) {
    if (!_pointers.remove(e.pointer)) return;
    if (_pointers.isEmpty && mounted) setState(() {});
  }

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
    final Matrix4 end;
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      end = Matrix4.identity();
    } else {
      const s = 2.5;
      // x' = s·x − tap·(s − 1): the tapped point stays under the finger.
      end = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1), 0);
    }
    if (MgMotion.reduced(context)) {
      c.value = end;
      return;
    }
    _zoomAnim?.removeListener(_applyZoom);
    _zoomAnim = Matrix4Tween(begin: c.value.clone(), end: end)
        .animate(CurvedAnimation(parent: _zoom, curve: MgMotion.out))
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

  Widget _photo(int i) {
    const placeholder = SizedBox.expand(child: MgSkeleton(dark: true, height: double.infinity, radius: 0));
    final error = Center(child: MgIcon(MgIcons.image, size: 32, color: MgColors.white(0.24)));
    return GestureDetector(
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _tc[i],
        minScale: 1,
        maxScale: 4,
        panEnabled: _zoomed,
        child: SizedBox.expand(
          child: MgImage(
            widget.urls[i],
            thumbWidth: 1600,
            fit: BoxFit.contain,
            fadeIn: MgMotion.of(context, const Duration(milliseconds: 150)),
            placeholder: placeholder,
            error: error,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final reduced = MgMotion.reduced(context);
    final k = reduced ? 0.0 : (_dy.abs() / 400).clamp(0.0, 1.0);
    final canDrag = !_zoomed && !_multi;
    final pager = PageView.builder(
      controller: _pc,
      physics: canDrag ? null : const NeverScrollableScrollPhysics(),
      itemCount: n,
      onPageChanged: (p) {
        if (_page != p) _tc[_page].value = Matrix4.identity();
        setState(() {
          _page = p;
          _zoomed = false;
        });
        widget.onPage?.call(p);
      },
      itemBuilder: (_, i) => _photo(i),
    );
    final tr = t(context);
    return MgStatusBar(
      dark: true,
      child: Material(
        color: MgColors.black(1 - 0.6 * k),
        child: Stack(children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: canDrag ? (_) => _back.stop() : null,
                onVerticalDragUpdate: canDrag ? (d) => setState(() => _dy += d.primaryDelta ?? 0) : null,
                onVerticalDragEnd: canDrag ? _dragEnd : null,
                child: Transform.translate(
                  offset: Offset(0, reduced ? 0 : _dy),
                  child: Transform.scale(scale: 1 - 0.1 * k, child: pager),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: top + 8,
            child: MgV2Back(onTap: widget.onClose, close: true, style: MgBackStyle.photo),
          ),
          if (n > 1)
            Positioned(
              right: 16,
              top: top + 8,
              height: 44,
              child: Center(
                child: Semantics(
                  label: tr.tr('v2UxCorePhotoOf').replaceAll('{n}', '${_page + 1}').replaceAll('{m}', '$n'),
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: MgColors.nightA(0.8), borderRadius: BorderRadius.circular(999)),
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
              bottom: bottom + 20,
              child: ExcludeSemantics(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < n; i++)
                    Container(
                      key: ValueKey('mg-viewer-dot-$i'),
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page ? MgColors.neon : MgColors.white(0.4),
                      ),
                    ),
                ]),
              ),
            ),
          if (widget.overlayBuilder != null) widget.overlayBuilder!(context, _page),
        ]),
      ),
    );
  }
}
