import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_row.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../document_models.dart' show ScanDocType;

/// v2 look of "Co je na fotce?" (gallery upload kind): light sheet, line
/// icons instead of emoji. [onPick] pops the same value as today.
class DocKindSheetV2 extends StatelessWidget {
  final String title;
  final List<String> labels;
  final List<ScanDocType> kinds;
  final ValueChanged<int> onPick;
  const DocKindSheetV2({super.key, required this.title, required this.labels, required this.kinds, required this.onPick});

  static String iconFor(ScanDocType k) => switch (k) {
        ScanDocType.passport => MgIcons.doc,
        ScanDocType.driversLicense => MgIcons.license,
        _ => MgIcons.idCard,
      };

  @override
  Widget build(BuildContext context) => MgSheetFrame(
        title: title,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: MgColors.line),
            MgRow(icon: iconFor(kinds[i]), title: labels[i], chevron: true, onTap: () => onPick(i)),
          ],
        ]),
      );
}
