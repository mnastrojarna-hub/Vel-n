import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import 'route_reviews_v2.dart';

/// Place sheet "Recenze · n" (board Zazitky "Detail místa · hodnocení"):
/// title 17/800 + count meta, the shared reviews block in its compact form
/// (plain empty line, hugging "✎ Napsat recenzi"). Old state / callbacks.
class PoiReviewsSectionV2 extends StatelessWidget {
  final RtReviewsData data;
  final VoidCallback onWrite;
  final VoidCallback onDelete;
  const PoiReviewsSectionV2({super.key, required this.data, required this.onWrite, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        header: true,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: tr.tr('routeReviewsHeader'), style: MgType.section.copyWith(color: MgColors.ink)),
          if (!data.loading)
            TextSpan(text: '  ·  ${data.count}', style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
        ])),
      ),
      const SizedBox(height: 10),
      RtReviewsBlockV2(data: data, onWrite: onWrite, onDelete: onDelete, compact: true),
    ]);
  }
}
