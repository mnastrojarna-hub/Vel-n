import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/router.dart';
import '../../core/friendly_error.dart';
import '../../core/widgets/state_views.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'sos_feedback.dart';
import 'sos_location.dart';
import 'sos_provider.dart';
import 'sos_report_sheet.dart';
import '../../core/widgets/mg_nav_controls.dart';

/// SOS main screen — mirrors s-sos from templates-res-sos.js.
/// Shows incident type selection, active incident banner, contact info.
class SosReportScreen extends ConsumerWidget {
  const SosReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeSosProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  MgBackTap(
                    onTap: () => context.backOr(Routes.home),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🆘 ${t(context).sosTitle}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                      Text(t(context).tr('selectProblemType'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Active incident banner — tappable, otevře detail incidentu.
              // Zobrazuje se pro JAKÝKOLIV aktivní incident (i „v řešení"),
              // ne jen vážný — aby na něj šlo vždy kliknout.
              activeAsync.when(
                data: (inc) {
                  if (inc == null || !inc.isActive) return const SizedBox.shrink();
                  return _ActiveBanner(
                    incident: inc,
                    onTap: () => context.push(Routes.sosDone),
                  );
                },
                loading: () => const SizedBox.shrink(),
                // Stav se nenačetl (výpadek) → říct to, ne tiše schovat.
                error: (e, _) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MgErrorView(
                    compact: true,
                    error: e,
                    what: t(context).tr('eoSosStatusFail'),
                    message: t(context).tr('eoSosStatusFailBody'),
                    onRetry: () => ref.invalidate(activeSosProvider),
                    contact: false,
                    extra: const [SosCallButton()],
                  ),
                ),
              ),

              // AI Agent card
              GestureDetector(
                onTap: () => context.push(Routes.aiAgent),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [MotoGoColors.dark, Color(0xFF2D4A35)]),
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                  ),
                  child: Row(
                    children: [
                      const Text('🤖', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t(context).tr('aiServiceAgent'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text(t(context).tr('aiServiceAgentDesc'), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      )),
                      const Text('›', style: TextStyle(fontSize: 20, color: MotoGoColors.green)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Emergency numbers banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MotoGoColors.redBg,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🚨 ${t(context).tr('emergencyFirst')}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: MotoGoColors.red),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _EmergencyChip(label: '112', desc: t(context).tr('emergencyGeneral')),
                        const SizedBox(width: 8),
                        _EmergencyChip(label: '155', desc: t(context).tr('emergencyAmbulance')),
                        const SizedBox(width: 8),
                        _EmergencyChip(label: '158', desc: t(context).tr('emergencyPolice')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Incident types
              _SosOption(
                icon: '💥', title: t(context).tr('accidentTheft'),
                subtitle: t(context).tr('reportAccidentTheft'),
                color: MotoGoColors.redBg,
                onTap: () => _showAccidentPicker(context, ref),
              ),
              const SizedBox(height: 8),
              _SosOption(
                icon: '🔧', title: t(context).tr('breakdownOnRoad'),
                subtitle: t(context).tr('motoNotWorking'),
                color: MotoGoColors.amberBg,
                onTap: () => _showBreakdownPicker(context, ref),
              ),
              const SizedBox(height: 8),
              _SosOption(
                icon: '📍', title: t(context).shareLocation,
                subtitle: t(context).tr('sendGpsToMotoGo'),
                color: const Color(0xFFE8FFE8),
                onTap: () => _shareLocation(context, ref),
              ),
              const SizedBox(height: 20),

              // Contact info
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.g200),
                ),
                child: Row(
                  children: [
                    const Text('📞', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(context).tr('nonstopLine'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                        const Text('+420 774 256 271', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
                      ],
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccidentPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MgSheetTitleRow(title: Text(t(context).tr('accidentType'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
              const SizedBox(height: 16),
              _PickerItem(icon: '🎯', label: t(context).tr('minorAccidentContinue'),
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.accidentMinor, t(context).tr('accidentMinorLabel')); }),
              _PickerItem(icon: '🚨', label: t(context).tr('seriousAccidentImmobile'),
                  onTap: () { Navigator.pop(ctx); context.push(Routes.sosAccident); }),
              _PickerItem(icon: '🔐', label: t(context).tr('theftTitle'),
                  onTap: () { Navigator.pop(ctx); context.push(Routes.sosTheft); }),
            ],
          ),
        ),
      ),
    );
  }

  void _showBreakdownPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MgSheetTitleRow(title: Text(t(context).tr('breakdownType'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
              const SizedBox(height: 16),
              _PickerItem(icon: '🔩', label: t(context).tr('minorDefectContinue'),
                  onTap: () { Navigator.pop(ctx); _report(context, ref, SosType.breakdownMinor, t(context).tr('breakdownMinorLabel')); }),
              _PickerItem(icon: '🚫', label: t(context).tr('motoImmobile'),
                  onTap: () { Navigator.pop(ctx); context.push(Routes.sosBreakdown); }),
              _PickerItem(icon: '🔧', label: t(context).tr('nearestServiceInvoice'),
                  onTap: () { Navigator.pop(ctx); context.push(Routes.sosService); }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref, String type, String typeLabel) async {
    // 0. POVINNÝ popis + fotodokumentace — bez nich incident nelze nahlásit
    //    (fotka jen když ji telefon umí pořídit). Velín tak u KAŽDÉHO SOS
    //    vidí popis i fotky.
    final collected = await collectSosReport(context, typeLabel);
    if (collected == null || !context.mounted) return;

    final userDesc = collected.description;
    final photos = collected.photos;
    // Sloučíme kategorii + popis zákazníka, ať Velín vidí oboje.
    final fullDesc = '$typeLabel — $userDesc'
        '${collected.cameraProblem ? ' [bez fotek – kamera nedostupná]' : ''}';
    await _submitReport(context, ref, type, fullDesc, photos);
  }

  /// Odeslání hlášení s průběhem (nejde zavřít ani odeslat dvakrát) a s
  /// chybou, která řekne proč a nabídne volání / opakování.
  Future<void> _submitReport(BuildContext context, WidgetRef ref, String type,
      String fullDesc, List<XFile> photos) async {
    final tr = t(context);
    final progress = SosProgress.show(context, tr.tr('eoSosSendingGps'));

    // 1. Capture GPS position (max 20 s, nic neotevírá)
    final loc = await sosLocate();
    final lat = loc.pos?.latitude, lng = loc.pos?.longitude;
    progress.update(tr.tr('eoSosSending'));

    // 2. Determine fault (major accident = ask, breakdown = not at fault)
    final bool isFault = type == SosType.accidentMajor || type == SosType.theft;

    // 3. Create incident via direct INSERT with GPS + popis zákazníka
    String incId;
    try {
      incId = await createSosIncident(
        type: type,
        description: fullDesc,
        lat: lat,
        lng: lng,
        isFault: isFault,
      ).timeout(const Duration(seconds: 45));
    } catch (e) {
      progress.close();
      if (!context.mounted) return;
      final retry = await showSosActionFailed(context,
          title: tr.tr('eoSosReportFailTitle'), error: e);
      if (retry && context.mounted) {
        await _submitReport(context, ref, type, fullDesc, photos);
      }
      return;
    }

    // 4. Upload povinné fotodokumentace
    var photosFailed = false;
    if (photos.isNotEmpty) {
      progress.update(tr.tr('eoSosSendingPhotos'));
      try {
        // Celkový strop ~40 s (uvnitř) — incident už je nahlášený, zákazník
        // nesmí čekat minuty; co nedojde, pošle ve Zprávách.
        final sent = await uploadSosPhotos(incId, photos);
        photosFailed = sent.length < photos.length;
      } catch (e) {
        FriendlyError.log('sos_photo_upload', e);
        photosFailed = true;
      }
    }
    progress.close();

    if (!context.mounted) return;
    ref.invalidate(activeSosProvider);
    if (photosFailed) {
      showMotoGoToast(context,
          icon: '⚠️',
          title: tr.tr('photoUploadFailed'),
          message: tr.tr('eoSosPhotosLater'),
          duration: const Duration(seconds: 8));
    } else if (loc.pos == null) {
      showSosSentWithoutLocation(context);
    }

    // 5. Set done type based on incident type
    if (type == SosType.accidentMinor) {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.accidentMinor;
    } else if (type == SosType.breakdownMinor) {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.breakdownMinor;
    } else {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.generic;
    }

    if (!photosFailed && loc.pos != null) {
      showMotoGoToast(context, icon: '✅', title: tr.tr('incidentReported'), message: tr.tr('motoGoInformed'));
    }
    context.push(Routes.sosDone);
  }

  /// „Sdílet polohu" — úspěch JEN když poloha opravdu dorazila; jinak důvod
  /// a volání / nastavení / zkusit znovu.
  Future<void> _shareLocation(BuildContext context, WidgetRef ref) async {
    final tr = t(context);
    final progress = SosProgress.show(context, tr.tr('sharingLocation'));
    final active = ref.read(activeSosProvider).valueOrNull;
    final r = await shareLocationNow(active?.isActive == true ? active!.id : null);
    progress.close();
    if (!context.mounted) return;
    ref.invalidate(activeSosProvider);
    final retry = await showSosLocationResult(context, r);
    if (retry && context.mounted) await _shareLocation(context, ref);
  }
}

class _ActiveBanner extends StatelessWidget {
  final SosIncident incident;
  final VoidCallback onTap;
  const _ActiveBanner({required this.incident, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusLabels = {
      'reported': t(context).tr('reported'),
      'acknowledged': t(context).tr('accepted'),
      'in_progress': t(context).tr('inProgress'),
    };
    return PressableScale(
      pressedScale: 0.97,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: MotoGoColors.amberBg, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: Border.all(color: MotoGoColors.amberBorder, width: 2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⚠️ ${t(context).tr('activeSosIncident')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                  Text('${t(context).tr('statusLabel')}: ${statusLabels[incident.status] ?? incident.status} · ${incident.id.substring(incident.id.length - 8).toUpperCase()}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
                  Text(t(context).tr('tapToOpenDetail'),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                ],
              ),
            ),
            const Text('›', style: TextStyle(fontSize: 20, color: Color(0xFF92400E))),
          ],
        ),
      ),
    );
  }
}

class _SosOption extends StatelessWidget {
  final String icon; final String title; final String subtitle;
  final Color color; final VoidCallback onTap;
  const _SosOption({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm), border: Border.all(color: MotoGoColors.g200)),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 20)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
          ])),
          const Text('›', style: TextStyle(fontSize: 18, color: MotoGoColors.g400)),
        ]),
      ),
    );
  }
}

class _EmergencyChip extends StatelessWidget {
  final String label;
  final String desc;
  const _EmergencyChip({required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PressableScale(
        onTap: () => launchUrl(Uri.parse('tel:$label')),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MotoGoColors.red.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.red)),
              Text(desc, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerItem extends StatelessWidget {
  final String icon; final String label; final VoidCallback onTap;
  const _PickerItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: 0.96,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm), border: Border.all(color: MotoGoColors.g200)),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)), const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black))),
          const Text('›', style: TextStyle(fontSize: 16, color: MotoGoColors.g400)),
        ]),
      ),
    );
  }
}
