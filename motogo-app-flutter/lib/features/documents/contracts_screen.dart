import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/supabase_client.dart';
import '../../core/data/legal_texts.dart';
import 'document_models.dart';
import 'document_provider.dart';

/// Contracts & documents screen — mirrors s-contracts from templates-done-pages.js.
/// Shows rental contracts, handover protocols, VOP.
class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(title: const Text('📄 Dokumenty a smlouvy'), backgroundColor: MotoGoColors.dark),
      body: docsAsync.when(
        data: (docs) {
          // Filter to contract types only
          final contracts = docs.where((d) => ['contract', 'protocol', 'vop'].contains(d.type)).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // VOP virtual entry (always shown)
              _DocTile(
                icon: '📋',
                title: 'Všeobecné obchodní podmínky',
                subtitle: 'VOP — MotoGo24',
                onTap: () => _showVop(context),
              ),
              _DocTile(
                icon: '🔒',
                title: 'Zpracování osobních údajů',
                subtitle: 'GDPR — informace',
                onTap: () => _showGdpr(context),
              ),
              if (contracts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('Žádné další dokumenty', style: TextStyle(fontSize: 12, color: MotoGoColors.g400))),
                ),
              ...contracts.map((d) => _DocTile(
                icon: d.type == 'contract' ? '📄' : '📝',
                title: d.name ?? d.typeLabel,
                subtitle: '${d.createdAt.day}. ${d.createdAt.month}. ${d.createdAt.year}',
                onTap: () => _openDoc(d),
              )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
        error: (_, __) => const Center(child: Text('Chyba', style: TextStyle(color: MotoGoColors.red))),
      ),
    );
  }

  void _showVop(BuildContext context) {
    _showLegalDialog(context, LegalTexts.vopTitle, LegalTexts.vopSummary);
  }

  void _showGdpr(BuildContext context) {
    _showLegalDialog(context, LegalTexts.gdprTitle, LegalTexts.gdprSummary);
  }

  void _showLegalDialog(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(body, style: const TextStyle(fontSize: 12, color: MotoGoColors.g600, height: 1.6)),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Zavřít'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDoc(UserDocument doc) async {
    if (doc.storagePath != null) {
      final url = MotoGoSupabase.client.storage.from('documents').getPublicUrl(doc.storagePath!);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}

class _DocTile extends StatelessWidget {
  final String icon; final String title; final String subtitle; final VoidCallback onTap;
  const _DocTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
        ])),
        const Text('›', style: TextStyle(fontSize: 16, color: MotoGoColors.g400)),
      ]),
    ),
  );
}
