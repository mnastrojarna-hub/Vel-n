import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../profile/widgets/branches_sheet.dart';
import 'branches_info_provider.dart';
import 'branches_widgets.dart';
import '../../core/router.dart';
import '../../core/v2/flag/v2_scope.dart';
import '../../core/v2/shell/shell_nav_map.dart' show V2TabOrigin, v2SetTabOrigin;
import 'v2/branches_view_v2.dart';

/// Pobočky — přehled (Profil → Pobočky, na místě dočasně skrytého e-shopu).
/// Každá karta vede na vlastní obrazovku pobočky (`/pobocky/<index>`,
/// [BranchDetailScreen]) — stejně jako web /pobocky → /pobocky/<slug>.
/// Texty z Velína (`web.pobocky.*`).
class BranchesInfoScreen extends ConsumerWidget {
  const BranchesInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider).languageCode;
    final tx = ref.watch(branchesInfoProvider(lang)).valueOrNull ?? branchesInfoDefaults;

    // v2 vzhled (kill-switch app_v2_ui, PLAN §2.5.2): stejné texty i akce.
    if (MgV2.on(context)) {
      return BranchesViewV2(
        tx: tx,
        onBack: () => branchesBack(context),
        onRefresh: () => ref.refresh(branchesInfoProvider(lang).future),
        onOpen: (i) => context.push('/pobocky/$i'),
        onBook: () {
          v2SetTabOrigin(ref, const V2TabOrigin(tab: 1, route: Routes.branchesInfo, labelKey: 'branchesLabel'));
          context.go(Routes.search);
        },
        onMotosSheet: () => showBranchesSheet(context),
      );
    }

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: branchesAppBar(context, t(context).tr('branchesLabel')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(branchesInfoProvider(lang).future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            richText(tx['h1'], const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
            const SizedBox(height: 8),
            richText(tx['intro'], const TextStyle(fontSize: 14, height: 1.45, color: MotoGoColors.g600)),
            const SizedBox(height: 16),
            for (var i = 0; i < branchesInfoMapQueries.length; i++) _BranchTile(tx: tx, i: i),
            branchesCtaBox(context, tx),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showBranchesSheet(context),
              icon: const Text('🏍️'),
              label: Text(t(context).tr('branchesMotos')),
              style: OutlinedButton.styleFrom(
                foregroundColor: MotoGoColors.dark,
                side: const BorderSide(color: MotoGoColors.g200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
              ),
            ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  final Map<String, String> tx;
  final int i;
  const _BranchTile({required this.tx, required this.i});

  @override
  Widget build(BuildContext context) {
    String? v(String k) => tx['branches.$i.$k'];
    void open() => context.push('/pobocky/$i');
    return GestureDetector(
      onTap: open,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: branchesCardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          branchBadge(v('badge')),
          const SizedBox(height: 10),
          richText(v('title'), const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 8),
          branchLine('📍', v('address'), branchesBodyStyle),
          branchLine('🕑', v('hours'), branchesBodyStyle),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: open,
              style: ElevatedButton.styleFrom(
                backgroundColor: MotoGoColors.green, foregroundColor: MotoGoColors.dark, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
              ),
              child: Text(plainText(tx['detail_button'] ?? ''), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }
}
