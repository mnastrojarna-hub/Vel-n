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
import 'sos_provider.dart';

/// SOS replacement motorcycle selection.
///
/// Náhradní motorka je v APLIKACI VŽDY ZDARMA — placené flow (spoluúčast
/// 30 000 Kč + nájem náhrady) bylo z aplikace zrušeno. Zákazník jen vybere
/// motorku a adresu přistavení. Případná spoluúčast/škody řeší operátor ve
/// Velínu (telefonické nahlášení / web rezervace), ne aplikace.
class SosReplacementScreen extends ConsumerStatefulWidget {
  const SosReplacementScreen({super.key});

  @override
  ConsumerState<SosReplacementScreen> createState() => _SosReplacementState();
}

class _SosReplacementState extends ConsumerState<SosReplacementScreen> {
  Motorcycle? _selectedMoto;
  final _addrKey = GlobalKey<AddressAutocompleteFieldState>();
  String _addrStreet = '';
  String _addrCity = '';
  bool _loading = false;

  void _onAddressSelected(AddressSuggestion s) {
    _addrStreet = s.street;
    _addrCity = s.city;
  }

  void _onAddressCleared() {
    _addrStreet = '';
    _addrCity = '';
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

    try {
      // Náhrada vždy zdarma — sos_swap_bookings založí náhradní rezervaci
      // (paid, 0 Kč) a ukončí původní.
      await MotoGoSupabase.client.rpc('sos_swap_bookings', params: {
        'p_incident_id': active.id,
        'p_replacement_moto_id': _selectedMoto!.id,
        'p_replacement_model': _selectedMoto!.model,
        'p_delivery_fee': 0,
        'p_daily_price': 0,
        'p_is_free': true,
      });

      await MotoGoSupabase.client.from('sos_timeline').insert({
        'incident_id': active.id,
        'action': 'Zákazník objednal náhradní motorku: ${_selectedMoto!.model} (zdarma)',
        'description': 'Adresa: $_addrStreet, $_addrCity',
      });
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
      setState(() => _loading = false);
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);
    ref.invalidate(activeSosProvider);

    ref.read(sosDoneTypeProvider.notifier).state = SosDoneType.replacementFree;
    ref.read(sosDoneModelProvider.notifier).state = _selectedMoto!.model;
    showMotoGoToast(context, icon: '✅', title: t(context).tr('ordered'), message: t(context).tr('replacementWillBeDeliveredFree'));
    context.go(Routes.sosDone);
  }

  @override
  Widget build(BuildContext context) {
    final motosAsync = ref.watch(motorcyclesProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header — náhrada zdarma
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [MotoGoColors.dark, Color(0xFF2D4A35)]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    GestureDetector(
                      onTap: () => context.backOr(Routes.home),
                      child: Container(width: 36, height: 36,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                        child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                    ),
                    const SizedBox(width: 12),
                    Text('🏍️ ${t(context).tr('replacementFree')}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                  ]),
                  const SizedBox(height: 8),
                  Text(t(context).tr('breakdownFreeBannerDesc'),
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
                      data: (motos) {
                        if (motos.isEmpty) {
                          // Bez dostupné motorky nesmí zákazník zírat na
                          // prázdný seznam — naveď ho na asistenční linku.
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: MotoGoColors.amberBg,
                              borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                            ),
                            child: Text(
                              '⚠️ ${t(context).tr('sosNoMotos')}\n📞 +420 774 256 271',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF78350F), height: 1.5),
                            ),
                          );
                        }
                        return Column(
                          children: motos.map((m) => _MotoOption(
                            moto: m,
                            selected: _selectedMoto?.id == m.id,
                            onTap: () => setState(() => _selectedMoto = m),
                          )).toList(),
                        );
                      },
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
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // CTA button — vždy zdarma
            Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              color: Colors.white,
              child: ElevatedButton(
                onPressed: _loading ? null : _confirm,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.check_circle, size: 18),
                        const SizedBox(width: 8),
                        Text(t(context).tr('confirmOrderFree')),
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
  final Motorcycle moto; final bool selected; final VoidCallback onTap;
  const _MotoOption({required this.moto, required this.selected, required this.onTap});

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
          Text(t(context).free,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
        ]),
      ),
    );
  }
}
