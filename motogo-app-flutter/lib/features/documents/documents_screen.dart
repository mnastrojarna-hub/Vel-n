import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import 'document_models.dart';
import 'document_provider.dart';

/// Documents screen — mirrors s-docs from templates-done-pages.js.
/// Shows doc verification status, scan button, document list.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verifiedAsync = ref.watch(docsVerifiedProvider);
    final docsAsync = ref.watch(documentsProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(title: const Text('📋 Moje doklady'), backgroundColor: MotoGoColors.dark),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Verification status banner
            verifiedAsync.when(
              data: (v) => _VerificationBanner(verification: v),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),

            // Scan button
            ElevatedButton.icon(
              onPressed: () => context.push(Routes.docScan),
              icon: const Text('📷', style: TextStyle(fontSize: 18)),
              label: const Text('Naskenovat doklady'),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 16),

            // Document tabs
            const Text('Nahrané doklady', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 8),

            docsAsync.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Column(children: [
                      Text('📋', style: TextStyle(fontSize: 36)),
                      SizedBox(height: 8),
                      Text('Žádné dokumenty', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                      Text('Naskenujte doklady pro rychlejší rezervaci', style: TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                    ]),
                  );
                }
                return Column(children: docs.map((d) => _DocTile(doc: d)).toList());
              },
              loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
              error: (_, __) => const Text('Chyba načítání', style: TextStyle(color: MotoGoColors.red)),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  final DocsVerification verification;
  const _VerificationBanner({required this.verification});

  @override
  Widget build(BuildContext context) {
    if (verification.isComplete) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MotoGoColors.greenPale,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
        ),
        child: const Row(children: [
          Text('✅', style: TextStyle(fontSize: 22)),
          SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Doklady ověřeny', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
            Text('OP/Pas + Řidičský průkaz', style: TextStyle(fontSize: 11, color: MotoGoColors.g600)),
          ])),
        ]),
      );
    }

    final missing = <String>[];
    if (!verification.hasIdOrPassport) missing.add('OP nebo pas');
    if (!verification.hasLicense) missing.add('řidičský průkaz');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(children: [
        const Text('⚠️', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Doklady neověřeny', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
          Text('Chybí: ${missing.join(", ")}', style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
        ])),
      ]),
    );
  }
}

class _DocTile extends StatelessWidget {
  final UserDocument doc;
  const _DocTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
      child: Row(children: [
        Text(doc.typeLabel.substring(0, 2), style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc.name ?? doc.typeLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
          Text('${doc.createdAt.day}. ${doc.createdAt.month}. ${doc.createdAt.year}', style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
        ])),
      ]),
    );
  }
}
