import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../moto_detail_page.dart';

/// v2 view of the detail pager (`MotoDetailScreen`, technique S limited to
/// the overlay controls): the SAME `PageView` (controller, item count,
/// `onPageChanged`, `MotoDetailPage` per bike) — only the back control
/// becomes the photo-style `MgV2Back` (same `backOr(Routes.search)`) and the
/// position counter a glass pill next to it with ‹ › (CB-12, tap = swipe).
class MotoDetailPagerV2View extends StatelessWidget {
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

  void _go(BuildContext context, int dir) {
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
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: MgColors.surface,
      body: Stack(children: [
        if (hasPager)
          PageView.builder(
            controller: controller,
            itemCount: itemCount,
            onPageChanged: onPageChanged,
            itemBuilder: (_, i) {
              final idx = i % ids.length;
              return MotoDetailPage(key: ValueKey(ids[idx]), motoId: ids[idx]);
            },
          )
        else
          MotoDetailPage(motoId: motoId, showBackButton: true),
        if (hasPager) ...[
          Positioned(top: top + 12, left: 16, child: MgV2Back(onTap: onBack, style: MgBackStyle.photo)),
          // CB-12: "‹ n / m ›" — the chevrons are the tap twin of the
          // existing swipe (same controller, 300 ms out; a jump when the
          // system asks for reduced motion).
          Positioned(
            top: top + 12,
            left: 16 + 44 + 8,
            child: Semantics(
              label: tr.trArgs('v2DetPagerAria', {'n': currentIndex + 1, 'total': ids.length}),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: MgColors.nightA(0.8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.white(0.22)),
                  boxShadow: MgShadows.photoControl,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Chev(left: true, label: tr.tr('v2UxCbPrevBike'), onTap: () => _go(context, -1)),
                  ExcludeSemantics(
                    child: Text('${currentIndex + 1} / ${ids.length}',
                        style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark, height: 1))),
                  ),
                  _Chev(left: false, label: tr.tr('v2UxCbNextBike'), onTap: () => _go(context, 1)),
                ]),
              ),
            ),
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
