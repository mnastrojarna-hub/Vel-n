import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import '../catalog/catalog_provider.dart';
import '../catalog/moto_model.dart';
import '../booking/price_calculator.dart';
import 'sos_provider.dart';

/// SOS replacement motorcycle selection — mirrors s-sos-replacement
/// from templates-res-sos2.js + ui-sos-replacement.js.
class SosReplacementScreen extends ConsumerStatefulWidget {
  const SosReplacementScreen({super.key});

  @override
  ConsumerState<SosReplacementScreen> createState() => _SosReplacementState();
}

class _SosReplacementState extends ConsumerState<SosReplacementScreen> {
  Motorcycle? _selectedMoto;
  bool _isFault = false; // customer at-fault
  final _cityCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  double _deliveryFee = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final active = ref.read(activeSosProvider).valueOrNull;
    _isFault = active?.customerFault == true;
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _streetCtrl.dispose();
    super.dispose();
  }

  double get _motoTotal {
    if (_selectedMoto?.prices == null) return 0;
    // Remaining days until original booking end
    final remainingDays = 3; // Will be calculated from actual booking
    return _selectedMoto!.prices!.cheapest * remainingDays;
  }

  double get _damageDeposit => _isFault ? 30000 : 0;

  double get _total => _isFault ? (_motoTotal + _deliveryFee + _damageDeposit) : 0;

  void _calcDelivery() {
    final address = _streetCtrl.text.trim();
    if (address.isEmpty) { setState(() => _deliveryFee = 0); return; }
    final km = estimateKm('${_cityCtrl.text} $address');
    setState(() => _deliveryFee = PriceCalculator.calcDeliveryFee(km.toDouble()));
  }

  Future<void> _confirm() async {
    if (_selectedMoto == null) {
      showMotoGoToast(context, icon: '⚠️', title: 'Motorka', message: 'Vyberte náhradní motorku');
      return;
    }
    if (_streetCtrl.text.trim().isEmpty) {
      showMotoGoToast(context, icon: '⚠️', title: 'Adresa', message: 'Zadejte adresu přistavení');
      return;
    }

    setState(() => _loading = true);

    final active = ref.read(activeSosProvider).valueOrNull;
    if (active == null) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: 'Chyba', message: 'Žádný aktivní incident');
      setState(() => _loading = false);
      return;
    }

    try {
      // Call sos_swap_bookings RPC
      await MotoGoSupabase.client.rpc('sos_swap_bookings', params: {
        'p_incident_id': active.id,
        'p_replacement_moto_id': _selectedMoto!.id,
        'p_delivery_fee': _isFault ? _deliveryFee : 0,
        'p_daily_price': _isFault ? _selectedMoto!.prices!.cheapest : 0,
        'p_is_free': !_isFault,
      });

      // Timeline entry
      await MotoGoSupabase.client.from('sos_timeline').insert({
        'incident_id': active.id,
        'action': _isFault
            ? 'Zákazník objednal náhradní motorku: ${_selectedMoto!.model} (${_total.toStringAsFixed(0)} Kč)'
            : 'Zákazník objednal náhradní motorku: ${_selectedMoto!.model} (zdarma)',
        'description': 'Adresa: ${_streetCtrl.text}, ${_cityCtrl.text}',
      });
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: 'Chyba', message: '$e');
      setState(() => _loading = false);
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);
    ref.invalidate(activeSosProvider);

    if (_isFault) {
      // Navigate to SOS payment
      context.push(Routes.sosPayment);
    } else {
      showMotoGoToast(context, icon: '✅', title: 'Objednáno', message: 'Náhradní motorka bude přistavena zdarma');
      context.go(Routes.sosDone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motosAsync = ref.watch(motorcyclesProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header with fault banner
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _isFault
                    ? [const Color(0xFF7F1D1D), const Color(0xFFB91C1C)]
                    : [MotoGoColors.dark, const Color(0xFF2D4A35)]),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(width: 36, height: 36,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                        child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                    ),
                    const SizedBox(width: 12),
                    Text(_isFault ? '🏍️ Náhradní motorka — za poplatek' : '🏍️ Náhradní motorka — zdarma',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                  ]),
                  const SizedBox(height: 8),
                  Text(_isFault
                      ? 'Nehoda zaviněná zákazníkem — motorka a přistavení jsou za poplatek.'
                      : 'Porucha / nezaviněná nehoda — přistavení zdarma.',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Motorcycle list
                    const Text('Vyberte náhradní motorku', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    const SizedBox(height: 8),
                    motosAsync.when(
                      data: (motos) => Column(
                        children: motos.map((m) => _MotoOption(
                          moto: m,
                          selected: _selectedMoto?.id == m.id,
                          isFault: _isFault,
                          onTap: () => setState(() => _selectedMoto = m),
                        )).toList(),
                      ),
                      loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
                      error: (_, __) => const Text('Chyba načítání motorek'),
                    ),
                    const SizedBox(height: 16),

                    // Address
                    const Text('Adresa přistavení', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    const SizedBox(height: 8),
                    TextField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'Město'), onChanged: (_) => _calcDelivery()),
                    const SizedBox(height: 8),
                    TextField(controller: _streetCtrl, decoration: const InputDecoration(labelText: 'Ulice a č.p.'), onChanged: (_) => _calcDelivery()),
                    if (_deliveryFee > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('📍 Přistavení: ${_deliveryFee.toStringAsFixed(0)} Kč',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.greenDarker)),
                      ),
                    const SizedBox(height: 16),

                    // Summary (only for at-fault)
                    if (_isFault && _selectedMoto != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
                        child: Column(children: [
                          _SummaryRow(label: '🏍️ Motorka', value: '${_motoTotal.toStringAsFixed(0)} Kč'),
                          _SummaryRow(label: '🚛 Přistavení', value: '${_deliveryFee.toStringAsFixed(0)} Kč'),
                          _SummaryRow(label: '🛡️ Záloha na poškození', value: '${_damageDeposit.toStringAsFixed(0)} Kč'),
                          const Divider(),
                          _SummaryRow(label: 'Celkem', value: '${_total.toStringAsFixed(0)} Kč', bold: true),
                        ]),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // CTA button
            Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              color: Colors.white,
              child: ElevatedButton(
                onPressed: _loading ? null : _confirm,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isFault ? 'Zaplatit ${_total.toStringAsFixed(0)} Kč a objednat →' : 'Potvrdit objednávku (zdarma) →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MotoOption extends StatelessWidget {
  final Motorcycle moto; final bool selected; final bool isFault; final VoidCallback onTap;
  const _MotoOption({required this.moto, required this.selected, required this.isFault, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g200, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Container(width: 18, height: 18,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g400, width: 2)),
            child: selected ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: MotoGoColors.green))) : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(moto.model, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            Text(moto.category ?? '', style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
          ])),
          Text(isFault ? '${moto.priceLabel}/den' : 'Zdarma',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isFault ? MotoGoColors.black : MotoGoColors.greenDarker)),
        ]),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label; final String value; final bool bold;
  const _SummaryRow({required this.label, required this.value, this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: MotoGoColors.g600)),
      Text(value, style: TextStyle(fontSize: bold ? 16 : 12, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: bold ? MotoGoColors.greenDarker : MotoGoColors.black)),
    ]),
  );
}
