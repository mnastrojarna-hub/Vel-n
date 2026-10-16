import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_buttons.dart';
import '../widgets/mg_toast.dart';

/// Collapsed "Technické detaily ▾" with the raw technical text (code,
/// reference, time) + "Zkopírovat". Raw server / exception text NEVER goes
/// into a state body — only here, and only when the caller has one.
class MgTechDetails extends StatefulWidget {
  final String details;
  final bool dark;
  const MgTechDetails({super.key, required this.details, this.dark = false});

  @override
  State<MgTechDetails> createState() => _MgTechDetailsState();
}

class _MgTechDetailsState extends State<MgTechDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final fg = widget.dark ? MgColors.onDarkLead : MgColors.lead;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        expanded: _open,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr.tr('v2StTech'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: MgMotion.of(context, MgMotion.color),
                child: MgIcon(MgIcons.chevronDown, size: 16, color: fg),
              ),
            ]),
          ),
        ),
      ),
      AnimatedSize(
        duration: MgMotion.of(context, MgMotion.sheet),
        alignment: Alignment.topLeft,
        child: !_open
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
                decoration: BoxDecoration(
                  color: widget.dark ? MgColors.white(0.06) : MgColors.well,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.dark ? MgColors.white(0.10) : MgColors.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText(widget.details,
                      style: MgType.small.copyWith(
                          fontFamily: 'monospace', color: widget.dark ? MgColors.onDarkBody : MgColors.body2)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: MgBtnText(
                      label: tr.tr('v2StTechCopy'),
                      icon: MgIcons.copy,
                      dark: widget.dark,
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: widget.details));
                        if (context.mounted) showMgToast(context, tr.tr('v2StCopied'));
                      },
                    ),
                  ),
                ]),
              ),
      ),
    ]);
  }
}
