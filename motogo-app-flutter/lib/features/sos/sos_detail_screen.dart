import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import 'sos_provider.dart';

/// SOS detail / done screen — mirrors s-sos-done from templates-res-sos3.js.
/// Shows incident info, realtime timeline, next steps.
class SosDetailScreen extends ConsumerWidget {
  const SosDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeSosProvider);

    return activeAsync.when(
      data: (inc) {
        if (inc == null) return _doneView(context, null);
        return _buildDetail(context, ref, inc);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: MotoGoColors.green))),
      error: (_, __) => _doneView(context, null),
    );
  }

  Widget _doneView(BuildContext context, SosIncident? inc) {
    return Scaffold(
      backgroundColor: MotoGoColors.dark,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MotoGoColors.green, width: 3)),
                  child: const Center(child: Text('✅', style: TextStyle(fontSize: 32))),
                ),
                const SizedBox(height: 20),
                const Text('Incident nahlášen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 8),
                Text('Asistent MotoGo24 vás bude kontaktovat', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => context.go(Routes.reservations),
                  child: const Text('Moje rezervace →'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go(Routes.home),
                  child: const Text('Zpět domů', style: TextStyle(color: MotoGoColors.g400)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, WidgetRef ref, SosIncident inc) {
    final timelineAsync = ref.watch(sosTimelineProvider(inc.id));
    final statusLabels = {
      'reported': 'Nahlášeno', 'acknowledged': 'Přijato',
      'in_progress': 'Řeší se', 'resolved': 'Vyřešeno', 'closed': 'Uzavřeno',
    };

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🆘 SOS Incident', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                  Text(inc.id.substring(inc.id.length - 8).toUpperCase(), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                ])),
              ]),
              const SizedBox(height: 16),

              // Status card
              _Card(children: [
                _Row(label: 'Stav', child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: inc.isActive ? const Color(0xFFFEF3C7) : MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(statusLabels[inc.status] ?? inc.status,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: inc.isActive ? const Color(0xFFD97706) : MotoGoColors.greenDarker)),
                )),
                _Row(label: 'Typ', value: _typeLabel(inc.type)),
                _Row(label: 'Nahlášeno', value: '${inc.createdAt.day}. ${inc.createdAt.month}. ${inc.createdAt.year} ${inc.createdAt.hour}:${inc.createdAt.minute.toString().padLeft(2, '0')}'),
                if (inc.motoRideable != null)
                  _Row(label: 'Motorka pojízdná', value: inc.motoRideable! ? 'Ano' : 'Ne'),
                if (inc.customerFault != null)
                  _Row(label: 'Zavinění', value: inc.customerFault! ? 'Zákazník' : 'Porucha / nezaviněno'),
                if (inc.contactPhone != null)
                  _Row(label: 'Kontakt', value: inc.contactPhone!),
              ]),
              const SizedBox(height: 12),

              // Photos
              if (inc.photos.isNotEmpty) ...[
                _Card(children: [
                  const Text('📷 Fotodokumentace', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 70,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: inc.photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(inc.photos[i], width: 70, height: 70, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
              ],

              // Timeline (realtime)
              _Card(children: [
                const Text('📋 Timeline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                const SizedBox(height: 8),
                timelineAsync.when(
                  data: (entries) {
                    if (entries.isEmpty) return const Text('Zatím žádné záznamy', style: TextStyle(fontSize: 12, color: MotoGoColors.g400));
                    return Column(children: entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 5),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: MotoGoColors.green)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.action, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
                          Text('${e.createdAt.hour}:${e.createdAt.minute.toString().padLeft(2, '0')} · ${e.createdAt.day}. ${e.createdAt.month}.',
                            style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                        ])),
                      ]),
                    )).toList());
                  },
                  loading: () => const CircularProgressIndicator(color: MotoGoColors.green),
                  error: (_, __) => const Text('Chyba', style: TextStyle(color: MotoGoColors.red)),
                ),
              ]),
              const SizedBox(height: 16),

              // Actions
              if (inc.isActive && inc.isSerious)
                ElevatedButton(
                  onPressed: () => context.push(Routes.sosReplacement),
                  child: const Text('🏍️ Náhradní motorka'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push(Routes.messages),
                child: const Text('📩 Zprávy z MotoGo24'),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
    'theft' => 'Krádež', 'accident_minor' => 'Lehká nehoda', 'accident_major' => 'Závažná nehoda',
    'breakdown_minor' => 'Drobná závada', 'breakdown_major' => 'Porucha — nepojízdná',
    'defect_question' => 'Dotaz na závadu', 'location_share' => 'Sdílení polohy', _ => 'Jiné',
  };
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
      boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

class _Row extends StatelessWidget {
  final String label; final String? value; final Widget? child;
  const _Row({required this.label, this.value, this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
      child ?? Text(value ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
    ]),
  );
}
