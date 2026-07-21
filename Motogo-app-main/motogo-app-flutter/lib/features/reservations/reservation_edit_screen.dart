import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_models.dart';
import '../booking/widgets/address_picker.dart';
import '../catalog/moto_model.dart';
import '../catalog/catalog_provider.dart';
import '../loyalty/loyalty_provider.dart';
import '../payment/payment_provider.dart';
import 'reservation_models.dart';
import 'reservation_edit_price_calc.dart';
import 'reservation_provider.dart';
import 'widgets/reservation_edit_widgets.dart';
import 'widgets/reservation_edit_confirm_page.dart';
import 'widgets/reservation_edit_moto_section.dart';
import 'widgets/reservation_edit_extras_section.dart';
import 'widgets/reservation_edit_calendar_section.dart';
import 'widgets/reservation_swap_section.dart';
import '../../core/currency.dart';

/// Edit upcoming reservation — compact single-page layout.
/// Calendar supports both extend and shorten in one view.
/// Moto change with ŘP validation. Price diff with payment gate.
class ReservationEditScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const ReservationEditScreen({super.key, required this.bookingId});

  @override
  ConsumerState<ReservationEditScreen> createState() => _EditState();
}

class _EditState extends ConsumerState<ReservationEditScreen> {
  String _tab = 'extend'; // 'extend' or 'shorten'
  String? _shortenDir; // 'start' or 'end' — direction for shortening (upcoming)
  DateTime? _newStart;
  DateTime? _newEnd;
  bool _saving = false;
  bool _motoExpanded = false;
  String? _newMotoId;
  String _pickupMethod = 'store';
  String _returnMethod = 'store';
  String _pickupTime = '09:00';
  String _returnTime = '19:00';
  double _pickupDelivFee = 0;
  double _returnDelivFee = 0;
  final Set<String> _selectedExtras = {};
  // Původní zaplacené doplňky (baseline) — přidání = doplatek, odebrání = refund.
  final Set<String> _origExtras = {};
  String? _helmetSize;
  String? _jacketSize;
  String? _pantsSize;
  String? _bootsSize;
  String? _glovesSize;
  String? _passengerHelmetSize;
  String? _passengerJacketSize;
  String? _passengerPantsSize;
  String? _passengerBootsSize;
  // „Mám vlastní výbavu" — skryje výběr velikostí základní výbavy řidiče a
  // přeskočí jejich povinnost při přistavení (UI-only, neukládá se do DB).
  bool _ownGear = false;
  DayPrices? _motoPrices;

  Reservation? _booking;
  bool _isActive = false;
  // Typ slevy ('percent'/'fixed') pro variantu B přepočtu ceny při úpravě.
  String? _discountType;

  // Confirmation page state — rendered inline (declaratively) so navigation
  // stays inside go_router. Imperative Navigator.push here would leave a
  // route go_router doesn't know about, freezing the back-to-reservations CTA.
  bool _confirmed = false;
  String _confirmTitle = '';
  String _confirmMessage = '';
  bool _confirmIsRefund = false;

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    final res = await ref.read(reservationByIdProvider(widget.bookingId).future);
    if (res != null && mounted) {
      setState(() {
        _booking = res;
        _isActive = res.displayStatus == ResStatus.aktivni;
        _newStart = res.startDate;
        _newEnd = res.endDate;
        _pickupMethod = res.pickupMethod;
        _returnMethod = res.returnMethod;
        _pickupTime = res.pickupTime ?? '09:00';
        _returnTime = res.returnTime ?? '19:00';
        _helmetSize = res.helmetSize;
        _jacketSize = res.jacketSize;
        _pantsSize = res.pantsSize;
        _bootsSize = res.bootsSize;
        _glovesSize = res.glovesSize;
        _passengerHelmetSize = res.passengerHelmetSize;
        _passengerJacketSize = res.passengerJacketSize;
        _passengerPantsSize = res.passengerPantsSize;
        _passengerBootsSize = res.passengerBootsSize;
      });
      _loadDiscountType(res);
      _loadOriginalExtras();
      // Load motorcycle per-day prices for accurate pricing
      if (res.motoId != null) {
        final motos = ref.read(motorcyclesProvider).valueOrNull ?? [];
        final moto = motos.where((m) => m.id == res.motoId).firstOrNull;
        if (moto?.prices != null && mounted) {
          setState(() => _motoPrices = moto!.prices);
        }
      }
    }
  }

  /// Varianta B: zjisti typ slevy rezervace pro přepočet ceny při úpravě.
  /// Voucher kódy v promo_codes nejsou → maybeSingle vrátí null → 'fixed'
  /// (konzervativní default, shodný se SQL helperem _booking_discount_type).
  Future<void> _loadDiscountType(Reservation res) async {
    if ((res.discountAmount ?? 0) <= 0) return;
    var type = 'fixed';
    final code = res.discountCode;
    if (code != null && code.isNotEmpty) {
      try {
        final row = await MotoGoSupabase.client
            .from('promo_codes')
            .select('type')
            .eq('code', code.toUpperCase())
            .maybeSingle();
        type = (row?['type'] as String?) ?? 'fixed';
      } catch (_) { /* fallback fixed */ }
    }
    if (mounted) setState(() => _discountType = type);
  }

  /// Kanonické názvy modelovaných doplňků (shodné s tím, co se vkládá do
  /// booking_extras) — slouží k jejich nahrazení (delete+insert) při úpravě.
  static const _modeledExtraNames = [
    'Výbava spolujezdce', 'Boty řidiče', 'Boty spolujezdce',
  ];
  static const _extraDefs = {
    'spolujezdec': ('Výbava spolujezdce', 690.0),
    'boty_ridic': ('Boty řidiče', 290.0),
    'boty_spolujezdec': ('Boty spolujezdce', 290.0),
  };

  /// Mapuje název řádku booking_extras na náš id doplňku.
  static String? _extraIdFromName(String name) {
    final n = name.toLowerCase();
    final hasBoots = n.contains('bot');
    final hasPass = n.contains('spoluj');
    if (hasBoots && hasPass) return 'boty_spolujezdec';
    if (hasBoots) return 'boty_ridic';
    if (hasPass) return 'spolujezdec';
    return null;
  }

  static bool _setEq(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// Načte původní zaplacené doplňky → předzaškrtne je a uloží jako baseline.
  Future<void> _loadOriginalExtras() async {
    try {
      final rows = await MotoGoSupabase.client
          .from('booking_extras')
          .select('name')
          .eq('booking_id', widget.bookingId);
      final orig = <String>{};
      for (final r in (rows as List)) {
        final id = _extraIdFromName((r['name'] ?? '').toString());
        if (id != null) orig.add(id);
      }
      if (mounted) {
        setState(() {
          _origExtras
            ..clear()
            ..addAll(orig);
          _selectedExtras
            ..clear()
            ..addAll(orig);
        });
      }
    } catch (_) {/* bez původních doplňků = prázdný baseline */}
  }

  /// Nahradí modelované řádky booking_extras aktuálním výběrem (delete + insert).
  Future<void> _replaceModeledExtras(List<Map<String, dynamic>>? rows) async {
    try {
      await MotoGoSupabase.client
          .from('booking_extras')
          .delete()
          .eq('booking_id', widget.bookingId)
          .inFilter('name', _modeledExtraNames);
      if (rows != null && rows.isNotEmpty) {
        await MotoGoSupabase.client.from('booking_extras').insert(rows);
      }
    } catch (e) {
      debugPrint('[Edit] extras replace failed: $e');
    }
  }

  EditPriceCalc get _calc {
    DayPrices? newMotoPrices;
    if (_newMotoId != null && _newMotoId != _booking!.motoId) {
      final motos = ref.read(motorcyclesProvider).valueOrNull ?? [];
      final newMoto = motos.where((m) => m.id == _newMotoId).firstOrNull;
      newMotoPrices = newMoto?.prices;
    }
    return EditPriceCalc(
      booking: _booking!,
      newStart: _newStart, newEnd: _newEnd,
      motoPrices: _motoPrices,
      newMotoId: _newMotoId,
      newMotoPrices: newMotoPrices,
      pickupDelivFee: _pickupDelivFee,
      returnDelivFee: _returnDelivFee,
      selectedExtras: _selectedExtras,
      origExtras: _origExtras,
      pickupMethod: _pickupMethod,
      returnMethod: _returnMethod,
      pickupTime: _pickupTime,
      returnTime: _returnTime,
      helmetSize: _helmetSize, jacketSize: _jacketSize, pantsSize: _pantsSize,
      bootsSize: _bootsSize, glovesSize: _glovesSize,
      passengerHelmetSize: _passengerHelmetSize,
      passengerJacketSize: _passengerJacketSize,
      passengerPantsSize: _passengerPantsSize,
      passengerBootsSize: _passengerBootsSize,
      discountType: _discountType,
      loyaltyLevel: ref.read(loyaltyStatusProvider).valueOrNull?.level ?? 0,
    );
  }

  String _fmt(DateTime? d) {
    if (d == null) return '–';
    return '${d.day}.${d.month}.${d.year}';
  }

  Widget _buildStornoWarning(BuildContext context) {
    final targetDate = _newEnd ?? _booking!.endDate;
    final pct = StornoCalc.refundPercent(targetDate);
    final Color bgColor;
    final Color textColor;
    final IconData icon;
    final String message;

    if (pct == 100) {
      bgColor = MotoGoColors.greenPale;
      textColor = MotoGoColors.greenDarker;
      icon = Icons.check_circle;
      message = t(context).tr('refund100');
    } else if (pct == 50) {
      bgColor = MotoGoColors.amberBg;
      textColor = const Color(0xFF92400E);
      icon = Icons.warning_amber_rounded;
      message = t(context).tr('refund50');
    } else {
      bgColor = MotoGoColors.redBg;
      textColor = MotoGoColors.red;
      icon = Icons.cancel;
      message = t(context).tr('refund0');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor)),
            ),
          ],
        ),
      ),
    );
  }

  String _getCalendarInstruction() {
    if (_tab == 'move') {
      return t(context).tr('moveInstruction');
    }
    if (_tab == 'extend') {
      if (_isActive) {
        return t(context).tr('clickDayAfterForExtend').replaceAll('{date}', '${_booking!.endDate.day}.${_booking!.endDate.month}.');
      }
      return t(context).tr('clickDayBeforeOrAfterForExtend').replaceAll('{startDate}', '${_booking!.startDate.day}.${_booking!.startDate.month}.').replaceAll('{endDate}', '${_booking!.endDate.day}.${_booking!.endDate.month}.');
    } else {
      if (_isActive) {
        return t(context).tr('clickNewReturnDay').replaceAll('{date}', '${_booking!.endDate.day}.${_booking!.endDate.month}.');
      }
      if (_shortenDir == null) {
        return t(context).tr('selectShortenDirection');
      }
      if (_shortenDir == 'start') {
        return t(context).tr('clickNewStartDay');
      }
      return t(context).tr('clickNewEndDay');
    }
  }

  /// Gear sizes required when the motorcycle is delivered (přistavení).
  /// Returns list of missing items — empty means OK.
  List<String> _missingGearSizes() {
    if (_pickupMethod != 'delivery' && _returnMethod != 'delivery') {
      return const [];
    }
    final missing = <String>[];
    // Základní výbava řidiče je volitelná PO KUSECH (parita s rezervačním
    // formulářem) — nevybraná velikost = kus nechce, uložení neblokuje.
    // Placené boty mají vlastní velikost (i u vlastní výbavy je nutná).
    if (_selectedExtras.contains('boty_ridic') && _bootsSize == null) {
      missing.add(t(context).tr('gearBootsDriver'));
    }
    if (_selectedExtras.contains('boty_spolujezdec') && _passengerBootsSize == null) {
      missing.add(t(context).tr('gearBootsPassenger'));
    }
    if (_selectedExtras.contains('spolujezdec')) {
      if (_passengerHelmetSize == null) missing.add(t(context).tr('gearHelmetPassenger'));
      if (_passengerJacketSize == null) missing.add(t(context).tr('gearJacketPassenger'));
      if (_passengerPantsSize == null) missing.add(t(context).tr('gearPantsPassenger'));
    }
    return missing;
  }

  /// True when the move tab has shifted the start date (length is preserved
  /// by construction, so a changed start = a real reschedule).
  bool get _moveChanged {
    if (_booking == null || _newStart == null) return false;
    final o = DateTime(_booking!.startDate.year, _booking!.startDate.month, _booking!.startDate.day);
    final n = DateTime(_newStart!.year, _newStart!.month, _newStart!.day);
    return o != n;
  }

  /// Free reschedule (Posun termínu): moves the whole reservation keeping the
  /// same number of days and the same price. Backend RPC validates overlaps and
  /// fires the booking_modified trigger (mail + updated contract).
  Future<void> _saveMove() async {
    if (_booking == null || _newStart == null || _newEnd == null || !_moveChanged) return;
    setState(() => _saving = true);
    try {
      final res = await MotoGoSupabase.client.rpc('reschedule_booking_free', params: {
        'p_booking_id': widget.bookingId,
        'p_new_start': _newStart!.toIso8601String().substring(0, 10),
        'p_new_end': _newEnd!.toIso8601String().substring(0, 10),
        'p_source': 'app',
      });
      final ok = res is Map && res['success'] == true;
      if (!ok) {
        final code = (res is Map ? res['error']?.toString() : null) ?? '';
        final msg = <String, String>{
          'moto_overlap': t(context).tr('moveOccupiedRange'),
          'customer_overlap': t(context).tr('moveErrCustomerOverlap'),
          'length_mismatch': t(context).tr('moveErrLength'),
          'past_date': t(context).tr('cannotSelectPast'),
        }[code] ?? t(context).error;
        if (mounted) showMotoGoToast(context, icon: '⚠️', title: t(context).error, message: msg);
        return;
      }
      if (mounted) {
        ref.invalidate(reservationsProvider);
        ref.invalidate(reservationByIdProvider(widget.bookingId));
        ref.invalidate(doorCodesProvider(widget.bookingId));
        _showConfirmation(
          title: t(context).tr('moveConfirmedTitle'),
          message: t(context).tr('moveConfirmed')
              .replaceAll('{start}', _fmt(_newStart))
              .replaceAll('{end}', _fmt(_newEnd)),
        );
      }
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_booking == null || _newStart == null || _newEnd == null) return;
    final calc = _calc;
    if (_newEnd!.isBefore(_newStart!)) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).error, message: t(context).tr('invalidDateRange'));
      return;
    }
    if (_isActive) {
      final origS = DateTime(_booking!.startDate.year, _booking!.startDate.month, _booking!.startDate.day);
      final newS = DateTime(_newStart!.year, _newStart!.month, _newStart!.day);
      if (origS != newS) {
        showMotoGoToast(context, icon: '⚠️', title: t(context).error, message: t(context).tr('cannotChangePickupActive'));
        return;
      }
    }
    final missingSizes = _missingGearSizes();
    if (missingSizes.isNotEmpty) {
      showMotoGoToast(context,
        icon: '⚠️',
        title: t(context).tr('missingGearSizesTitle'),
        message: '${t(context).tr('addOnDelivery')}: ${missingSizes.join(', ')}');
      return;
    }

    setState(() => _saving = true);
    final motoId = _newMotoId ?? _booking!.motoId;

    // Check availability
    if (motoId != null) {
      final ok = await checkMotoAvailability(motoId, _newStart!, _newEnd!, excludeBookingId: widget.bookingId);
      if (!ok && mounted) {
        setState(() => _saving = false);
        showMotoGoToast(context, icon: '⚠️', title: t(context).tr('occupiedTitle'), message: t(context).tr('motoOccupied'));
        return;
      }
    }

    try {
      final changes = <String, dynamic>{
        'end_date': _newEnd!.toIso8601String().substring(0, 10),
        'pickup_method': _pickupMethod,
        'return_method': _returnMethod,
        'pickup_time': _pickupTime,
        'return_time': _returnTime,
      };
      if (!_isActive) changes['start_date'] = _newStart!.toIso8601String().substring(0, 10);
      // Aktivní rezervace: motorka je zamčená (měnit lze jen konec, místo a
      // čas vrácení) — UI sekci skrývá, ale guard tu musí být i pro případ
      // rozjetého stavu (parita s webem).
      if (!_isActive && _newMotoId != null && _newMotoId != _booking!.motoId) {
        changes['moto_id'] = _newMotoId;
      }
      if (_helmetSize != _booking!.helmetSize) changes['helmet_size'] = _helmetSize;
      if (_jacketSize != _booking!.jacketSize) changes['jacket_size'] = _jacketSize;
      if (_pantsSize != _booking!.pantsSize) changes['pants_size'] = _pantsSize;
      if (_bootsSize != _booking!.bootsSize) changes['boots_size'] = _bootsSize;
      if (_glovesSize != _booking!.glovesSize) changes['gloves_size'] = _glovesSize;
      if (_passengerHelmetSize != _booking!.passengerHelmetSize) changes['passenger_helmet_size'] = _passengerHelmetSize;
      if (_passengerJacketSize != _booking!.passengerJacketSize) changes['passenger_jacket_size'] = _passengerJacketSize;
      if (_passengerPantsSize != _booking!.passengerPantsSize) changes['passenger_pants_size'] = _passengerPantsSize;
      if (_passengerBootsSize != _booking!.passengerBootsSize) changes['passenger_boots_size'] = _passengerBootsSize;

      // Varianta B: total i sleva po přepočtu slevy na nový obsah rezervace.
      changes['total_price'] = calc.newTotal;
      if ((_booking!.discountAmount ?? 0) > 0) {
        changes['discount_amount'] = calc.newDiscountAmount;
      }
      // Sleva 50 % na 1. den (pozdní vyzvednutí) — ulož přepočtenou hodnotu,
      // i 0 při ztrátě slevy (posun času před 12:00 / pod 2 dny). Posílá se jen
      // když je relevantní (= backend se sloupcem nasazen).
      if (calc.newLatePickup > 0 || calc.oldLatePickup > 0) {
        changes['late_pickup_discount_amount'] = calc.newLatePickup;
      }
      // Doprava: účtuje/vrací se rozdíl; nová kombinovaná fee se persistuje,
      // aby seděl rozpis KF (generate_final_invoice čte delivery_fee).
      if (calc.deliveryFeeDelta != 0) {
        changes['delivery_fee'] = calc.newDeliveryFee;
      }
      // Doplňky: účtuje/vrací se ROZDÍL vůči původně zaplaceným (přidání =
      // doplatek, odebrání = refund — řídí effectivePriceDiff). extrasRows =
      // celý nový stav modelovaných doplňků (delete+insert při uložení).
      // extras_price = původní + rozdíl (nezáporné). Při doplatku se aplikuje
      // až PO platbě (přes pendingEditChanges), jinak hned.
      List<Map<String, dynamic>>? extrasRows;
      final extrasChanged = !_setEq(_selectedExtras, _origExtras);
      if (extrasChanged) {
        extrasRows = [
          for (final id in _selectedExtras)
            if (_extraDefs[id] != null)
              {
                'booking_id': widget.bookingId,
                'name': _extraDefs[id]!.$1,
                'unit_price': _extraDefs[id]!.$2,
                'quantity': 1,
              },
        ];
        final newExtrasPrice = (_booking!.extrasPrice ?? 0) + calc.extrasDelta;
        changes['extras_price'] = newExtrasPrice < 0 ? 0.0 : newExtrasPrice;
      }

      // Build modification_history entry — tracks ALL changes:
      // dates, motorcycle, pickup/return method & address.
      final fmtD = (DateTime d) => d.toIso8601String().substring(0, 10);
      final datesChanged = calc.diffDays != 0;
      final motoChanged = _newMotoId != null && _newMotoId != _booking!.motoId;
      final pickupMethodChanged = _pickupMethod != _booking!.pickupMethod;
      final returnMethodChanged = _returnMethod != _booking!.returnMethod;
      // Always record history when any significant change occurs
      if (datesChanged || motoChanged || pickupMethodChanged || returnMethodChanged || calc.hasChanges) {
        // Store original dates on first-ever modification
        if (_booking!.originalStartDate == null) {
          changes['original_start_date'] = fmtD(_booking!.startDate);
          changes['original_end_date'] = fmtD(_booking!.endDate);
        }
        // Append to modification_history
        final hist = _booking!.modificationHistory.map((e) => e.toJson()).toList();
        final entry = <String, dynamic>{
          'at': DateTime.now().toIso8601String(),
          'from_start': fmtD(_booking!.startDate),
          'from_end': fmtD(_booking!.endDate),
          'to_start': fmtD(_newStart!),
          'to_end': fmtD(_newEnd!),
          'source': 'customer',
        };
        // Track motorcycle change
        if (motoChanged) {
          entry['from_moto'] = _booking!.motoName;
          final motos = ref.read(motorcyclesProvider).valueOrNull ?? [];
          final newMoto = motos.where((m) => m.id == _newMotoId).firstOrNull;
          entry['to_moto'] = newMoto?.model ?? _newMotoId!;
        }
        // Track pickup method/address change
        if (pickupMethodChanged) {
          entry['from_pickup_method'] = _booking!.pickupMethod;
          entry['to_pickup_method'] = _pickupMethod;
        }
        if (returnMethodChanged) {
          entry['from_return_method'] = _booking!.returnMethod;
          entry['to_return_method'] = _returnMethod;
        }
        // Track address changes (delivery addresses)
        if (_pickupMethod == 'delivery' && _booking!.pickupMethod == 'delivery' &&
            _booking!.pickupAddress != null) {
          // both delivery but address might change — track if different
          // (address is updated separately, here we note method change context)
        }
        hist.add(entry);
        changes['modification_history'] = hist;
      }

      // Účtuje/vrací se rozdíl PO slevě (varianta B) — effectivePriceDiff.
      final effDiff = calc.effectivePriceDiff;
      if (effDiff > 0) {
        // Needs extra payment — do NOT update booking yet.
        // Store pending changes; apply only after Stripe confirms payment.
        // Mirrors window._pendingEditChanges from Capacitor app.
        if (mounted) {
          ref.read(paymentContextProvider.notifier).state = PaymentContext(
            flowType: PaymentFlowType.extension,
            bookingId: widget.bookingId,
            amount: effDiff,
            label: t(context).tr('extensionSurcharge'),
            pendingEditChanges: {
              ...changes,
              // Při doplatku se doplňky aplikují až PO platbě. `_extras_replace`
              // říká, ať se modelované řádky nahradí (i odebrání), `_extras_rows`
              // je nový stav (může být i prázdný = vše odebráno).
              if (extrasChanged) '_extras_replace': true,
              if (extrasChanged) '_extras_rows': extrasRows ?? const [],
            },
          );
          context.push(Routes.payment);
        }
      } else {
        // effDiff <= 0 — zkrácení / levnější motorka / místo blíže
        // Při effDiff < 0 musíme nejdřív vystavit credit_note + Stripe refund
        // přes process-refund (jinak by KF nesedla na 0). UPDATE bookings až poté
        // (DB trigger trg_booking_modified_email pošle mail s diff + dobropisem).
        if (effDiff < 0) {
          try {
            final refundRes = await MotoGoSupabase.client.functions.invoke('process-refund', body: {
              'booking_id': widget.bookingId,
              'amount': -effDiff,
              'reason': 'edit_shortening',
            });
            // Realita > optimismus: process-refund vrací {success:bool,error}.
            // Když refund neproběhl (success != true / je error), NEUKLÁDÁME
            // změnu a NEhlásíme úspěch — jinak by appka tvrdila vrácení, které
            // se nestalo.
            final rd = refundRes.data;
            final refundOk = rd is Map && rd['success'] == true;
            if (!refundOk) {
              final msg = (rd is Map && rd['error'] != null)
                  ? rd['error'].toString()
                  : t(context).tr('refundFailedRetry');
              if (mounted) showMotoGoToast(context, icon: '✗',
                title: t(context).error, message: msg);
              return;
            }
          } catch (e) {
            if (mounted) showMotoGoToast(context, icon: '✗',
              title: t(context).error,
              message: 'Refund failed: $e');
            return;
          }
        }
        // No surcharge or refund — save directly
        await MotoGoSupabase.client.from('bookings').update(changes).eq('id', widget.bookingId);
        // Nahraď modelované doplňky novým stavem (přidané vlož, odebrané smaž).
        if (extrasChanged) {
          await _replaceModeledExtras(extrasRows);
        }
        if (mounted) {
          ref.invalidate(reservationsProvider);
          ref.invalidate(reservationByIdProvider(widget.bookingId));
          ref.invalidate(doorCodesProvider(widget.bookingId));
          _showConfirmation(
            title: effDiff < 0 ? t(context).tr('shorteningConfirmed') : t(context).tr('changesSavedTitle'),
            message: effDiff < 0
                ? '${t(context).tr('reservationShortened')}\n${t(context).tr('refundAmount').replaceAll('{amount}', '${(-effDiff).toStringAsFixed(0)}').replaceAll('{percent}', '${StornoCalc.refundPercent(_newEnd ?? _booking!.endDate)}')}\n${t(context).tr('refundToOriginalMethod')}'
                : '${t(context).tr('changesSaved')}\n${t(context).tr('reservationRange').replaceAll('{start}', _fmt(_newStart)).replaceAll('{end}', _fmt(_newEnd))}',
            isRefund: effDiff < 0,
          );
        }
      }
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _showConfirmation({required String title, required String message, bool isRefund = false}) {
    // Render the confirmation page inline (see _confirmed in build) instead of
    // an imperative Navigator.pushReplacement — keeps the "back to reservations"
    // CTA working under go_router.
    setState(() {
      _confirmed = true;
      _confirmTitle = title;
      _confirmMessage = message;
      _confirmIsRefund = isRefund;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed) {
      return EditConfirmPage(
        title: _confirmTitle,
        message: _confirmMessage,
        isRefund: _confirmIsRefund,
      );
    }
    if (_booking == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: MotoGoColors.green)));
    }
    final calc = _calc;
    final bookedAsync = ref.watch(bookedDatesProvider(_booking!.motoId ?? ''));
    final profile = ref.watch(profileProvider);
    final userLicense = profile.valueOrNull?['license_type'] as String?;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // === HEADER ===
          Container(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 14),
            decoration: const BoxDecoration(color: MotoGoColors.dark, borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(onTap: () => context.backOr(Routes.reservations),
                  child: Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.arrow_back, size: 18, color: Colors.black))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t(context).tr('editReservation'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text('${_booking!.motoName} · ${_booking!.shortId}',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                ])),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)),
                  child: Text('${_fmt(_booking!.startDate)} – ${_fmt(_booking!.endDate)}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black))),
                const SizedBox(width: 8),
                Text('${_isActive ? t(context).active : t(context).upcoming} · ${calc.origDays} ${calc.origDays == 1 ? t(context).tr("day1") : calc.origDays < 5 ? t(context).tr("days24") : t(context).tr("days5")}',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
              ]),
            ]),
          ),

          // === TABY ===
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              EditTabBtn(label: t(context).tr('extendChangePlace'), active: _tab == 'extend',
                onTap: () => setState(() { _tab = 'extend'; _shortenDir = null; _newStart = _booking!.startDate; _newEnd = _booking!.endDate; })),
              const SizedBox(width: 6),
              EditTabBtn(label: t(context).tr('shortenChangePlace'), active: _tab == 'shorten',
                onTap: () => setState(() { _tab = 'shorten'; _shortenDir = null; _newStart = _booking!.startDate; _newEnd = _booking!.endDate; })),
              // Posun termínu zdarma — jen nadcházející a zaplacené (jako web).
              if (!_isActive &&
                  _booking!.displayStatus == ResStatus.nadchazejici &&
                  _booking!.paymentStatus == 'paid') ...[
                const SizedBox(width: 6),
                EditTabBtn(label: t(context).tr('moveChangePlace'), active: _tab == 'move',
                  onTap: () => setState(() { _tab = 'move'; _shortenDir = null; _newStart = _booking!.startDate; _newEnd = _booking!.endDate; })),
              ],
              // Výměna motorky uprostřed rezervace — reserved/active + zaplaceno.
              if ((_booking!.status == 'reserved' || _booking!.status == 'active') &&
                  _booking!.paymentStatus == 'paid') ...[
                const SizedBox(width: 6),
                EditTabBtn(label: t(context).tr('swap.tab'), active: _tab == 'swap',
                  onTap: () => setState(() { _tab = 'swap'; _shortenDir = null; _newStart = _booking!.startDate; _newEnd = _booking!.endDate; })),
              ],
            ])),

          // === VÝMĚNA MOTORKY UPROSTŘED REZERVACE ===
          if (_tab == 'swap')
            SwapMotoSection(
              booking: _booking!,
              userLicense: userLicense,
              onSwapped: (swapDate, swapTime, newMotoName) {
                ref.invalidate(reservationsProvider);
                ref.invalidate(reservationByIdProvider(widget.bookingId));
                ref.invalidate(doorCodesProvider(widget.bookingId));
                ref.invalidate(bookedDatesProvider(_booking!.motoId ?? ''));
                _showConfirmation(
                  title: t(context).tr('swap.successTitle'),
                  message: t(context).tr('swap.success')
                      .replaceAll('{date}', _fmt(swapDate))
                      .replaceAll('{time}', swapTime)
                      .replaceAll('{moto}', newMotoName),
                );
              },
            ),

          // === TERMÍN ===
          if (_tab != 'swap')
          EditCalendarSection(
            tab: _tab,
            isActive: _isActive,
            origStart: _booking!.startDate,
            origEnd: _booking!.endDate,
            newStart: _newStart,
            newEnd: _newEnd,
            diffDays: calc.diffDays,
            shortenDir: _shortenDir,
            calendarInstruction: _getCalendarInstruction(),
            motoName: _booking!.motoName,
            shortId: _booking!.shortId,
            bookedDates: bookedAsync.valueOrNull ?? <BookedDateRange>[],
            onDatesChanged: (s, e) => setState(() { _newStart = s; _newEnd = e; }),
            onError: (msg) => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), duration: const Duration(seconds: 2))),
            onShortenStart: () => setState(() { _shortenDir = 'start'; _newStart = _booking!.startDate; _newEnd = _booking!.endDate; }),
            onShortenEnd: () => setState(() { _shortenDir = 'end'; _newStart = _booking!.startDate; _newEnd = _booking!.endDate; }),
          ),

          // === POSUN ZDARMA — info banner ===
          if (_tab == 'move')
            Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: MotoGoColors.green, width: 1)),
                child: Row(children: [
                  const Icon(Icons.swap_horiz, size: 18, color: MotoGoColors.greenDarker),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t(context).tr('moveFreeNote'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker))),
                ]))),

          // === PŘISTAVENÍ MOTORKY (only for upcoming) ===
          if (!_isActive && _tab != 'move' && _tab != 'swap')
            EditCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.motorcycle, size: 16, color: MotoGoColors.greenDark),
                const SizedBox(width: 6),
                Text(t(context).tr('pickupMotorcycle'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              ]),
              const SizedBox(height: 8),
              AddressPickerWidget(label: t(context).pickup, method: _pickupMethod,
                onMethodChanged: (m) => setState(() => _pickupMethod = m),
                onAddressChanged: (_) {},
                onDeliveryFeeChanged: (f) => setState(() => _pickupDelivFee = f)),
              const SizedBox(height: 8),
              EditTimePicker(label: t(context).tr('pickupTimeEdit'), value: _pickupTime,
                onChanged: (v) => setState(() => _pickupTime = v)),
            ])),

          // === VRÁCENÍ MOTORKY ===
          if (_tab != 'move' && _tab != 'swap')
            EditCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.assignment_return, size: 16, color: MotoGoColors.greenDark),
              const SizedBox(width: 6),
              Text(t(context).tr('returnMotorcycle'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            ]),
            const SizedBox(height: 8),
            AddressPickerWidget(label: t(context).returnLabel, method: _returnMethod,
              onMethodChanged: (m) => setState(() => _returnMethod = m),
              onAddressChanged: (_) {},
              onDeliveryFeeChanged: (f) => setState(() => _returnDelivFee = f)),
            const SizedBox(height: 8),
            EditTimePicker(label: t(context).tr('returnTimeEdit'), value: _returnTime,
              onChanged: (v) => setState(() => _returnTime = v)),
          ])),

          // === ZMĚNA MOTORKY (collapsible, only for upcoming) ===
          if (!_isActive && _tab != 'move' && _tab != 'swap')
            EditMotoChangeSection(
              currentMotoName: _booking!.motoName,
              currentMotoId: _booking!.motoId,
              newMotoId: _newMotoId,
              expanded: _motoExpanded,
              userLicense: userLicense,
              onMotoSelected: (id) => setState(() => _newMotoId = id),
              onToggleExpanded: () => setState(() => _motoExpanded = !_motoExpanded),
            ),

          // === DOPLŇKY (only for upcoming) ===
          if (!_isActive && _tab != 'move' && _tab != 'swap')
            EditExtrasSection(
              selectedExtras: _selectedExtras,
              pickupMethod: _pickupMethod,
              returnMethod: _returnMethod,
              isKids: _booking!.motoLicenseRequired == 'N',
              ownGear: _ownGear,
              loyaltyLevel: ref.watch(loyaltyStatusProvider).valueOrNull?.level ?? 0,
              helmetSize: _helmetSize, jacketSize: _jacketSize, pantsSize: _pantsSize,
              bootsSize: _bootsSize, glovesSize: _glovesSize,
              passengerHelmetSize: _passengerHelmetSize,
              passengerJacketSize: _passengerJacketSize,
              passengerPantsSize: _passengerPantsSize,
              passengerBootsSize: _passengerBootsSize,
              onExtrasChanged: (extras) => setState(() { _selectedExtras.clear(); _selectedExtras.addAll(extras); }),
              onOwnGearChanged: (v) => setState(() => _ownGear = v),
              onHelmetSize: (s) => setState(() => _helmetSize = s),
              onJacketSize: (s) => setState(() => _jacketSize = s),
              onPantsSize: (s) => setState(() => _pantsSize = s),
              onBootsSize: (s) => setState(() => _bootsSize = s),
              onGlovesSize: (s) => setState(() => _glovesSize = s),
              onPassengerHelmetSize: (s) => setState(() => _passengerHelmetSize = s),
              onPassengerJacketSize: (s) => setState(() => _passengerJacketSize = s),
              onPassengerPantsSize: (s) => setState(() => _passengerPantsSize = s),
              onPassengerBootsSize: (s) => setState(() => _passengerBootsSize = s),
            ),

          // === STORNO NOTE (shorten tab) ===
          if (_tab == 'shorten') ...[
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: MotoGoColors.amberBg, borderRadius: BorderRadius.circular(10)),
                child: Text('${t(context).tr('stornoConditions')} ${t(context).tr('stornoRules')}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF92400E))))),
            // Dynamic storno warning when date is selected
            if (calc.diffDays < 0) _buildStornoWarning(context),
          ],

          // === CENOVÝ PŘEHLED ===
          if (calc.hasChanges && _tab != 'move' && _tab != 'swap')
            EditCard(child: Column(children: [
              EditPriceRow(t(context).tr('originalPrice'), '${Money.czk(_booking!.totalPrice)}'),
              EditPriceRow(t(context).tr('originalDuration'), '${calc.origDays} ${calc.origDays == 1 ? t(context).tr("day1") : calc.origDays < 5 ? t(context).tr("days24") : t(context).tr("days5")}'),
              if (calc.diffDays != 0) EditPriceRow(t(context).tr('newDuration'), '${calc.newDays} ${calc.newDays == 1 ? t(context).tr("day1") : calc.newDays < 5 ? t(context).tr("days24") : t(context).tr("days5")}'),
              if (calc.diffDays > 0) EditPriceRow('${t(context).tr('extensionLabel')} (+${calc.diffDays} ${calc.diffDays == 1 ? t(context).tr("day1") : calc.diffDays < 5 ? t(context).tr("days24") : t(context).tr("days5")})',
                '+${Money.czk(calc.dateChangeAmount)}'),
              if (calc.diffDays < 0) EditPriceRow('${t(context).tr('shorteningLabel')} (${calc.diffDays.abs()} ${calc.diffDays.abs() == 1 ? t(context).tr("day1") : calc.diffDays.abs() < 5 ? t(context).tr("days24") : t(context).tr("days5")})',
                '-${Money.czk(calc.dateChangeAmount.abs())}'),
              // Doprava: účtuje/vrací se ROZDÍL oproti původní rezervaci
              if (calc.deliveryFeeDelta != 0)
                EditPriceRow(
                  '${t(context).tr('pickupDeliveryLabel')} / ${t(context).tr('returnDeliveryLabel')}',
                  '${calc.deliveryFeeDelta > 0 ? "+" : "−"}${Money.czk(calc.deliveryFeeDelta.abs())}'),
              if (calc.extrasTotal > 0) EditPriceRow(t(context).tr('addons'), '+${Money.czk(calc.extrasTotal)}'),
              // Sleva se přepočítává na nový obsah rezervace (varianta B) —
              // řádek ukazuje úpravu slevy, finální Doplatek/Vrácení je PO slevě.
              if ((_booking!.discountAmount ?? 0) > 0 && calc.newDiscountAmount != (_booking!.discountAmount ?? 0))
                EditPriceRow(t(context).tr('discountLabel'),
                  '${(_booking!.discountAmount ?? 0).toStringAsFixed(0)} → ${Money.czk(calc.newDiscountAmount)}'),
              const Divider(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(calc.effectivePriceDiff > 0 ? t(context).tr('surcharge') : calc.effectivePriceDiff < 0 ? t(context).tr('refundLabel') : t(context).tr('differenceLabel'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                Text('${calc.effectivePriceDiff > 0 ? "+" : ""}${Money.czk(calc.effectivePriceDiff)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                    color: calc.effectivePriceDiff > 0 ? MotoGoColors.red : calc.effectivePriceDiff < 0 ? MotoGoColors.greenDarker : MotoGoColors.black)),
              ]),
              if (calc.effectivePriceDiff < 0 && calc.diffDays < 0)
                Padding(padding: const EdgeInsets.only(top: 4),
                  child: Text('${t(context).tr('stornoRefundPercent').replaceAll('{percent}', '${StornoCalc.refundPercent(_newEnd ?? _booking!.endDate)}')}',
                    style: const TextStyle(fontSize: 10, color: MotoGoColors.g400))),
            ])),

          // === MISSING SIZES WARNING (přistavení) ===
          if (_tab != 'move' && _tab != 'swap' && _missingGearSizes().isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9E6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD54F))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFF92400E)),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t(context).tr('fillGearSizesOnDelivery'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                    const SizedBox(height: 2),
                    Text('${t(context).tr('missingLabel')}: ${_missingGearSizes().join(', ')}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF92400E))),
                  ])),
                ]))),

          // === CTA BUTTON (swap má vlastní tlačítko v sekci) ===
          if (_tab != 'swap')
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(height: 52, child: PressableScale(
              enabled: !_saving,
              child: ElevatedButton(
              onPressed: _tab == 'move'
                  ? ((!_saving && _moveChanged) ? _saveMove : null)
                  : ((!_saving && calc.hasChanges && _missingGearSizes().isEmpty) ? _save : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: MotoGoColors.green, foregroundColor: Colors.black,
                disabledBackgroundColor: MotoGoColors.g200,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_tab == 'move'
                          ? t(context).tr('moveSaveBtn')
                          : (calc.effectivePriceDiff > 0
                              ? '${t(context).tr('proceedToPayment')} (+${Money.czk(calc.effectivePriceDiff)})'
                              : t(context).tr('saveChangesBtn')),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                      const SizedBox(width: 6), const Icon(Icons.arrow_forward, size: 16),
                    ]),
            )))),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
