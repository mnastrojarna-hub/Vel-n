import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';

/// v2 look of `ManualCard` (V-branch): the SAME open / search / download
/// closures (`launchUrl` modes + the "not available" snackbar live in the
/// old widget), rendered as a light row with actions.
class ManualCardV2Look extends StatelessWidget {
  final String fileName;
  final bool isPdf;
  final VoidCallback onView;
  final VoidCallback onSearch;
  final VoidCallback onDownload;

  const ManualCardV2Look({
    super.key,
    required this.fileName,
    required this.isPdf,
    required this.onView,
    required this.onSearch,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        MgIconTileLight(MgIcons.doc),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // "Gebruikershandleiding" / "Bedienungsanleitung" at large text:
            // scale a little rather than split the word.
            MgWordFit(minScale: 0.7, child: Text(tr.tr('manualDefaultTitle'), style: MgType.title.copyWith(color: MgColors.ink))),
            if (fileName != tr.tr('manualDefaultTitle'))
              Text(fileName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.small.copyWith(color: MgColors.meta)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      if (isPdf)
        Row(children: [
          Expanded(child: MgBtnGhostLight(label: tr.tr('manualView'), icon: MgIcons.external, onTap: onView, height: 44)),
          const SizedBox(width: 8),
          Expanded(child: MgBtnGhostLight(label: tr.tr('manualSearch'), icon: MgIcons.search, onTap: onSearch, height: 44)),
          const SizedBox(width: 8),
          MgIconButton(
            icon: MgIcons.download,
            onTap: onDownload,
            semanticLabel: tr.tr('v2DetManualDownload'),
            style: MgIconButtonStyle.light,
          ),
        ])
      else
        MgBtnGhostLight(label: tr.tr('manualView'), icon: MgIcons.external, onTap: onView, height: 44),
    ]);
  }
}
