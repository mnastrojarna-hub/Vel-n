import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/currency.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/supabase_client.dart';
import '../../auth/widgets/toast_helper.dart';
import '../../catalog/moto_model.dart';
import '../../catalog/catalog_provider.dart';
import '../../booking/booking_validator.dart';
import '../../payment/payment_provider.dart';
import '../reservation_models.dart';
import 'reservation_edit_widgets.dart';

/// Výměna motorky uprostřed rezervace.
/// Zákazník od zvoleného data (a času) přejede na novou motorku. Na pozadí vznikne
/// DRUHÁ navazující rezervace na novou motorku (RPC split_booking_moto_swap) —
/// tu je potřeba zaplatit (dokončí se z přehledu rezervací); nevyužité dny původní
/// motorky se po zaplacení vrátí. Switch proběhne předávacím protokolem na pobočce.
class SwapMotoSection extends ConsumerStatefulWidget {
  final Reservation booking;
  final String? userLicense;

  /// Volá se po úspěšné výměně — parent zobrazí potvrzení / refresh.
  final void Function(DateTime swapDate, String swapTime, String newMotoName) onSwapped;

  const SwapMotoSection({
    super.key,
    required this.booking,
    required this.userLicense,
    required this.onSwapped,
  });

  @override
  ConsumerState<SwapMotoSection> createState() => _SwapMotoSectionState();
}

class _SwapMotoSectionState extends ConsumerState<SwapMotoSection> {
  DateTime? _swapDate;
  String _swapTime = '09:00';
  String? _newMotoId;
  bool _saving = false;

  // Dostupnost kandidátních motorek od data výměny do konce rezervace.
  // motoId -> volná? (null = ještě nezjištěno / počítá se).
  final Map<String, bool> _avail = {};
  bool _availLoading = false;
  bool _availInit = false;
  int _availToken = 0; // proti zápisu zastaralého výsledku při rychlé změně data

  // Náhled cenového rozdílu (net z dry-run): >0 doplatek, <0 vratka, 0 beze změny.
  double? _net;
  bool _netLoading = false;
  int _netToken = 0;

  DateTime get _rangeStart {
    final b = widget.booking.startDate;
    final start = DateTime(b.year, b.month, b.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // U probíhající rezervace nelze měnit do minulosti — nejdříve dnes.
    return start.isBefore(today) ? today : start;
  }

  DateTime get _rangeEnd {
    final b = widget.booking.endDate;
    return DateTime(b.year, b.month, b.day);
  }

  @override
  void initState() {
    super.initState();
    _swapTime = widget.booking.pickupTime ?? '09:00';
    // Default: den po začátku dostupného rozsahu (výměna „uprostřed"),
    // clamp do rozsahu; u jednodenního rozsahu = první den.
    final first = _rangeStart;
    var d = first.add(const Duration(days: 1));
    if (d.isAfter(_rangeEnd)) d = first;
    _swapDate = d;
  }

  bool _licenseOk(Motorcycle m) {
    final lic = widget.userLicense;
    if (lic == null) return true;
    return BookingValidator.checkLicense(
          userLicenseGroups: [lic],
          motoLicenseGroups: m.licenseGroupsOrFallback,
        ) ==
        null;
  }

  /// Kandidáti = active/maintenance motorky (motorcyclesProvider), bez aktuální,
  /// filtr dle ŘP zákazníka.
  List<Motorcycle> _candidates(List<Motorcycle> motos) => motos
      .where((m) => m.id != widget.booking.motoId)
      .where(_licenseOk)
      .toList();

  /// Přepočítá dostupnost všech kandidátů od data výměny do konce rezervace.
  Future<void> _recomputeAvail(List<Motorcycle> motos) async {
    final date = _swapDate;
    if (date == null) return;
    final token = ++_availToken;
    setState(() => _availLoading = true);
    final cands = _candidates(motos);
    final results = await Future.wait(cands.map((m) => checkMotoAvailability(
          m.id,
          date,
          _rangeEnd,
          excludeBookingId: widget.booking.id,
        )));
    if (!mounted || token != _availToken) return;
    final map = <String, bool>{};
    for (var i = 0; i < cands.length; i++) {
      map[cands[i].id] = results[i];
    }
    setState(() {
      _avail
        ..clear()
        ..addAll(map);
      _availLoading = false;
    });
  }

  /// Náhled cenového rozdílu pro zvolené datum + motorku (server-side dry-run,
  /// stejná RPC jako potvrzení — zahrnuje i věrnostní slevu). Nic nezapisuje.
  Future<void> _recomputeNet() async {
    final date = _swapDate;
    final motoId = _newMotoId;
    final token = ++_netToken;
    if (date == null || motoId == null) {
      setState(() { _net = null; _netLoading = false; });
      return;
    }
    setState(() { _net = null; _netLoading = true; });
    try {
      final res = await MotoGoSupabase.client.rpc('split_booking_moto_swap', params: {
        'p_booking_id': widget.booking.id,
        'p_new_moto_id': motoId,
        'p_swap_date': date.toIso8601String().substring(0, 10),
        'p_swap_time': _swapTime,
        'p_dry_run': true,
      });
      if (!mounted || token != _netToken) return;
      setState(() {
        _net = (res is Map && res['success'] == true) ? ((res['net'] as num?)?.toDouble() ?? 0) : null;
        _netLoading = false;
      });
    } catch (_) {
      if (mounted && token == _netToken) setState(() => _netLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _swapDate ?? _rangeStart,
      firstDate: _rangeStart,
      lastDate: _rangeEnd,
      helpText: t(context).tr('swap.pickDate'),
    );
    if (picked != null && mounted) {
      setState(() {
        _swapDate = DateTime(picked.year, picked.month, picked.day);
        _newMotoId = null; // dostupnost se změnou data přepočítá
      });
      _recomputeNet(); // reset náhledu ceny (motorka zrušena)
      final motos = ref.read(motorcyclesProvider).valueOrNull;
      if (motos != null) _recomputeAvail(motos);
    }
  }

  bool _rpcOk(dynamic res) => res is Map && res['success'] == true;

  /// Namapuje chybový kód RPC na hlášku a zobrazí toast.
  void _showSwapError(dynamic res) {
    if (!mounted) return;
    final code = (res is Map ? res['error']?.toString() : null) ?? '';
    final msg = <String, String>{
          'not_found': t(context).tr('swap.err.notFound'),
          'forbidden': t(context).tr('swap.err.forbidden'),
          'wrong_status': t(context).tr('swap.err.wrongStatus'),
          'not_paid': t(context).tr('swap.err.notPaid'),
          'invalid_new_moto': t(context).tr('swap.err.invalidMoto'),
          'swap_date_out_of_range': t(context).tr('swap.err.dateRange'),
          'already_split': t(context).tr('swap.err.alreadySplit'),
          'new_moto_unavailable': t(context).tr('swap.err.unavailable'),
        }[code] ??
        t(context).error;
    showMotoGoToast(context, icon: '⚠️', title: t(context).error, message: msg);
  }

  /// Dvoukrokový flow výměny — POŘADÍ: dry-run → vypořádání net → COMMIT.
  ///  1) `p_dry_run:true` zjistí `net` (kolik zákazník doplatí >0 / dostane <0), nic nezapíše.
  ///  2) net>0 → doplatek přes STÁVAJÍCÍ edit-platbu (extension) a COMMIT až PO úspěšné platbě
  ///     (řeší payment_screen přes speciální klíč `_swap_commit`); net<0 → refund na PŮVODNÍ
  ///     rezervaci přes edge `process-refund` PŘED commitem; net==0 → rovnou commit.
  ///  3) `p_dry_run:false` = COMMIT — server zkrátí původní, vytvoří druhou (paid) rezervaci
  ///     a sám rozešle její „reserved" mail + smlouvu. COMMIT platbu ANI refund nedělá.
  Future<void> _confirm() async {
    final date = _swapDate;
    final motoId = _newMotoId;
    if (date == null || motoId == null || _saving) return;
    setState(() => _saving = true);
    final swapDateStr = date.toIso8601String().substring(0, 10);
    final swapParams = <String, dynamic>{
      'p_booking_id': widget.booking.id,
      'p_new_moto_id': motoId,
      'p_swap_date': swapDateStr,
      'p_swap_time': _swapTime,
    };
    try {
      // 1) DRY RUN — spočítej net, nic nezapisuj.
      final dry = await MotoGoSupabase.client.rpc('split_booking_moto_swap', params: {
        ...swapParams,
        'p_dry_run': true,
      });
      if (!_rpcOk(dry)) {
        _showSwapError(dry);
        return;
      }
      final net = (dry is Map ? (dry['net'] as num?)?.toDouble() : null) ?? 0;

      // 2a) DOPLATEK (net>0) — přes stávající edit-platbu (extension). COMMIT provede
      // payment_screen po úspěšné platbě (klíč `_swap_commit`), NIKDY před ní.
      if (net > 0.5) {
        if (!mounted) return;
        final motos = ref.read(motorcyclesProvider).valueOrNull ?? const [];
        final newMoto = motos.where((m) => m.id == motoId).firstOrNull;
        ref.read(paymentContextProvider.notifier).state = PaymentContext(
          flowType: PaymentFlowType.extension,
          bookingId: widget.booking.id,
          amount: net,
          label: t(context).tr('swap.surchargeLabel'),
          pendingEditChanges: {
            // Nese parametry pro server-side COMMIT po zaplacení doplatku.
            // NEobsahuje žádné bookings sloupce → payment_screen nepošle `change`
            // do Stripe metadat a webhook původní rezervaci nezmění.
            '_swap_commit': {
              ...swapParams,
              'new_moto_name': newMoto?.model ?? '',
              'swap_date': swapDateStr,
              'swap_time': _swapTime,
            },
          },
        );
        context.push(Routes.payment);
        return;
      }

      // 2b) VRÁCENÍ (net<0) — refund na PŮVODNÍ rezervaci PŘED commitem. Když selže, NEcommituj.
      if (net < -0.5) {
        final refundRes = await MotoGoSupabase.client.functions.invoke('process-refund', body: {
          'booking_id': widget.booking.id,
          'amount': -net,
          'reason': 'moto_swap',
        });
        final rd = refundRes.data;
        final refundOk = rd is Map && rd['success'] == true;
        if (!refundOk) {
          final msg = (rd is Map && rd['error'] != null)
              ? rd['error'].toString()
              : t(context).tr('refundFailedRetry');
          if (mounted) {
            showMotoGoToast(context, icon: '✗', title: t(context).error, message: msg);
          }
          return;
        }
      }

      // 3) COMMIT — net (<=0) je vypořádán, teprve teď zapiš.
      final commit = await MotoGoSupabase.client.rpc('split_booking_moto_swap', params: {
        ...swapParams,
        'p_dry_run': false,
      });
      if (!_rpcOk(commit)) {
        _showSwapError(commit);
        return;
      }
      if (mounted) {
        final motos = ref.read(motorcyclesProvider).valueOrNull ?? const [];
        final newMoto = motos.where((m) => m.id == motoId).firstOrNull;
        widget.onSwapped(date, _swapTime, newMoto?.model ?? '');
      }
    } catch (e) {
      if (mounted) {
        showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmt(DateTime? d) => d == null ? '–' : '${d.day}.${d.month}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final motosAsync = ref.watch(motorcyclesProvider);

    // První načtení dostupnosti po dodání seznamu motorek.
    final motosData = motosAsync.valueOrNull;
    if (motosData != null && !_availInit) {
      _availInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recomputeAvail(motosData);
      });
    }

    final canConfirm = !_saving && _swapDate != null && _newMotoId != null;

    return Column(children: [
      // === INFO / CENA ===
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MotoGoColors.greenPale,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MotoGoColors.green, width: 1),
          ),
          child: Row(children: [
            const Icon(Icons.sync_alt, size: 18, color: MotoGoColors.greenDarker),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t(context).tr('swap.priceNote'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker))),
          ]),
        ),
      ),

      // === DATUM + ČAS VÝMĚNY ===
      EditCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.event, size: 16, color: MotoGoColors.dark),
            const SizedBox(width: 6),
            Text(t(context).tr('swap.title'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          ]),
          const SizedBox(height: 4),
          Text(t(context).tr('swap.subtitle'),
              style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
          const SizedBox(height: 8),
          // Rozsah rezervace pro orientaci.
          Text(
            '${t(context).tr('swap.rangeLabel')}: ${_fmt(widget.booking.startDate)} – ${_fmt(widget.booking.endDate)}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MotoGoColors.greenDark),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MotoGoColors.green, width: 1.5),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_month, size: 18, color: MotoGoColors.greenDarker),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t(context).tr('swap.pickDate'),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark)),
                  Text(_fmt(_swapDate),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                ])),
                const Icon(Icons.edit_calendar, size: 18, color: MotoGoColors.greenDark),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          EditTimePicker(
            label: t(context).tr('swap.pickTime'),
            value: _swapTime,
            onChanged: (v) => setState(() => _swapTime = v),
          ),
        ]),
      ),

      // === NOVÁ MOTORKA ===
      EditCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.motorcycle, size: 16, color: MotoGoColors.greenDark),
            const SizedBox(width: 6),
            Expanded(
                child: Text(t(context).tr('swap.pickMoto'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
            if (_availLoading)
              const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.green)),
          ]),
          const SizedBox(height: 4),
          Text(
            '${t(context).tr('currentMoto')}: ${widget.booking.motoName}',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: MotoGoColors.g400),
          ),
          const SizedBox(height: 8),
          motosAsync.when(
            data: (motos) {
              final cands = _candidates(motos);
              if (cands.isEmpty) {
                return Text(t(context).tr('swap.noMoto'),
                    style: const TextStyle(fontSize: 12, color: MotoGoColors.g400));
              }
              return Column(
                children: cands.map((m) {
                  final free = _avail[m.id];
                  final selectable = free == true;
                  final selected = _newMotoId == m.id;
                  return GestureDetector(
                    onTap: selectable
                        ? () {
                            setState(() => _newMotoId = selected ? null : m.id);
                            _recomputeNet();
                          }
                        : null,
                    child: Opacity(
                      opacity: (free == false) ? 0.45 : 1,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selected ? MotoGoColors.greenPale : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: selected ? MotoGoColors.green : MotoGoColors.g200, width: selected ? 2 : 1),
                        ),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: m.displayImage.isNotEmpty
                                ? MgImage(m.displayImage,
                                    thumbWidth: 150,
                                    width: 48,
                                    height: 36,
                                    fit: BoxFit.cover,
                                    error: Container(width: 48, height: 36, color: MotoGoColors.g200))
                                : Container(width: 48, height: 36, color: MotoGoColors.g200),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.model,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                            Text(
                              '${m.licenseGroupsOrFallback.where((g) => g != 'N').join(' / ').isEmpty ? '–' : m.licenseGroupsOrFallback.where((g) => g != 'N').join(' / ')} · ${m.priceLabel}/den',
                              style: const TextStyle(fontSize: 10, color: MotoGoColors.g400),
                            ),
                          ])),
                          const SizedBox(width: 6),
                          if (free == false)
                            Text(t(context).tr('swap.occupied'),
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.red))
                          else if (free == null && _availLoading)
                            const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.green))
                          else if (free == true)
                            const Icon(Icons.check_circle, size: 18, color: MotoGoColors.greenDarker),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
            error: (_, __) =>
                Text(t(context).tr('loadingError'), style: const TextStyle(color: MotoGoColors.red)),
          ),
        ]),
      ),

      // === CENOVÝ ROZDÍL (živý náhled z dry-run — doplatek / vratka) ===
      if (_newMotoId != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MotoGoColors.greenPale,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MotoGoColors.green, width: 1.5),
            ),
            child: Row(children: [
              Icon(
                _net == null
                    ? Icons.payments
                    : _net! > 0.5
                        ? Icons.add_card
                        : _net! < -0.5
                            ? Icons.savings
                            : Icons.check_circle,
                size: 18,
                color: MotoGoColors.greenDarker,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _net == null
                      ? t(context).tr('swap.net.title')
                      : _net! > 0.5
                          ? t(context).tr('swap.net.surcharge')
                          : _net! < -0.5
                              ? t(context).tr('swap.net.refund')
                              : t(context).tr('swap.net.same'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker),
                ),
              ),
              if (_netLoading)
                const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.green))
              else if (_net != null && _net!.abs() > 0.5)
                Text(
                  '${_net! > 0 ? '+' : '−'}${Money.czk(_net!.abs())}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: MotoGoColors.black),
                ),
            ]),
          ),
        ),

      // === POTVRDIT ===
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: canConfirm ? _confirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: MotoGoColors.green,
              foregroundColor: Colors.black,
              disabledBackgroundColor: MotoGoColors.g200,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(t(context).tr('swap.confirm'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward, size: 16),
                  ]),
          ),
        ),
      ),
    ]);
  }
}
