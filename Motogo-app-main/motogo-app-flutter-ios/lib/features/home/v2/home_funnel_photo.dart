import 'package:flutter/widgets.dart';

/// Smallest / largest Home offer photo (5.0.1 FR-01).
const double kFunnelPhotoMin = 124;
const double kFunnelPhotoMax = 200;

/// First-frame photo height before the room is measured (also the
/// loading skeleton): < 700 dp 150, < 800 dp 190, else 200.
double homeFunnelPhotoGuess(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return h >= 800 ? kFunnelPhotoMax : (h < 700 ? 150.0 : 190.0);
}

/// Sizes the Home offer photo from the room left on the first screen
/// (5.0.1 FR-01): the photo is as big as possible (up to
/// [kFunnelPhotoMax]) while the card's last line (REZERVOVAT, [bottomPad]
/// above the card's bottom edge) still ends [gap] above the bottom of the
/// scroll view (= above the bottom menu). Measured only while the page is
/// at its top — scrolling or the hide-on-scroll menu never resize it.
class FunnelPhotoFit extends StatefulWidget {
  final Widget Function(BuildContext context, double photoH) builder;
  final double bottomPad;
  final double gap;
  const FunnelPhotoFit({super.key, required this.builder, this.bottomPad = 16, this.gap = 8});

  @override
  State<FunnelPhotoFit> createState() => _FunnelPhotoFitState();
}

class _FunnelPhotoFitState extends State<FunnelPhotoFit> {
  final GlobalKey _card = GlobalKey();
  double? _h;
  double _used = 0;

  void _measure() {
    if (!mounted) return;
    final box = _card.currentContext?.findRenderObject();
    final scroll = Scrollable.maybeOf(context);
    final vp = scroll?.context.findRenderObject();
    if (box is! RenderBox || vp is! RenderBox || !box.hasSize || !vp.hasSize || !box.attached) return;
    final pos = scroll!.position;
    if (pos.axis != Axis.vertical || !pos.hasPixels || pos.pixels.abs() > 0.5) return;
    final top = box.localToGlobal(Offset.zero, ancestor: vp).dy;
    // Everything on the card except the photo does not depend on it.
    final rest = box.size.height - _used;
    final room = vp.size.height - widget.gap + widget.bottomPad - top - rest;
    final next = room.clamp(kFunnelPhotoMin, kFunnelPhotoMax).floorToDouble();
    if (_h == null || (next - _h!).abs() >= 1) setState(() => _h = next);
  }

  @override
  Widget build(BuildContext context) {
    final h = _h ?? homeFunnelPhotoGuess(context);
    _used = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return KeyedSubtree(key: _card, child: widget.builder(context, h));
  }
}
