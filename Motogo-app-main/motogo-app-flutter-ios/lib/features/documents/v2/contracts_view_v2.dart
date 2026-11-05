import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/v2/profile_v2_parts.dart';
import '../contracts_screen.dart' show docDisplayTitle;
import '../document_models.dart';

/// Dokumenty a smlouvy in the v2 look (PLAN §2.5.2, seam view of
/// `ContractsScreen`): two groups — "Obchodní podmínky a vzory" (VOP, GDPR,
/// damage protocol sample; always visible, also on error) and "Tvoje
/// dokumenty" (contracts / protocols with date). Every row opens the SAME
/// viewer as today.
class ContractsViewV2 extends StatelessWidget {
  final AsyncValue<List<UserDocument>> docsAsync;
  final List<UserDocument> Function(List<UserDocument>) contractsOf;
  final VoidCallback onBack;
  final VoidCallback onVop;
  final VoidCallback onGdpr;
  final VoidCallback onDamageSample;
  final ValueChanged<UserDocument> onOpenDoc;
  final VoidCallback onRetry;

  const ContractsViewV2({
    super.key,
    required this.docsAsync,
    required this.contractsOf,
    required this.onBack,
    required this.onVop,
    required this.onGdpr,
    required this.onDamageSample,
    required this.onOpenDoc,
    required this.onRetry,
  });

  static String iconFor(String type) => switch (type) {
        'contract' => MgIcons.doc,
        'protocol_damage' => MgIcons.warn,
        'vop' => MgIcons.docs,
        _ => MgIcons.protocol,
      };

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final mine = docsAsync.when<Widget>(
      data: (docs) {
        final contracts = contractsOf(docs);
        if (contracts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MgColors.well,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MgColors.line),
              ),
              child: Row(children: [
                const MgIcon(MgIcons.docs, size: 22, color: MgColors.meta),
                const SizedBox(width: 10),
                Expanded(child: Text(tr.tr('noOtherDocs'), style: MgType.body.copyWith(color: MgColors.lead))),
              ]),
            ),
          );
        }
        return MgReveal(
          child: PfGroup(rows: [
            for (final d in contracts)
              PfRow(
                icon: iconFor(d.type),
                title: docDisplayTitle(tr, d),
                value: '${d.createdAt.day}. ${d.createdAt.month}. ${d.createdAt.year}',
                onTap: () => onOpenDoc(d),
              ),
          ]),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: MgColors.link)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: MgErrorView(compact: true, error: e, what: tr.tr('eoContractsLoadFail'), onRetry: onRetry),
      ),
    );
    return MgPage(
      header: MgAppBar(title: tr.tr('documentsAndContracts'), onBack: onBack),
      overlapHero: false,
      sections: [
        PfSectionLabel(tr.tr('v2DocGroupTerms'), icon: MgIcons.shield,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12)),
        MgReveal(
          sessionKey: 'contracts-terms',
          child: PfGroup(rows: [
            PfRow(icon: MgIcons.docs, title: tr.tr('termsOfService'), value: tr.tr('vopSubtitle'), onTap: onVop),
            PfRow(icon: MgIcons.lock, title: tr.tr('dataProcessing'), value: tr.tr('gdprSubtitle'), onTap: onGdpr),
            PfRow(icon: MgIcons.warn, title: tr.tr('damageProtocol'), value: tr.tr('damageProtocolSubtitle'), onTap: onDamageSample),
          ]),
        ),
        PfSectionLabel(tr.tr('v2DocGroupMine'), icon: MgIcons.doc),
        mine,
      ],
    );
  }
}
