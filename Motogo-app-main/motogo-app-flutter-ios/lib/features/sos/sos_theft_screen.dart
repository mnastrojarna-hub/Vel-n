import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/native/gps_service.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'sos_provider.dart';

/// Theft screen — mirrors s-sos-kradez from templates-res-sos.js.
/// 4-step instructions + secured/unsecured decision + report + replacement.
class SosTheftScreen extends ConsumerStatefulWidget {
  const SosTheftScreen({super.key});

  @override
  ConsumerState<SosTheftScreen> createState() => _SosTheftState();
}

class _SosTheftState extends ConsumerState<SosTheftScreen> {
  bool _reported = false;
  String? _incidentId;
  bool _submitting = false;
  bool? _secured; // true = secured (free), false = unsecured (paid)

  Future<void> _reportTheft() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    double? lat, lng;
    try {
      final pos = await GpsService.getCurrentPosition();
      lat = pos?.latitude;
      lng = pos?.longitude;
    } catch (_) {}

    try {
      final incId = await createSosIncident(
        type: SosType.theft,
        description: 'Krádež motorky',
        lat: lat, lng: lng,
        isFault: _secured == false, // unsecured = customer fault
      );
      _incidentId = incId;
      ref.invalidate(activeSosProvider);
      setState(() { _reported = true; _submitting = false; });
      if (mounted) showMotoGoToast(context, icon: '✅', title: t(context).tr('theftReported'), message: t(context).tr('motoGoInformed'));
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
    }
  }

  void _requestReplacement() {
    if (_secured == null) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('theftSecuredQuestion'), message: t(context).tr('theftSelectSecured'));
      return;
    }
    // secured = free replacement, unsecured = paid
    ref.read(sosFaultProvider.notifier).state = !_secured!;
    context.push(Routes.sosReplacement);
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
              _header(context),
              const SizedBox(height: 16),

              // Step 1: Call police
              _step(1, '📞', t(context).tr('theftStep1Title'),
                  t(context).tr('theftStep1Desc'),
                  actionLabel: t(context).tr('theftCallPolice'),
                  onAction: () => launchUrl(Uri.parse('tel:158'))),
              const SizedBox(height: 8),

              // Step 2: Contact MotoGo
              _step(2, '📱', t(context).tr('theftStep2Title'),
                  t(context).tr('theftStep2Desc')),
              const SizedBox(height: 8),

              // Step 3: Case number
              _step(3, '📋', t(context).tr('theftStep3Title'),
                  t(context).tr('theftStep3Desc')),
              const SizedBox(height: 16),

              // Liability info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MotoGoColors.amberBg,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(color: MotoGoColors.amberBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚖️ ${t(context).tr('theftLiability')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                    const SizedBox(height: 6),
                    Text('✅ ${t(context).tr('theftSecuredInfo')}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF78350F))),
                    const SizedBox(height: 4),
                    Text('❌ ${t(context).tr('theftUnsecuredInfo')}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF78350F))),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Secured decision (for replacement pricing)
              Text(t(context).tr('theftSecuredQuestion'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              const SizedBox(height: 8),
              Row(children: [
                _securedBtn(true, '✅', t(context).tr('theftYesSecured'),
                    t(context).tr('theftSecuredDesc')),
                const SizedBox(width: 8),
                _securedBtn(false, '❌', t(context).tr('theftNoUnsecured'),
                    t(context).tr('theftUnsecuredDesc')),
              ]),
              const SizedBox(height: 16),

              // Report button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _reported || _submitting ? null : _reportTheft,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _reported ? MotoGoColors.greenDark : MotoGoColors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: MotoGoColors.greenDark,
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  child: Text(
                    _reported ? '✅ ${t(context).tr('theftReported')} MotoGo24' : '🚨 ${t(context).tr('reportIncident')} MotoGo24',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
              ),

              // Replacement option (after report)
              if (_reported) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Text(t(context).tr('wantReplacementMoto'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _requestReplacement,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: MotoGoColors.greenPale,
                      borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                      border: Border.all(color: MotoGoColors.g200),
                    ),
                    child: Row(children: [
                      const Text('🏍️', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t(context).tr('orderReplacementMoto'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                        Text(t(context).tr('selectMotoAndAddress'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g600)),
                      ])),
                      const Text('›', style: TextStyle(fontSize: 18, color: MotoGoColors.g400)),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.theftReported;
                    context.go(Routes.sosDone);
                  },
                  child: Text(t(context).tr('noReplacementEnd'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MotoGoColors.redBg,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        border: Border.all(color: MotoGoColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Text('🔐', style: TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t(context).tr('theftTitle'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          Text(t(context).tr('followStepsBelow'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
        ])),
        GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
            child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
          ),
        ),
      ]),
    );
  }

  Widget _step(int num, String icon, String title, String desc, {String? actionLabel, VoidCallback? onAction}) {
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
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
        ]),
        const SizedBox(height: 6),
        Text(desc, style: const TextStyle(fontSize: 11, color: MotoGoColors.g600)),
        if (actionLabel != null) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: MotoGoColors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            child: Text(actionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          )),
        ],
      ]),
    );
  }

  Widget _securedBtn(bool value, String icon, String label, String desc) {
    final selected = _secured == value;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _secured = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? (value ? MotoGoColors.greenPale : MotoGoColors.redBg) : Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: Border.all(
            color: selected ? (value ? MotoGoColors.greenDark : MotoGoColors.red) : MotoGoColors.g200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: selected ? MotoGoColors.black : MotoGoColors.g600)),
          Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: MotoGoColors.g400)),
        ]),
      ),
    ));
  }
}
