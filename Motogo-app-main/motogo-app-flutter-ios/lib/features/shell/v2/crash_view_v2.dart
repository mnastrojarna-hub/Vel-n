import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/states/mg_support_row.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';

/// Crash fallback in the v2 look (Stavy 19.1 "Tahle obrazovka spadla"):
/// error tone, ✕ (16,55) and primary "Zpět na Domů" → [onHome], secondary
/// "Zpět" → [onBack] — the SAME two actions as the old crash widget (no
/// "Zkusit znovu" / "Nahlásit": the crash is reported automatically), the
/// call line of the support row. Texts come from the caller (no context
/// localization: `ErrorWidget.builder` runs with the last app language).
///
/// The builder may run inside any box (a list row, a sheet): a full page
/// only where there is room for one, otherwise a compact card — never a
/// second layout error inside the error widget.
class CrashViewV2 extends StatelessWidget {
  final String title, why, homeLabel, backLabel;
  final VoidCallback onHome, onBack;
  const CrashViewV2({
    super.key,
    required this.title,
    required this.why,
    required this.homeLabel,
    required this.backLabel,
    required this.onHome,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final roomy = c.hasBoundedHeight && c.hasBoundedWidth && c.maxHeight >= 480 && c.maxWidth >= 280;
      final full = roomy && MediaQuery.maybeOf(context) != null && Directionality.maybeOf(context) != null;
      if (full) {
        return MgStateScreen(
          tone: MgTone.err,
          icon: MgIcons.crash,
          title: title,
          why: why,
          support: false,
          onClose: onHome,
          primary: MgStateAction(homeLabel, onHome),
          secondary: MgStateAction(backLabel, onBack),
          children: const [MgSupportRow(showWrite: false)],
        );
      }
      return _CompactCrash(view: this, bounded: c.hasBoundedHeight);
    });
  }
}

class _CompactCrash extends StatelessWidget {
  final CrashViewV2 view;
  final bool bounded;
  const _CompactCrash({required this.view, required this.bounded});

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: MgColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const MgToneDisc(tone: MgTone.err, size: 40, icon: MgIcons.crash, animate: false),
            const SizedBox(width: 12),
            Expanded(child: Text(view.title, style: MgType.title.copyWith(color: MgColors.ink))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.end, children: [
            MgBtnText(label: view.backLabel, onTap: view.onBack),
            MgBtnText(label: view.homeLabel, onTap: view.onHome),
          ]),
        ]),
      ),
    );
    final directed = Directionality.maybeOf(context) == null
        ? Directionality(textDirection: TextDirection.ltr, child: card)
        : card;
    return bounded ? SingleChildScrollView(child: directed) : directed;
  }
}
