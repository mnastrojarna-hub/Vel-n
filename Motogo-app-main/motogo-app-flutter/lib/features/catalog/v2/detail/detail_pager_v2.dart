import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_hide_on_scroll.dart';
import '../../../../core/v2/gestures/mg_one_step.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/motion/mg_sticky_slide.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../moto_detail_page.dart';
import 'moto_detail_view_v2.dart' show detailHeroHeight;
import '../bike_screen_list_v2.dart' show catalogShownMotoProvider;

/// v2 view of the detail pager (`MotoDetailScreen`, technique S limited to
/// the overlay controls): the SAME `PageView` (controller, item count,
/// `onPageChanged`, `MotoDetailPage` per bike) — only the back control
/// becomes the photo-style `MgV2Back` (same `backOr(Routes.search)`) and the
/// position counter a glass pill next to it with ‹ › (CB-12, tap = swipe).
/// Hide-on-scroll (owner 2026-11-08): both controls fold up while the bike
/// is scrolled down and return on scroll up; a new page starts with them
/// shown. The bike on screen is published ([catalogShownMotoProvider]) so
/// the list it came from returns scrolled to it.
class MotoDetailPagerV2View extends ConsumerStatefulWidget {
  final bool hasPager;
  final PageController controller;
  final List<String> ids;
  final int itemCount;
  final String motoId;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onBack;

  const MotoDetailPagerV2View({
    super.key,
    required this.hasPager,
    required this.controller,
    required this.ids,
    required this.itemCount,
    required this.motoId,
    required this.currentIndex,
    required this.onPageChanged,
    required this.onBack,
  });

  @override
  ConsumerState<MotoDetailPagerV2View> createState() => _MotoDetailPagerV2ViewState();
}

class _MotoDetailPagerV2ViewState extends ConsumerState<MotoDetailPagerV2View> {
  /// One bike per swipe, however fast (owner v5.0.1).
  final MgSwipeAnchor _swipe = MgSwipeAnchor();

  @override
  void initState() {
    super.initState();
    final w = widget;
    final id = w.hasPager && w.ids.isNotEmpty ? w.ids[w.currentIndex.clamp(0, w.ids.length - 1)] : w.motoId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish(id));
  }

  void _publish(String id) {
    if (!mounted) return;
    final n = ref.read(catalogShownMotoProvider.notifier);
    if (n.state != id) n.state = id;
  }

  /// P2-10: the bike is scrolled past its photo — the controls get a solid
  /// band so they never sit on text.
  bool _scrolled = false;

  bool _onScroll(ScrollNotification n, double threshold) {
    if (n.metrics.axis != Axis.vertical || n.depth > 1) return false;
    final v = n.metrics.pixels > threshold;
    if (v != _scrolled) setState(() => _scrolled = v);
    return false;
  }

  /// The shared `onPageChanged` + bars back + the bike on screen.
  void _changed(int i) {
    if (_scrolled) setState(() => _scrolled = false);
    MgBarsScope.read(context)?.show();
    widget.onPageChanged(i);
    if (widget.ids.isNotEmpty) _publish(widget.ids[i % widget.ids.length]);
  }

  void _go(BuildContext context, int dir) {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    if (MgMotion.reduced(context)) {
      controller.jumpToPage((controller.page ?? 0).round() + dir);
    } else if (dir < 0) {
      controller.previousPage(duration: MgMotion.pager, curve: MgMotion.out);
    } else {
      controller.nextPage(duration: MgMotion.pager, curve: MgMotion.out);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final ids = w.ids;
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    // Only the two controls listen to the bars (never the pages).
    Widget folding(Widget child) => Builder(
          builder: (context) => MgStickySlide(visible: !MgBarsScope.hiddenOf(context), from: AxisDirection.up, child: child),
        );
    final bandH = top + 12 + 46 + 8;
    return Scaffold(
      backgroundColor: MgColors.surface,
      body: Stack(children: [
        if (w.hasPager)
          NotificationListener<ScrollNotification>(
            onNotification: (n) => _onScroll(n, detailHeroHeight(context) - bandH - 24),
            child: MgSwipeAnchorListener(
              anchor: _swipe,
              axis: Axis.horizontal,
              child: PageView.builder(
                controller: w.controller,
                itemCount: w.itemCount,
                pageSnapping: false,
                physics: MgOnePagePhysics(anchor: _swipe),
                onPageChanged: _changed,
                itemBuilder: (_, i) {
                  final idx = i % ids.length;
                  return MotoDetailPage(key: ValueKey(ids[idx]), motoId: ids[idx]);
                },
              ),
            ),
          )
        else
          MotoDetailPage(motoId: w.motoId, showBackButton: true),
        if (w.hasPager) ...[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: folding(IgnorePointer(
              ignoring: !_scrolled,
              child: AnimatedOpacity(
                key: const ValueKey('detail-pager-band'),
                opacity: _scrolled ? 1 : 0,
                duration: MgMotion.of(context, MgMotion.color),
                child: Container(
                  height: bandH,
                  decoration: const BoxDecoration(color: MgColors.surface, boxShadow: MgShadows.card),
                ),
              ),
            )),
          ),
          Positioned(
            top: top + 12,
            left: 16,
            child: folding(MgV2Back(onTap: w.onBack, style: MgBackStyle.photo)),
          ),
          // CB-12: "‹ n / m ›" — the chevrons are the tap twin of the
          // existing swipe (same controller, 300 ms out; a jump when the
          // system asks for reduced motion).
          Positioned(
            top: top + 12,
            left: 16 + 44 + 8,
            child: folding(Semantics(
              label: tr.trArgs('v2DetPagerAria', {'n': w.currentIndex + 1, 'total': ids.length}),
              child: Container(
                height: 46, // 44 hit inside the 1 px ring
                decoration: BoxDecoration(
                  color: MgColors.nightA(0.8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.white(0.22)),
                  boxShadow: MgShadows.photoControl,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Chev(left: true, label: tr.tr('v2UxCbPrevBike'), onTap: () => _go(context, -1)),
                  ExcludeSemantics(
                    child: Text('${w.currentIndex + 1} / ${ids.length}',
                        style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark, height: 1))),
                  ),
                  _Chev(left: false, label: tr.tr('v2UxCbNextBike'), onTap: () => _go(context, 1)),
                ]),
              ),
            )),
          ),
        ],
      ]),
    );
  }
}

/// 44 px chevron hit area inside the pager pill.
class _Chev extends StatelessWidget {
  final bool left;
  final String label;
  final VoidCallback onTap;
  const _Chev({required this.left, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          scale: 0.92,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: MgIcon(left ? MgIcons.chevronLeft : MgIcons.chevronRight, size: 18, color: MgColors.onDark)),
          ),
        ),
      );
}
