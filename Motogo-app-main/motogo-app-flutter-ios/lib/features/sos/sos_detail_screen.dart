import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import 'sos_provider.dart';

/// SOS detail / done screen — mirrors s-sos-done from templates-res-sos3.js.
/// Shows contextual done view based on SosDoneType, or full detail with timeline.
class SosDetailScreen extends ConsumerWidget {
  const SosDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeSosProvider);
    final doneType = ref.watch(sosDoneTypeProvider);

    return activeAsync.when(
      data: (inc) {
        if (inc == null) return _doneView(context, ref, doneType);
        return _buildDetail(context, ref, inc);
      },
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator(color: MotoGoColors.green))),
      error: (_, __) => _doneView(context, ref, doneType),
    );
  }

  Widget _doneView(BuildContext context, WidgetRef ref, SosDoneType type) {
    final model = ref.read(sosDoneModelProvider);
    final paid = ref.read(sosDonePaidProvider);

    final config = _doneConfig(context, type, model, paid);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // Status header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: config.headerColor,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                ),
                child: Row(children: [
                  Text(config.icon, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(config.title,
                        style: const TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                    Text(config.subtitle,
                        style: const TextStyle(fontSize: 11, color: MotoGoColors.g600)),
                  ])),
                ]),
              ),
              const SizedBox(height: 16),

              // What happens next
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(t(context).tr('whatHappensNext'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                          color: MotoGoColors.g400, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Text(config.nextSteps,
                      style: const TextStyle(fontSize: 13, color: MotoGoColors.black)),
                ]),
              ),
              const SizedBox(height: 16),

              // Contact card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                  border: Border.all(color: MotoGoColors.g200),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(t(context).tr('directContact'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                          color: MotoGoColors.g400, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('📞', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('+420 774 256 271',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                              color: MotoGoColors.greenDarker)),
                      Text(t(context).tr('assistanceLine'),
                          style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                    ]),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),

              // Action buttons
              OutlinedButton(
                onPressed: () => context.push(Routes.messages),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                child: Text('📨 ${t(context).tr('messagesFromMotoGo')}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => context.go(Routes.reservations),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                child: Text('📋 ${t(context).tr('myReservations')}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go(Routes.home),
                child: Text(t(context).tr('backToHome'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: MotoGoColors.g400)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _DoneConfig _doneConfig(BuildContext context, SosDoneType type, String? model, double? paid) {
    switch (type) {
      case SosDoneType.accidentMinor:
        return _DoneConfig(
          icon: '✅', title: t(context).tr('doneAccidentMinorTitle'),
          subtitle: t(context).tr('doneIncidentReported'),
          headerColor: MotoGoColors.greenPale,
          nextSteps: t(context).tr('doneThanksSafeTrip'),
        );
      case SosDoneType.breakdownMinor:
        return _DoneConfig(
          icon: '✅', title: t(context).tr('doneBreakdownMinorTitle'),
          subtitle: t(context).tr('doneIncidentReported'),
          headerColor: MotoGoColors.greenPale,
          nextSteps: t(context).tr('doneThanksSafeTrip'),
        );
      case SosDoneType.theftReported:
        return _DoneConfig(
          icon: '🔐', title: t(context).tr('theftReported'),
          subtitle: t(context).tr('motoGoInformed'),
          headerColor: MotoGoColors.redBg,
          nextSteps: t(context).tr('doneTheftNextSteps'),
        );
      case SosDoneType.towOrdered:
        return _DoneConfig(
          icon: '🚛', title: t(context).tr('towOrdered'),
          subtitle: t(context).tr('doneTowRideEnded'),
          headerColor: MotoGoColors.amberBg,
          nextSteps: t(context).tr('doneTowNextSteps'),
        );
      case SosDoneType.towFree:
        return _DoneConfig(
          icon: '🚛', title: t(context).tr('doneTowFreeTitle'),
          subtitle: t(context).tr('doneTowFreeSubtitle'),
          headerColor: MotoGoColors.greenPale,
          nextSteps: t(context).tr('doneTowFreeNextSteps'),
        );
      case SosDoneType.replacementFree:
        return _DoneConfig(
          icon: '🏍️', title: t(context).tr('doneReplacementOrdered'),
          subtitle: model != null ? '${t(context).tr('doneSwitchedTo')} $model' : t(context).free,
          headerColor: MotoGoColors.greenPale,
          nextSteps: '${t(context).tr('doneReservationSwitched')}${model != null ? ' $model' : ''}. ${t(context).tr('doneAwaitingApproval')}',
        );
      case SosDoneType.replacementPaid:
        return _DoneConfig(
          icon: '💳', title: '${t(context).tr('donePaid')}${paid != null ? ' — ${paid.toStringAsFixed(0)} Kč' : ''}',
          subtitle: model != null ? '${t(context).tr('doneSwitchedTo')} $model' : t(context).tr('doneAwaitingApproval'),
          headerColor: MotoGoColors.greenPale,
          nextSteps: '${t(context).tr('doneReservationSwitched')}${model != null ? ' $model' : ''}. ${t(context).tr('doneAwaitingApproval')} ${t(context).tr('doneInvoiceGenerated')}',
        );
      case SosDoneType.serviceSelf:
        return _DoneConfig(
          icon: '🔧', title: t(context).tr('doneServiceReported'),
          subtitle: t(context).tr('doneInvoiceReceived'),
          headerColor: MotoGoColors.greenPale,
          nextSteps: t(context).tr('doneServiceNextSteps'),
        );
      case SosDoneType.generic:
        return _DoneConfig(
          icon: '✅', title: t(context).tr('doneIncidentResolved'),
          subtitle: t(context).tr('doneAllGood'),
          headerColor: MotoGoColors.greenPale,
          nextSteps: t(context).tr('doneAssistantContact'),
        );
    }
  }

  Widget _buildDetail(BuildContext context, WidgetRef ref, SosIncident inc) {
    final timelineAsync = ref.watch(sosTimelineProvider(inc.id));
    final statusLabels = {
      'reported': t(context).tr('reported'), 'acknowledged': t(context).tr('accepted'),
      'in_progress': t(context).tr('inProgress'), 'resolved': t(context).tr('resolved'), 'closed': t(context).tr('closed'),
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
                    decoration: BoxDecoration(color: MotoGoColors.green,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: Text('←',
                        style: TextStyle(fontSize: 18,
                            fontWeight: FontWeight.w900, color: Colors.black)))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🆘 SOS Incident',
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                  Text(inc.id.substring(inc.id.length - 8).toUpperCase(),
                      style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                ])),
              ]),
              const SizedBox(height: 16),

              // Status card
              _Card(children: [
                _Row(label: t(context).tr('statusLabel'), child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: inc.isActive ? MotoGoColors.amberBg : MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(statusLabels[inc.status] ?? inc.status,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                        color: inc.isActive ? MotoGoColors.amber : MotoGoColors.greenDarker)),
                )),
                _Row(label: t(context).tr('typeLabel'), value: _typeLabel(context, inc.type)),
                _Row(label: t(context).tr('reported'),
                    value: '${inc.createdAt.day}. ${inc.createdAt.month}. ${inc.createdAt.year} ${inc.createdAt.hour}:${inc.createdAt.minute.toString().padLeft(2, '0')}'),
                if (inc.motoRideable != null)
                  _Row(label: t(context).tr('motoRideableLabel'),
                      value: inc.motoRideable! ? t(context).tr('yes') : t(context).tr('no')),
                if (inc.customerFault != null)
                  _Row(label: t(context).tr('faultLabel'),
                      value: inc.customerFault! ? t(context).tr('customerFault') : t(context).tr('breakdownNotFault')),
              ]),
              const SizedBox(height: 12),

              // Photos
              if (inc.photos.isNotEmpty) ...[
                _Card(children: [
                  Text('📷 ${t(context).tr('photoDocumentation')}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                          color: MotoGoColors.black)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 70,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: inc.photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(inc.photos[i],
                            width: 70, height: 70, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
              ],

              // Timeline (realtime)
              _Card(children: [
                const Text('📋 Timeline',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                        color: MotoGoColors.black)),
                const SizedBox(height: 8),
                timelineAsync.when(
                  data: (entries) {
                    if (entries.isEmpty) return Text(t(context).tr('noRecordsYet'),
                        style: const TextStyle(fontSize: 12, color: MotoGoColors.g400));
                    return Column(children: entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Container(width: 8, height: 8,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, color: MotoGoColors.green)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(e.action,
                              style: const TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: MotoGoColors.black)),
                          Text('${e.createdAt.hour}:${e.createdAt.minute.toString().padLeft(2, '0')} · ${e.createdAt.day}. ${e.createdAt.month}.',
                              style: const TextStyle(fontSize: 10,
                                  color: MotoGoColors.g400)),
                        ])),
                      ]),
                    )).toList());
                  },
                  loading: () => const CircularProgressIndicator(
                      color: MotoGoColors.green),
                  error: (_, __) => Text(t(context).error,
                      style: const TextStyle(color: MotoGoColors.red)),
                ),
              ]),
              const SizedBox(height: 16),

              // Actions
              if (inc.isActive && inc.isSerious)
                ElevatedButton(
                  onPressed: () => context.push(Routes.sosReplacement),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    const Icon(Icons.motorcycle, size: 18),
                    const SizedBox(width: 8),
                    Text(t(context).tr('replacementMoto')),
                  ]),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push(Routes.messages),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Icon(Icons.mail_outline, size: 18),
                  const SizedBox(width: 8),
                  Text(t(context).tr('messagesFromMotoGo')),
                ]),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(BuildContext context, String type) => switch (type) {
    'theft' => t(context).theft,
    'accident_minor' => t(context).tr('accidentMinorLabel'),
    'accident_major' => t(context).tr('accidentMajorLabel'),
    'breakdown_minor' => t(context).tr('breakdownMinorLabel'),
    'breakdown_major' => t(context).tr('breakdownMajorLabel'),
    'defect_question' => t(context).tr('defectQuestionLabel'),
    'location_share' => t(context).shareLocation,
    _ => t(context).tr('other'),
  };
}

class _DoneConfig {
  final String icon;
  final String title;
  final String subtitle;
  final Color headerColor;
  final String nextSteps;
  const _DoneConfig({
    required this.icon, required this.title, required this.subtitle,
    required this.headerColor, required this.nextSteps,
  });
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06),
            blurRadius: 12)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children),
  );
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  const _Row({required this.label, this.value, this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
      child ?? Text(value ?? '', style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w600, color: MotoGoColors.black)),
    ]),
  );
}
