import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// One choice of an SOS type sheet (same action as the old row).
typedef SosTypeChoice = ({String icon, SosTint tint, String label, VoidCallback onTap});

/// Accident / breakdown type sheet (SOS board): light MgSheetFrame with
/// grabber, ✕ 44, swipe-down and scrim close; icon-tile rows. A row closes
/// the sheet and runs its existing action.
Future<void> showSosTypeSheetV2(BuildContext context, {required String title, required List<SosTypeChoice> choices}) {
  return showMgSheet<void>(
    context,
    title: title,
    builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in choices) ...[
        SosRowV2(
          icon: c.icon,
          tint: c.tint,
          title: c.label,
          onTap: () {
            Navigator.pop(ctx);
            c.onTap();
          },
        ),
        const SizedBox(height: 10),
      ],
    ]),
  );
}

/// The report sheet body (popis + fotky) in the v2 look. Still NOT
/// dismissible by drag / scrim (deliberate SOS safety) → no grabber; ✕ and
/// "Zrušit" run the existing discard-confirm cancel. The send button is
/// enabled by the SAME condition; when it is not, the line above it says
/// what is missing.
class SosReportSheetV2 extends StatelessWidget {
  final String typeLabel;
  final bool accident;
  final TextEditingController descCtrl;
  final List<String> photoPaths;
  final String? cameraProblem;
  final bool needsSettings;
  final bool missingDesc;
  final bool missingPhoto;
  final String submitLabel;
  final VoidCallback? onSubmit;
  final VoidCallback onCapture;
  final VoidCallback onCancel;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onDescChanged;
  const SosReportSheetV2({
    super.key,
    required this.typeLabel,
    required this.accident,
    required this.descCtrl,
    required this.photoPaths,
    required this.cameraProblem,
    required this.needsSettings,
    required this.missingDesc,
    required this.missingPhoto,
    required this.submitLabel,
    required this.onSubmit,
    required this.onCapture,
    required this.onCancel,
    required this.onOpenSettings,
    required this.onDescChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final mq = MediaQuery.of(context);
    final (bg, fg) = sosTintColors(accident ? SosTint.ok : SosTint.green);
    final missing = [if (missingDesc) tr.tr('sosDescriptionLabel'), if (missingPhoto) tr.tr('photoDocumentation')];
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(s, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: (mq.size.height - mq.padding.top) * 0.86 + mq.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: MgShadows.sheet,
        ),
        padding: EdgeInsets.fromLTRB(16, 14, 12, mq.viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Center(child: MgIcon(accident ? MgIcons.target : MgIcons.bolt, size: 22, color: fg)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(header: true, child: Text(typeLabel, style: MgType.h3.copyWith(color: MgColors.ink))),
            ),
            MgV2Back(onTap: onCancel, close: true, style: MgBackStyle.light),
          ]),
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(0, 12, 4, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr.tr('v2UxAsmSosReportWhy'), style: MgType.body.copyWith(color: MgColors.lead)),
                const SizedBox(height: 14),
                label('${tr.tr('sosDescriptionLabel')} *'),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  onChanged: onDescChanged,
                  style: MgType.body.copyWith(color: MgColors.ink),
                  decoration: mgInputDecoration(context, hint: tr.tr('sosDescriptionHint')).copyWith(hintMaxLines: 4),
                ),
                const SizedBox(height: 14),
                label('${tr.tr('photoDocumentation')}${cameraProblem == null ? ' *' : ''}'),
                if (photoPaths.isNotEmpty) ...[
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: photoPaths.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(photoPaths[i]),
                            width: 64,
                            height: 64,
                            cacheWidth: 192,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                width: 64,
                                height: 64,
                                color: MgColors.well,
                                child: const Center(child: MgIcon(MgIcons.image, size: 20, color: MgColors.meta)))),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                MgBtnGhostLight(
                  label: photoPaths.isEmpty ? tr.tr('takePhoto') : tr.tr('addAnotherPhoto'),
                  icon: MgIcons.camera,
                  onTap: onCapture,
                ),
                if (cameraProblem != null && photoPaths.isEmpty) ...[
                  const SizedBox(height: 10),
                  MgStateBanner(
                    tone: MgTone.warn,
                    icon: MgIcons.camera,
                    title: tr.tr('v2UxAsmSosNoCamTitle'),
                    text: tr.trArgs('eoSosNoCameraBody', {'reason': cameraProblem!}),
                    actions: [
                      if (needsSettings) MgBtnText(label: tr.tr('eoOpenSettings'), onTap: onOpenSettings),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                if (onSubmit == null && missing.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text('${tr.tr('missing')}: ${missing.join(' · ')}',
                          textAlign: TextAlign.center,
                          style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.warn)),
                    ),
                  ),
                MgBtnSos(label: submitLabel, onTap: onSubmit),
                const SizedBox(height: 4),
                Center(child: MgBtnText(label: tr.cancel, onTap: onCancel)),
                SizedBox(height: mq.padding.bottom + 8),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
