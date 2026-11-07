import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../moto_detail_page.dart';

/// v2 view of the detail pager (`MotoDetailScreen`, technique S limited to
/// the overlay controls): the SAME `PageView` (controller, item count,
/// `onPageChanged`, `MotoDetailPage` per bike) — only the back control
/// becomes the photo-style `MgV2Back` (same `backOr(Routes.search)`) and the
/// position counter a glass pill next to it. No new arrows (swipe as today).
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
          Positioned(
            top: top + 18,
            left: 16 + 44 + 10,
            child: Semantics(
              label: tr.trArgs('v2DetPagerAria', {'n': currentIndex + 1, 'total': ids.length}),
              excludeSemantics: true,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: MgColors.nightA(0.8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.white(0.22)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  MgIcon(MgIcons.moto, size: 16, color: MgColors.neon),
                  const SizedBox(width: 6),
                  Text('${currentIndex + 1} / ${ids.length}',
                      style: MgType.tab(MgType.meta.copyWith(color: MgColors.onDark, height: 1))),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
