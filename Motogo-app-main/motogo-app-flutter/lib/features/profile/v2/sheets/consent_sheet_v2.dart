import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';
import '../../../../core/v2/widgets/mg_sheet.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../../core/widgets/state_views.dart';

/// v2 look of the Notifikace / Soukromí a souhlasy sheet (V21 P6a/P6b):
/// light sheet, switches instead of squares, lock banner during a rental,
/// pinned Uložit. All state and actions live in `ConsentSheet` (same load,
/// toggle incl. the locked toast, save, retry).
class ConsentSheetV2View extends StatelessWidget {
  final String title;
  final bool locked;
  final bool loading;
  final Object? loadError;
  final bool saving;
  final String? saveError;

  /// (db column, label, value) in today's order.
  final List<(String, String, bool)> items;
  final ValueChanged<String> onToggle;
  final VoidCallback onSave;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const ConsentSheetV2View({
    super.key,
    required this.title,
    required this.locked,
    required this.loading,
    required this.loadError,
    required this.saving,
    required this.saveError,
    required this.items,
    required this.onToggle,
    required this.onSave,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(color: MgColors.link)),
      );
    } else if (loadError != null) {
      body = MgErrorView(
        compact: true,
        error: loadError,
        what: tr.tr('eoSettingsLoadFail'),
        onRetry: onRetry,
        onBack: onClose,
        backLabel: tr.tr('eoClose'),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1, thickness: 1, color: MgColors.line),
          MgSwitchRow(
            title: items[i].$2,
            value: items[i].$3,
            onChanged: (_) => onToggle(items[i].$1),
          ),
        ],
      ]);
    }
    return MgSheetFrame(
      title: title,
      onClose: onClose,
      footer: loadError != null
          ? null
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (saveError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const MgIcon(MgIcons.xCircle, size: 18, color: MgColors.err),
                    const SizedBox(width: 8),
                    Expanded(child: Text(saveError!, style: MgType.small.copyWith(color: MgColors.err))),
                  ]),
                ),
              MgBtnInk(
                label: tr.tr('save'),
                icon: MgIcons.check,
                neonLabel: true,
                busy: saving,
                onTap: loading || saving ? null : onSave,
              ),
            ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (locked) ...[
          MgTintOk(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const MgIcon(MgIcons.lock, size: 18, color: MgColors.onTintOk),
              const SizedBox(width: 10),
              Expanded(child: Text(tr.tr('consentsLockedHint'), style: MgType.small.copyWith(color: MgColors.onTintOk))),
            ]),
          ),
          const SizedBox(height: 8),
        ],
        body,
      ]),
    );
  }
}
