import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/address_autocomplete_field.dart';
import '../auth/widgets/toast_helper.dart';
import '../catalog/catalog_provider.dart';
import '../catalog/moto_model.dart';
import '../booking/price_calculator.dart';
import '../payment/payment_provider.dart';
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
  final _addrKey = GlobalKey<AddressAutocompleteFieldState>();
  String _addrStreet = '';
  String _addrCity = '';
  double? _addrLat;
  double? _addrLng;
  double _deliveryFee = 0;
  double _deliveryKm = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Use sosFaultProvider (set by immobile/theft screens) — true = paid, null/false = free
    final fault = ref.read(sosFaultProvider);
    _isFault = fault == true;
  }

  @override
  void dispose() {
    super.dispose();
  }

  int get _remainingDays {
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null && active.bookingEndDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final end = active.bookingEndDate!;
      final days = end.difference(today).inDays + 1; // inclusive, matches RPC
      return days < 1 ? 1 : days;
    }
    return 3; // fallback
  }

  double get _motoTotal {
    if (_selectedMoto?.prices == null) return 0;
    final active = ref.read(activeSosProvider).valueOrNull;
    if (active != null && active.bookingEndDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final end = active.bookingEndDate!;
      if (end.isBefore(today)) {
        // End already passed — at least 1 day at today's rate
        return _selectedMoto!.prices!.forWeekday(today.weekday);
      }
      // Per-day pricing for each remaining day (inclusive)
      return _selectedMoto!.prices!.totalForRange(today, end);
    }
    // Fallback
    return _selectedMoto!.prices!.cheapest * 3;
  }

  double get _damageDeposit => _isFault ? 30000 : 0;

  double get _total => _isFault ? (_motoTotal + _deliveryFee + _damageDeposit) : 0;

  Future<void> _onAddressSelected(AddressSuggestion s) async {
    _addrStreet = s.street;
    _addrCity = s.city;
    _addrLat = s.lat;
    _addrLng = s.lng;
    double km;
    if (s.lat != null && s.lng != null) {
      km = await routeKmFromBranch(s.lat!, s.lng!);
    } else {
      km = estimateKm('${s.city} ${s.street}').toDouble();
    }
    if (!mounted) return;
    setState(() {
      _deliveryKm = km;
      _deliveryFee = PriceCalculator.calcDeliveryFee(km);
    });
  }

  void _onAddressCleared() {
    _addrStreet = '';
    _addrCity = '';
    _addrLat = null;
    _addrLng = null;
    setState(() { _deliveryFee = 0; _deliveryKm = 0; });
  }

  Future<void> _confirm() async {
    if (_selectedMoto == null) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).motorcycle, message: t(context).tr('selectReplacementMoto'));
      return;
    }
    if (_addrStreet.isEmpty && _addrCity.isEmpty) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('addressLabel'), message: t(context).tr('enterDeliveryAddress'));
      return;
    }

    setState(() => _loading = true);

    final active = ref.read(activeSosProvider).valueOrNull;
    if (active == null) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: t(context).tr('noActiveIncident'));
      setState(() => _loading = false);
      return;
    }

    String? replacementBookingId;
    try {
      // Call sos_swap_bookings RPC — returns replacement booking ID
      final rpcResult = await MotoGoSupabase.client.rpc('sos_swap_bookings', params: {
        'p_incident_id': active.id,
        'p_replacement_moto_id': _selectedMoto!.id,
        'p_replacement_model': _selectedMoto!.model,
        'p_delivery_fee': _isFault ? _deliveryFee : 0,
        'p_daily_price': _isFault && _remainingDays > 0
            ? (_motoTotal / _remainingDays) : 0,
        'p_is_free': !_isFault,
      });
      // Capture replacement booking ID from RPC result
      if (rpcResult is Map) {
        replacementBookingId = rpcResult['replacement_booking_id'] as String?
            ?? rpcResult['booking_id'] as String?;
      } else if (rpcResult is String) {
        replacementBookingId = rpcResult;
      }

      // Timeline entry
      await MotoGoSupabase.client.from('sos_timeline').insert({
        'incident_id': active.id,
        'action': _isFault
            ? 'Zákazník objednal náhradní motorku: ${_selectedMoto!.model} (${_total.toStringAsFixed(0)} Kč)'
            : 'Zákazník objednal náhradní motorku: ${_selectedMoto!.model} (zdarma)',
        'description': 'Adresa: $_addrStreet, $_addrCity',
      });
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
      setState(() => _loading = false);
      return;
    }

    // If RPC didn't return booking_id, try to fetch it from the incident
    if (replacementBookingId == null && _isFault) {
      try {
        final incident = await MotoGoSupabase.client
            .from('sos_incidents')
            .select('replacement_booking_id')
            .eq('id', active.id)
            .single();
        replacementBookingId = incident['replacement_booking_id'] as String?;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _loading = false);
    ref.invalidate(activeSosProvider);

    if (_isFault) {
      // Build SOS price breakdown for payment screen
      final breakdown = <SosPriceItem>[
        SosPriceItem(
          icon: '🏍️',
          label: '${_selectedMoto!.model} ($_remainingDays ${t(context).tr('days')})',
          amount: _motoTotal,
        ),
        SosPriceItem(
          icon: '🚛',
          label: _deliveryKm > 0
              ? '${t(context).tr('deliveryFee')} (${_deliveryKm.toStringAsFixed(0)} km)'
              : t(context).tr('deliveryFee'),
          amount: _deliveryFee,
        ),
        SosPriceItem(
          icon: '🛡️',
          label: t(context).tr('damageDeposit'),
          amount: _damageDeposit,
        ),
      ];

      ref.read(paymentContextProvider.notifier).state = PaymentContext(
        flowType: PaymentFlowType.sos,
        bookingId: replacementBookingId,
        incidentId: active.id,
        amount: _total,
        label: t(context).tr('sosReplacementMoto'),
        sosBreakdown: breakdown,
        sosDepositNote: t(context).tr('depositRefundableNote'),
      );
      // Pre-set done context for after payment
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.replacementPaid;
      ref.read(sosDoneModelProvider.notifier).state = _selectedMoto!.model;
      ref.read(sosDonePaidProvider.notifier).state = _total;
      context.push(Routes.sosPayment);
    } else {
      ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.replacementFree;
      ref.read(sosDoneModelProvider.notifier).state = _selectedMoto!.model;
      showMotoGoToast(context, icon: '✅', title: t(context).tr('ordered'), message: t(context).tr('replacementWillBeDeliveredFree'));
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
                    Text(_isFault ? '🏍️ ${t(context).tr('replacementPaid')}' : '🏍️ ${t(context).tr('replacementFree')}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                  ]),
                  const SizedBox(height: 8),
                  Text(_isFault
                      ? t(context).tr('faultPaidBannerDesc')
                      : t(context).tr('breakdownFreeBannerDesc'),
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
                    Text(t(context).tr('selectReplacementMoto'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
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
                      error: (_, __) => Text(t(context).tr('errorLoadingMotos')),
                    ),
                    const SizedBox(height: 16),

                    // Address
                    Text(t(context).tr('deliveryAddress'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    const SizedBox(height: 8),
                    AddressAutocompleteField(
                      key: _addrKey,
                      onSelected: _onAddressSelected,
                      onCleared: _onAddressCleared,
                      hint: t(context).tr('enterCity'),
                    ),
                    if (_deliveryFee > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('📍 ${t(context).tr('deliveryFee')}: ${_deliveryKm.toStringAsFixed(0)} km × 40 + 1 000 = ${_deliveryFee.toStringAsFixed(0)} Kč',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.greenDarker)),
                      ),
                    const SizedBox(height: 16),

                    // Summary (only for at-fault)
                    if (_isFault && _selectedMoto != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
                        child: Column(children: [
                          _SummaryRow(label: '🏍️ ${t(context).motorcycle}', value: '${_motoTotal.toStringAsFixed(0)} Kč'),
                          _SummaryRow(
                            label: _deliveryKm > 0
                                ? '🚛 ${t(context).tr('deliveryFee')} (${_deliveryKm.toStringAsFixed(0)} km × 40 + 1 000)'
                                : '🚛 ${t(context).tr('deliveryFee')}',
                            value: '${_deliveryFee.toStringAsFixed(0)} Kč',
                          ),
                          _SummaryRow(label: '🛡️ ${t(context).tr('damageDeposit')}', value: '${_damageDeposit.toStringAsFixed(0)} Kč'),
                          const Divider(),
                          _SummaryRow(label: t(context).tr('totalLabel'), value: '${_total.toStringAsFixed(0)} Kč', bold: true),
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
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_isFault ? Icons.payment : Icons.check_circle, size: 18),
                        const SizedBox(width: 8),
                        Text(_isFault ? '${t(context).tr('payAndOrder')} ${_total.toStringAsFixed(0)} Kč →' : t(context).tr('confirmOrderFree')),
                      ]),
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
          Text(isFault ? '${moto.priceLabel}/${t(context).tr('perDay')}' : t(context).free,
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
