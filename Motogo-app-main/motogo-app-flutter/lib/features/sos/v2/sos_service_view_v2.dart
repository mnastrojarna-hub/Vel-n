import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import 'sos_actions_v2.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// v2 "Servis na vlastní pěst" (SOS board): ok note, dark 4-step guide
/// (find service = existing maps link, invoice details in a glass well,
/// upload = existing invoice upload with spinner / ✓), coverage note;
/// after upload the dock carries "Hotovo — zpět na přehled" (existing).
class SosServiceViewV2 extends StatelessWidget {
  final bool uploading;
  final bool uploaded;
  final VoidCallback onBack;
  final VoidCallback onFindService;
  final VoidCallback onUpload;
  final VoidCallback onDone;
  const SosServiceViewV2({
    super.key,
    required this.uploading,
    required this.uploaded,
    required this.onBack,
    required this.onFindService,
    required this.onUpload,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final Widget upload;
    if (uploading) {
      upload = const SosBusyButtonV2();
    } else if (uploaded) {
      upload = Container(
        height: 48,
        decoration: BoxDecoration(color: MgColors.tintOk, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const MgIcon(MgIcons.check, size: 18, color: MgColors.link),
          const SizedBox(width: 8),
          Flexible(child: Text(tr.tr('invoiceUploaded'), style: MgType.button.copyWith(color: MgColors.onTintOk))),
        ]),
      );
    } else {
      upload = MgBtnGhostDark(label: tr.tr('uploadInvoicePhoto').toUpperCase(), icon: MgIcons.camera, onTap: onUpload);
    }
    final meta = MgType.small.copyWith(color: MgColors.onDarkLead);
    return SosPageV2(
      onBack: onBack,
      header: SosHeaderV2(
        onBack: onBack,
        icon: MgIcons.wrench,
        tint: SosTint.green,
        eyebrow: tr.tr('breakdownMinorLabel'),
        title: tr.tr('selfServiceTitle'),
        sub: tr.tr('selfServiceSubtitle'),
      ),
      dock: SosDockV2(
        cta: uploaded ? SosNeonButtonV2(label: tr.tr('doneBackToOverview'), icon: MgIcons.checkCircle, onTap: onDone) : null,
      ),
      sections: [
        SosNoteV2(ok: true, icon: MgIcons.checkCircle, title: tr.tr('v2UxAsmServiceInfo')),
        SosGuideV2(steps: [
          SosStepV2(tr.tr('v2UxAsmService1T'),
              icon: MgIcons.pin,
              text: tr.tr('v2UxAsmService1D'),
              action: MgBtnGhostDark(label: tr.tr('serviceSearchNearby'), icon: MgIcons.search, onTap: onFindService)),
          SosStepV2(tr.tr('v2UxAsmService2T'), icon: MgIcons.phone, text: tr.tr('v2UxAsmService2D')),
          SosStepV2(tr.tr('v2UxAsmService3T'),
              icon: MgIcons.receipt,
              action: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MgColors.white(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MgColors.white(0.14)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr.tr('invoiceDetails')}:', style: MgType.micro.copyWith(fontSize: 12, color: MgColors.onDarkLead)),
                  const SizedBox(height: 2),
                  Text('Bc. Petra Semorádová', style: MgType.title.copyWith(fontSize: 13.5, color: MgColors.onDark)),
                  Text('IČO: 21874263 · neplátce DPH', style: meta),
                  Text('Mezná 9, 393 01 Pelhřimov', style: meta),
                ]),
              )),
          SosStepV2(tr.tr('v2UxAsmService4T'), icon: MgIcons.share, text: tr.tr('serviceStep4Desc'), action: upload),
        ]),
        SosNoteV2(
          icon: MgIcons.info,
          title: tr.tr('coverageTitle'),
          lines: [(true, tr.tr('v2UxAsmCoverageYes')), (false, tr.tr('coverageNo'))],
        ),
      ],
    );
  }
}
