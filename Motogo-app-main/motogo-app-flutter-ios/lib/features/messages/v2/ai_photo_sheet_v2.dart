import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_row.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// v2 look of the AI photo source sheet (camera / gallery). The caller's
/// closures pop the same `ImageSource` values as today.
class AiPhotoSheetV2 extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const AiPhotoSheetV2({super.key, required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgSheetFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgRow(icon: MgIcons.camera, title: tr.tr('aiTakePhoto'), chevron: true, onTap: onCamera),
        const Divider(height: 1, thickness: 1, color: MgColors.line),
        MgRow(icon: MgIcons.image, title: tr.tr('aiPickGallery'), chevron: true, onTap: onGallery),
      ]),
    );
  }
}
