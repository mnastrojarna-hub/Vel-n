import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/native/gps_service.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'sos_provider.dart';

/// Service self-repair screen — mirrors s-sos-servis from templates-res-sos2.js.
/// 4-step instructions + invoice upload. Creates breakdown_minor incident.
class SosServiceScreen extends ConsumerStatefulWidget {
  const SosServiceScreen({super.key});

  @override
  ConsumerState<SosServiceScreen> createState() => _SosServiceState();
}

class _SosServiceState extends ConsumerState<SosServiceScreen> {
  bool _uploading = false;
  bool _uploaded = false;
  String? _incidentId;

  Future<String?> _ensureIncident() async {
    if (_incidentId != null) return _incidentId;

    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null && active.isActive) {
      _incidentId = active.id;
      return active.id;
    }

    double? lat, lng;
    try {
      final pos = await GpsService.getCurrentPosition();
      lat = pos?.latitude;
      lng = pos?.longitude;
    } catch (_) {}

    final id = await createSosIncident(
      type: SosType.breakdownMinor,
      description: 'Servis na vlastní pěst',
      lat: lat, lng: lng,
      isFault: false,
    );
    _incidentId = id;
    ref.invalidate(activeSosProvider);
    return id;
  }

  Future<void> _uploadInvoice() async {
    if (_uploading) return;

    final incId = await _ensureIncident();
    if (incId == null) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: t(context).tr('incidentCreateFailed'));
      return;
    }

    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2048);
    if (photo == null) return;

    setState(() => _uploading = true);
    final url = await uploadServiceInvoice(incId, photo);

    if (mounted) {
      setState(() { _uploading = false; _uploaded = url != null; });
      if (url != null) {
        showMotoGoToast(context, icon: '✅', title: t(context).tr('invoiceUploaded'), message: t(context).tr('reimbursement7days'));
      } else {
        showMotoGoToast(context, icon: '✗', title: t(context).error, message: t(context).tr('invoiceUploadFailed'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                  border: Border.all(color: MotoGoColors.g200),
                ),
                child: Row(children: [
                  const Text('🔧', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t(context).tr('selfServiceTitle'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                    Text(t(context).tr('selfServiceSubtitle'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                  ])),
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Text('←', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                ),
                child: Text(
                  '💚 ${t(context).tr('serviceRepairInfo')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker),
                ),
              ),
              const SizedBox(height: 16),

              // Step 1
              _step(1, '📍', t(context).tr('serviceStep1Title'),
                  t(context).tr('serviceStep1Desc'),
                  actionLabel: '📍 ${t(context).tr('serviceSearchNearby')}',
                  onAction: () => launchUrl(Uri.parse('https://maps.google.com/?q=motorka+servis'))),
              const SizedBox(height: 8),

              // Step 2
              _step(2, '📱', t(context).tr('serviceStep2Title'),
                  t(context).tr('serviceStep2Desc')),
              const SizedBox(height: 8),

              // Step 3
              _step(3, '🧾', t(context).tr('serviceStep3Title'),
                  null,
                  richContent: _invoiceDetails()),
              const SizedBox(height: 8),

              // Step 4
              _step(4, '📤', t(context).tr('serviceStep4Title'),
                  t(context).tr('serviceStep4Desc'),
                  actionLabel: _uploaded ? '✅ ${t(context).tr('invoiceUploaded')}' : '📸 ${t(context).tr('uploadInvoicePhoto')}',
                  onAction: _uploaded ? null : _uploadInvoice,
                  loading: _uploading),
              const SizedBox(height: 16),

              // Coverage info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MotoGoColors.amberBg,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.amberBorder),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('⚠️ ${t(context).tr('coverageTitle')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                  const SizedBox(height: 6),
                  Text('✅ ${t(context).tr('coverageYes')}', style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
                  const SizedBox(height: 2),
                  Text('❌ ${t(context).tr('coverageNo')}', style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
                ]),
              ),
              const SizedBox(height: 16),

              // Done button
              if (_uploaded)
                ElevatedButton(
                  onPressed: () {
                    ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.serviceSelf;
                    context.go(Routes.sosDone);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MotoGoColors.green,
                    foregroundColor: MotoGoColors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  child: Text('✅ ${t(context).tr('doneBackToOverview')}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _invoiceDetails() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MotoGoColors.g100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${t(context).tr('invoiceDetails')}:', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
        const SizedBox(height: 4),
        const Text('MotoGo24 s.r.o.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MotoGoColors.g600)),
        const Text('IČ: 123 456 78 · DIČ: CZ12345678', style: TextStyle(fontSize: 10, color: MotoGoColors.g400)),
        const Text('Mezná 9, 393 01', style: TextStyle(fontSize: 10, color: MotoGoColors.g400)),
      ]),
    );
  }

  Widget _step(int num, String icon, String title, String? desc,
      {String? actionLabel, VoidCallback? onAction, Widget? richContent, bool loading = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: MotoGoColors.g200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text('$num', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: MotoGoColors.black))),
          ),
          const SizedBox(width: 10),
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
        ]),
        if (desc != null) ...[
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(fontSize: 11, color: MotoGoColors.g600)),
        ],
        if (richContent != null) richContent,
        if (actionLabel != null) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: loading ? null : onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: MotoGoColors.green,
              foregroundColor: MotoGoColors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            child: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.black))
                : Text(actionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          )),
        ],
      ]),
    );
  }
}
