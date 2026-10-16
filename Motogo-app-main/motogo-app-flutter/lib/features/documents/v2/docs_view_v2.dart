import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/widgets/state_views.dart';
import '../docs_gate_provider.dart';
import 'docs_parts_v2.dart';

/// Moje doklady in the v2 look (PLAN §2.5.2, seam view of
/// `DocumentsScreen`): dark compact app bar, verification banner, the dark
/// hero with the two document cards (OP/Pas, ŘP) + the screen's ONE looping
/// CTA "NASKENOVAT DOKLADY KAMEROU", the ŘP-only scan when the ID is done,
/// "NAHRÁT Z GALERIE", tips behind ⓘ, then the gate line / codes-ready box.
/// Outside the shell (no nav) — back as today. All actions are the screen's.
class DocsViewV2 extends StatelessWidget {
  final AsyncValue<DocsScreenStatus> verifiedAsync;
  final VoidCallback onBack;
  final VoidCallback onScan;
  final VoidCallback onScanDl;
  final VoidCallback onUpload;
  final ValueChanged<String> onReset;
  final VoidCallback onRetry;

  const DocsViewV2({
    super.key,
    required this.verifiedAsync,
    required this.onBack,
    required this.onScan,
    required this.onScanDl,
    required this.onUpload,
    required this.onReset,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final v = verifiedAsync.when<DocsScreenStatus?>(
      skipLoadingOnReload: true,
      data: (v) => v,
      loading: () => null,
      error: (_, __) => null,
    );
    final loading = verifiedAsync.when<bool>(
        skipLoadingOnReload: true, data: (_) => false, loading: () => true, error: (_, __) => false);
    final error = verifiedAsync.when<Object?>(
        skipLoadingOnReload: true, data: (_) => null, loading: () => null, error: (e, _) => e);

    return MgPage(
      header: MgAppBar(title: tr.tr('myDocuments'), subtitle: tr.tr('docsBeforeFirst'), onBack: onBack),
      overlapHero: false,
      sections: [
        if (v != null) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: MgEnter(child: _Banner(v: v))),
        MgDarkHero(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (v != null && !v.isComplete) ...[
              Text(tr.tr('v2DocsRequiredInfo'), style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              const SizedBox(height: 12),
            ],
            if (loading)
              const DocCardsSkeletonV2()
            else if (v != null)
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: DocCardV2(
                      icon: MgIcons.idCard,
                      title: tr.tr('idCardPassport'),
                      verified: v.hasIdOrPassport,
                      onReset: () => onReset('id_card'),
                      onScan: v.hasIdOrPassport ? null : onScan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DocCardV2(
                      icon: MgIcons.license,
                      title: tr.tr('driversLicense'),
                      verified: v.hasLicense,
                      onReset: () => onReset('drivers_license'),
                      onScan: v.hasLicense ? null : onScanDl,
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 12),
            const DocTipsV2(),
            const SizedBox(height: 4),
            MgCta(label: tr.tr('scanDocsCamera'), loop: true, onTap: onScan),
            if (v != null && v.hasIdOrPassport && !v.hasLicense) ...[
              const SizedBox(height: 10),
              MgBtnGhostDark(label: tr.tr('scanDlOnly'), icon: MgIcons.license, onTap: onScanDl),
            ],
            const SizedBox(height: 10),
            MgBtnGhostDark(label: tr.tr('uploadFromGallery'), icon: MgIcons.image, onTap: onUpload),
          ]),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: MgErrorView(compact: true, error: error, what: tr.tr('eoDocsStatusFail'), onRetry: onRetry),
          ),
        if (v != null) ..._statusFooter(context, v),
      ],
    );
  }

  List<Widget> _statusFooter(BuildContext context, DocsScreenStatus v) {
    final tr = t(context);
    final gate = v.gate;
    final missing = gate != null && !gate.ok ? docsGateMissingLabels(context, gate) : const <String>[];
    final none = !v.hasIdOrPassport && !v.hasLicense;
    return [
      if (none)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: MgStateBanner(
            tone: MgTone.info,
            title: tr.tr('docsStatus'),
            text: [
              tr.tr('docsNotVerifiedDesc'),
              if (missing.isNotEmpty) '${tr.tr('missing')}: ${missing.join(', ')}',
            ].join('\n'),
          ),
        )
      else if (missing.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: MgStateBanner(tone: MgTone.warn, title: tr.tr('docsStatus'), text: '${tr.tr('missing')}: ${missing.join(', ')}'),
        ),
      if (!none && v.codesReady)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: MgTintOk(
            child: Row(children: [
              const MgIcon(MgIcons.checkCircle, size: 20, color: MgColors.link),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr.tr('docsVerifiedDesc'),
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onTintOk)),
              ),
            ]),
          ),
        ),
    ];
  }
}

/// Verification banner (today's `_VerificationBanner` data): ✓ verified /
/// ⚠ not verified + what is missing.
class _Banner extends StatelessWidget {
  final DocsScreenStatus v;
  const _Banner({required this.v});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    if (v.isComplete) {
      return MgStateBanner(tone: MgTone.ok, title: tr.tr('docsVerified'), text: tr.tr('idPassportShort'));
    }
    final missing = <String>[
      if (!v.hasIdOrPassport) tr.tr('idOrPassport'),
      if (!v.hasLicense) tr.tr('driversLicense').toLowerCase(),
    ];
    return MgStateBanner(
      tone: MgTone.warn,
      title: tr.tr('docsNotVerified'),
      text: '${tr.tr('missing')}: ${missing.join(", ")}',
    );
  }
}
