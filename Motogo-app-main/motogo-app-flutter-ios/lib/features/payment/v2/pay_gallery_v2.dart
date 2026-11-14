import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/widgets/net_image.dart';

/// v2 look of the old `MotoGalleryCard` of a new-booking payment (owner
/// 2026-11-07 "jen upgrade vzhledu"): the SAME 200 px inline pager of every
/// photo (swipe; auto-advance every 3 s as before — off under reduced
/// motion, a loop), the swipe-hint chevron, the model and "{branch},
/// {city}" over the photo and the dots under it. Display only.
class PayGalleryV2 extends StatefulWidget {
  final List<String> images;
  final String model;
  final String? branchName;
  final String? branchCity;
  const PayGalleryV2({super.key, required this.images, required this.model, this.branchName, this.branchCity});

  @override
  State<PayGalleryV2> createState() => _PayGalleryV2State();
}

class _PayGalleryV2State extends State<PayGalleryV2> {
  final _ctrl = PageController();
  int _page = 0;
  Timer? _timer;

  List<String> get _imgs => widget.images.isNotEmpty ? widget.images : const [''];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = null;
    if (_imgs.length > 1 && !MgMotion.reduced(context)) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted || !_ctrl.hasClients) return;
        _ctrl.animateToPage((_page + 1) % _imgs.length,
            duration: MgMotion.of(context, MgMotion.sheet), curve: MgMotion.ease);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final imgs = _imgs;
    final branch = [
      if ((widget.branchName ?? '').isNotEmpty) widget.branchName!,
      if ((widget.branchCity ?? '').isNotEmpty) widget.branchCity!,
    ].join(', ');
    Widget fallback() => const ColoredBox(
          color: MgColors.panel,
          child: Center(child: MgIcon(MgIcons.moto, size: 40, color: MgColors.onDarkMeta)),
        );
    return Semantics(
      container: true,
      label: '${widget.model}${branch.isEmpty ? '' : ', $branch'}',
      child: Container(
        key: const ValueKey('pay-v2-gallery'),
        margin: const EdgeInsets.symmetric(horizontal: MgSpace.gutter),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(MgRadius.receipt),
          border: Border.all(color: MgColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 200,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(
                color: MgColors.night,
                child: PageView.builder(
                  controller: _ctrl,
                  itemCount: imgs.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => imgs[i].isEmpty
                      ? fallback()
                      : MgImage(imgs[i], thumbWidth: 800, fit: BoxFit.contain, width: double.infinity, error: fallback()),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MgColors.nightA(0), MgColors.nightA(0), MgColors.nightA(0.85)],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 14,
                end: 48,
                bottom: 12,
                child: IgnorePointer(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.model, maxLines: 2, style: MgType.title.copyWith(color: MgColors.onDark)),
                    if (branch.isNotEmpty)
                      Row(children: [
                        MgIcon(MgIcons.pin, size: 14, color: MgColors.neon),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(branch, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.white(0.85))),
                        ),
                      ]),
                  ]),
                ),
              ),
              if (imgs.length > 1 && _page < imgs.length - 1)
                PositionedDirectional(
                  end: 8,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(color: MgColors.nightA(0.6), shape: BoxShape.circle),
                        child: Center(child: MgIcon(MgIcons.chevronRight, size: 18, color: MgColors.onDark)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          if (imgs.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Semantics(
                label: tr.trArgs('v2DetGalleryAria', {'n': _page + 1, 'total': imgs.length}),
                excludeSemantics: true,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < imgs.length; i++)
                    AnimatedContainer(
                      duration: MgMotion.of(context, MgMotion.color),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i == _page ? MgColors.link : MgColors.line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
