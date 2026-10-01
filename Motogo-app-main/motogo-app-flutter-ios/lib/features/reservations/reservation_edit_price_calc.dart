import 'dart:math' as math;

import '../booking/booking_models.dart';
import '../catalog/moto_model.dart';
import 'reservation_models.dart';
import '../../core/date_days.dart';

/// Pure price calculation logic for reservation editing.
class EditPriceCalc {
  final Reservation booking;
  final DateTime? newStart;
  final DateTime? newEnd;
  final DayPrices? motoPrices;
  final String? newMotoId;
  final DayPrices? newMotoPrices;
  final double pickupDelivFee;
  final double returnDelivFee;
  final Set<String> selectedExtras;
  /// Původně zaplacené doplňky — účtuje/vrací se jen ROZDÍL vůči nim.
  final Set<String> origExtras;

  /// Skutečně zaplacená suma za modelované doplňky ze `booking_extras`
  /// (`SUM(unit_price * quantity)`). NULL = screen ji nenačetl → fallback na
  /// ceník (staré chování). Viz [origExtrasTotal].
  final double? origExtrasPaidTotal;
  final String pickupMethod;
  final String returnMethod;
  /// Nově zadaná adresa přistavení / odvozu („ulice, město"), null = nezadána.
  final String? pickupAddressNew;
  final String? returnAddressNew;
  final String pickupTime;
  final String returnTime;
  final String? helmetSize, jacketSize, pantsSize, bootsSize, glovesSize;
  final String? passengerHelmetSize, passengerJacketSize, passengerPantsSize, passengerBootsSize;

  /// Typ slevy rezervace: 'percent' | 'fixed' | null (bez slevy / neznámý →
  /// chová se jako fixed). Načítá screen z promo_codes podle discount_code;
  /// voucher kódy v promo_codes nejsou → fixed.
  final String? discountType;

  /// Aktuální věrnostní rank (loyalty level). Od [loyaltyFreeGearLevel] je
  /// veškerá placená výbava (výbava i obuv spolujezdce/řidiče) ZDARMA — i při
  /// úpravě rezervace.
  final int loyaltyLevel;

  /// Aktuální věrnostní sleva v % dle ranku — aplikuje se na KLADNÝ rozdíl
  /// (doplatek za pronájem + výbavu, bez dopravy) při úpravě APP rezervace.
  /// Screen ji předává jen pro booking_source='app', jinak 0 (parita se
  /// serverem: _apply_booking_changes_core / split_booking_moto_swap).
  final int loyaltyPercent;

  const EditPriceCalc({
    required this.booking,
    required this.newStart,
    required this.newEnd,
    required this.motoPrices,
    required this.newMotoId,
    this.newMotoPrices,
    required this.pickupDelivFee,
    required this.returnDelivFee,
    required this.selectedExtras,
    this.origExtras = const {},
    this.origExtrasPaidTotal,
    required this.pickupMethod,
    required this.returnMethod,
    this.pickupAddressNew,
    this.returnAddressNew,
    required this.pickupTime,
    required this.returnTime,
    this.helmetSize, this.jacketSize, this.pantsSize,
    this.bootsSize, this.glovesSize,
    this.passengerHelmetSize, this.passengerJacketSize, this.passengerPantsSize,
    this.passengerBootsSize,
    this.discountType,
    this.loyaltyLevel = 0,
    this.loyaltyPercent = 0,
  });

  static const _extraPrices = {'spolujezdec': 690.0, 'boty_ridic': 290.0, 'boty_spolujezdec': 290.0};

  /// Od 3. ranku je veškerá placená výbava (vč. obuvi a výbavy spolujezdce)
  /// zdarma — všechny položky v [_extraPrices] jsou gear.
  bool get _gearFree => loyaltyLevel >= loyaltyFreeGearLevel;

  double _priceFor(String id) => _gearFree ? 0.0 : (_extraPrices[id] ?? 0);

  /// Cena aktuálně vybraných doplňků.
  double get extrasTotal =>
      selectedExtras.fold(0.0, (sum, id) => sum + _priceFor(id));

  /// Cena původně ZAPLACENÝCH doplňků (baseline).
  ///
  /// Když screen zná skutečně zaplacené částky z `booking_extras.unit_price`
  /// ([origExtrasPaidTotal]), použije se ONA. Ceník dneška by baseline
  /// zkreslil: zákazník, který platil výbavu na ranku 1 (690 Kč) a dnes je na
  /// ranku 3, by měl baseline 0 → rozdíl by vyšel 0 a `extras_price` by zůstal
  /// na 690, zatímco řádky se přepíšou na 0 → faktura by vykázala jinou cenu
  /// pronájmu (a při odebrání výbavy by se vracelo, co nikdo nezaplatil).
  double get origExtrasTotal =>
      origExtrasPaidTotal ??
      origExtras.fold(0.0, (sum, id) => sum + _priceFor(id));

  /// ROZDÍL doplňků vůči původním — kladný = doplatek, záporný = refund.
  ///
  /// Počítá se JEN když se výběr doplňků reálně změnil. Jinak by po povýšení
  /// ranku (baseline = skutečně zaplaceno, dnešní cena = 0) vyskočil refund
  /// i při úpravě, která se doplňků vůbec netýká (třeba jen posun termínu) —
  /// a to bez přepsání `booking_extras` / `extras_price`, tedy rozbitě.
  /// Screen přepisuje řádky a `extras_price` právě a jen při [extrasChanged],
  /// takže obojí zůstává v souladu.
  double get extrasDelta =>
      extrasChanged ? (extrasTotal - origExtrasTotal) : 0.0;

  bool get extrasChanged => !(selectedExtras.length == origExtras.length &&
      selectedExtras.containsAll(origExtras));

  int get origDays => booking.dayCount;
  int get newDays {
    if (newStart == null || newEnd == null) return origDays;
    return calendarDaysInclusive(newStart!, newEnd!);
  }
  int get diffDays => newDays - origDays;

  double get origDailyPrice {
    if (origDays == 0) return 0;
    final base = booking.totalPrice
        + (booking.discountAmount ?? 0)
        - (booking.deliveryFee ?? 0)
        - (booking.extrasPrice ?? 0);
    return base / origDays;
  }

  /// Výměna motorky s dostupným ceníkem nové motorky (bez ceníku by rozdíl
  /// nešel spočítat — pak se počítá jako beze změny motorky).
  bool get motoChanged =>
      newMotoId != null && newMotoId != booking.motoId && newMotoPrices != null;

  /// Hrubá cena pronájmu rozsahu podle ceníku STARÉ motorky (fallback =
  /// průměrná zaplacená denní cena, když ceník není načtený).
  double _oldGrossFor(DateTime start, DateTime end) => motoPrices != null
      ? motoPrices!.totalForRange(start, end)
      : origDailyPrice * calendarDaysInclusive(start, end);

  /// Hrubá cena pronájmu původního rozsahu (ceník staré motorky).
  double get _rentalGrossOld => _oldGrossFor(booking.startDate, booking.endDate);

  /// Nový rozsah oceněný ceníkem STARÉ motorky — základ rozdílu termínu.
  double get _rentalGrossNewOnOld => (newStart == null || newEnd == null)
      ? _rentalGrossOld
      : _oldGrossFor(newStart!, newEnd!);

  /// Hrubá cena pronájmu nového rozsahu (ceník efektivní motorky — při výměně
  /// nové, jinak staré).
  double get _rentalGrossNew {
    if (newStart == null || newEnd == null) return _rentalGrossOld;
    if (motoChanged) return newMotoPrices!.totalForRange(newStart!, newEnd!);
    return _rentalGrossNewOnOld;
  }

  /// Informativní řádek UI: hrubý rozdíl pronájmu (bez storna a late slevy) —
  /// finální Doplatek/Vrácení počítá [rentalDiff]/[effectivePriceDiff].
  double get dateChangeAmount {
    if (newStart == null || newEnd == null) return 0;
    return _rentalGrossNew - _rentalGrossOld;
  }

  /// Storno % pro vratkovou část — server (_apply_booking_changes_core) ho
  /// počítá z NOVÉHO STARTU (v_fs), ne z konce. Vč. stropu po posunu termínu.
  int get stornoPercent =>
      StornoCalc.effectiveRefundPercent(newStart ?? booking.startDate, booking);

  /// Late sleva nového rozsahu podle ceníku STARÉ motorky (bez ceníku se drží
  /// uložená hodnota — stejná pojistka jako [newLatePickup]).
  double get _lateNewOnOld {
    if (newStart == null || newEnd == null) return 0;
    if (motoPrices == null) return oldLatePickup;
    return _lateFor(motoPrices, newStart!, newEnd!, pickupTime);
  }

  /// Rozdíl TERMÍNU podle ceníku STARÉ motorky (vč. late slevy) před stornem —
  /// zrcadlí server: (nová hrubá − nová late) − (stará hrubá − stará late).
  double get datesDiffRaw {
    if (newStart == null || newEnd == null) return 0;
    return (_rentalGrossNewOnOld - _lateNewOnOld) - (_rentalGrossOld - oldLatePickup);
  }

  /// Rozdíl termínu po stornu: ZÁPORNÝ rozdíl (odebrané dny, ztráta půldne) se
  /// krátí storno %, kladný doplatek je vždy 100 %.
  double get datesDiff {
    var d = datesDiffRaw;
    if (d < 0) d = (d * stornoPercent / 100).roundToDouble();
    return d;
  }

  /// Rozdíl VÝMĚNY MOTORKY na novém rozsahu (nový ceník − starý ceník, vč.
  /// late slevy). Storno se na něj NEvztahuje — vrací/účtuje se 100 % v obou
  /// směrech (parita se záložkou Výměna motorky, Velínem i SQL
  /// _apply_booking_changes_core; incident C69236EB 2026-09-12: levnější
  /// motorka den před startem = storno 0 % → rozdíl 0 Kč, žádný dobropis).
  double get motoDiff {
    if (newStart == null || newEnd == null || !motoChanged) return 0;
    return (_rentalGrossNew - newLatePickup) - (_rentalGrossNewOnOld - _lateNewOnOld);
  }

  /// Rozdíl pronájmu celkem = termín (po stornu) + výměna motorky (100 %).
  double get rentalDiff => datesDiff + motoDiff;

  static String? _normAddr(String? a) {
    final s = (a ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return s.isEmpty ? null : s;
  }

  /// Strana přistavení zůstává, ale zákazník zadal JINOU adresu.
  bool get pickupAddressChanged => pickupMethod == 'delivery' &&
      _normAddr(pickupAddressNew) != null &&
      _normAddr(pickupAddressNew) != _normAddr(booking.pickupAddress);
  bool get returnAddressChanged => returnMethod == 'delivery' &&
      _normAddr(returnAddressNew) != null &&
      _normAddr(returnAddressNew) != _normAddr(booking.returnAddress);

  /// Nově zvolené přistavení / odvoz bez zadané adresy nebo nová adresa bez
  /// spočtené trasy (poplatek 0) — uložit nejde, jinak by šlo přistavení
  /// zdarma (DB pojistka trg_guard_booking_delivery by zápis stejně odmítla).
  bool get deliveryAddressMissing =>
      (pickupMethod == 'delivery' && booking.pickupMethod != 'delivery' && pickupDelivFee <= 0) ||
      (returnMethod == 'delivery' && booking.returnMethod != 'delivery' && returnDelivFee <= 0) ||
      (pickupAddressChanged && pickupDelivFee <= 0) ||
      (returnAddressChanged && returnDelivFee <= 0);

  /// Spodní mez ceny strany přistavení: 1000 Kč + 40 Kč × (vzdušná km od
  /// Mezné − [tolKm]); bez GPS 1000 Kč (parita se serverem `_delivery_fee_floor`).
  static double _sideFloor(double? lat, double? lng, [double tolKm = 2]) {
    if (lat == null || lng == null) return 1000;
    const la0 = 49.3464, lo0 = 15.2119;
    double rad(double d) => d * math.pi / 180;
    final a = math.pow(math.sin(rad(lat - la0) / 2), 2) +
        math.cos(rad(la0)) * math.cos(rad(lat)) * math.pow(math.sin(rad(lng - lo0) / 2), 2);
    final km = 2 * 6371 * math.asin(math.min(1.0, math.sqrt(a)));
    if (km > 2000) return 1000;
    return (1000 + 40 * math.max(0.0, km - tolKm)).roundToDouble();
  }

  /// Přesné rozdělení delivery_fee z poslední úpravy (server, web i appka
  /// zapisují pickup_fee_to/return_fee_to + fee_split_exact) — platí, jen
  /// když součet sedí na současné delivery_fee.
  (double, double)? get _exactSplit {
    final fee = (booking.deliveryFee ?? 0).toDouble();
    for (final e in booking.modificationHistory.reversed) {
      final r = e.raw;
      if (r['fee_split_exact'] != true || r['pickup_fee_to'] == null || r['return_fee_to'] == null) continue;
      final p = double.tryParse('${r['pickup_fee_to']}');
      final q = double.tryParse('${r['return_fee_to']}');
      if (p == null || q == null || p < 0 || q < 0) return null;
      return ((p + q) - fee).abs() < 0.5 ? (p, q) : null;
    }
    return null;
  }

  /// Rozdíl poplatku za přistavení/odvoz + nové podíly stran.
  ///
  /// DB ukládá jen kombinovanou `delivery_fee`. Pravidla (2026-10-01, parita
  /// se serverem `_apply_booking_changes_core` — incident „vratka −11 Kč"):
  ///  • strana beze změny (i znovu zadaná STEJNÁ adresa) si nechává svůj podíl;
  ///  • obě strany přistavením → přesné podíly z historie, jinak odhad v poměru
  ///    podlah dle uložených GPS (bez nich půl na půl); odebraná strana při
  ///    odhadu vrací nejvýš svou podlahu;
  ///  • přesun adresy nikdy nevrací peníze (jen doplatek) — appka GPS nové
  ///    adresy nemá, vzdálenost nejde ověřit;
  ///  • nově přidaná strana = cena trasy (bez adresy uložit nejde).
  ({double delta, double pickup, double ret, bool exact}) get deliverySplit {
    final double oldFee = (booking.deliveryFee ?? 0).toDouble();
    final b = booking;
    final pickupWas = b.pickupMethod == 'delivery';
    final returnWas = b.returnMethod == 'delivery';
    final pickupIs = pickupMethod == 'delivery';
    final returnIs = returnMethod == 'delivery';
    final pickupMoved = pickupWas && pickupIs && pickupDelivFee > 0 && pickupAddressChanged;
    final returnMoved = returnWas && returnIs && returnDelivFee > 0 && returnAddressChanged;

    double oldP = pickupWas ? oldFee : 0.0;
    double oldR = returnWas ? oldFee : 0.0;
    bool exact = true;
    if (pickupWas && returnWas) {
      final ex = _exactSplit;
      if (ex != null) {
        oldP = ex.$1;
        oldR = ex.$2;
      } else {
        exact = false;
        final hasGps = b.pickupLat != null && b.pickupLng != null && b.returnLat != null && b.returnLng != null;
        final wp = hasGps ? _sideFloor(b.pickupLat, b.pickupLng, 0) : 1.0;
        final wr = hasGps ? _sideFloor(b.returnLat, b.returnLng, 0) : 1.0;
        oldP = (oldFee * wp / (wp + wr)).roundToDouble();
        oldR = oldFee - oldP;
        if (!pickupIs && returnIs) {
          oldP = math.min(oldP, _sideFloor(b.pickupLat, b.pickupLng));
          oldR = oldFee - oldP;
        } else if (pickupIs && !returnIs) {
          oldR = math.min(oldR, _sideFloor(b.returnLat, b.returnLng));
          oldP = oldFee - oldR;
        }
      }
    }

    if (pickupWas == pickupIs && returnWas == returnIs && !pickupMoved && !returnMoved) {
      return (delta: 0.0, pickup: oldP, ret: oldR, exact: exact);
    }

    double side(bool was, bool isNow, bool moved, double newFee, double oldShare) {
      if (!isNow) return 0.0;
      if (was && !moved) return oldShare;
      if (was && moved) return newFee > oldShare ? newFee : oldShare;
      return newFee;
    }

    final newP = side(pickupWas, pickupIs, pickupMoved, pickupDelivFee, oldP);
    final newR = side(returnWas, returnIs, returnMoved, returnDelivFee, oldR);
    return (
      delta: (newP + newR) - (oldP + oldR),
      pickup: newP,
      ret: newR,
      exact: exact || !(pickupIs && returnIs),
    );
  }

  /// Rozdíl poplatku za přistavení/odvoz oproti původní rezervaci (viz
  /// [deliverySplit]) — účtuje se (kladný) nebo vrací (záporný) JEN rozdíl.
  double get deliveryFeeDelta => deliverySplit.delta;

  /// Nová kombinovaná delivery_fee po úpravě (ukládá se do bookings).
  double get newDeliveryFee {
    final v = (booking.deliveryFee ?? 0) + deliveryFeeDelta;
    return v > 0 ? v : 0;
  }

  // ── Sleva 50 % na 1. den (pozdní vyzvednutí >=12:00, rezervace >=2 dny) ──
  // Mirror SQL _late_pickup_discount(). Je to redukce hrubého pronájmu — do
  // priceDiff vstupuje jako (stará sleva − nová sleva): víc slevy = vratka,
  // míň slevy (např. posun času před 12:00) = doplatek.
  static bool _isLatePickup(String? t) {
    if (t == null) return false;
    final p = t.split(':');
    final h = p.isNotEmpty ? int.tryParse(p[0]) : null;
    return h != null && h >= 12;
  }

  double _lateFor(DayPrices? prices, DateTime start, DateTime end, String? time) {
    if (prices == null) return 0;
    final d = calendarDaysInclusive(start, end);
    if (d < 2 || !_isLatePickup(time)) return 0;
    return (prices.forWeekday(start.weekday) * 0.5).roundToDouble();
  }

  DayPrices? get _effPrices =>
      (newMotoId != null && newMotoId != booking.motoId && newMotoPrices != null)
          ? newMotoPrices
          : motoPrices;

  /// Původní sleva na 1. den — REÁLNĚ uložená hodnota (ne přepočet; jinak by
  /// rezervace bez uložené late slevy vykázala fantomový rozdíl při úpravě).
  double get oldLatePickup => booking.latePickupDiscount ?? 0;

  /// Nová sleva na 1. den (po úpravě dat / motorky / času vyzvednutí).
  /// Bez načteného ceníku motorky nelze slevu přepočítat — drží se uložená
  /// hodnota (jinak by výpadek načtení ceníku vytvořil fantomový doplatek
  /// +oldLatePickup a tichý reset sloupce na 0).
  double get newLatePickup {
    if (newStart == null || newEnd == null) return 0;
    final p = _effPrices;
    if (p == null) return oldLatePickup;
    return _lateFor(p, newStart!, newEnd!, pickupTime);
  }

  /// Dopad změny late slevy na cenu (kladný = zákazník platí víc — o slevu
  /// přišel; záporný = slevu získal). Jen pro zobrazení řádku v UI.
  double get latePickupDelta => oldLatePickup - newLatePickup;

  double get priceDiff {
    if (newStart == null || newEnd == null) return 0;
    // rentalDiff už obsahuje rozdíl ceníku (vč. výměny motorky), late-pickup
    // slevu i storno na záporné části — zrcadlí server, viz výše.
    return rentalDiff + deliveryFeeDelta + extrasDelta;
  }

  // ── Varianta B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
  // `priceDiff` je HRUBÝ rozdíl (po stornu na zkrácené části). Na novou hrubou
  // cenu se znovu aplikuje původní sleva: procentuální efektivní sazbou
  // (discount / stará hrubá), absolutní jako odpočet max do výše nové hrubé.
  // Účtuje/vrací se `effectivePriceDiff` (po slevě) — zrcadlí SQL helper
  // _apply_discount_variant_b (web RPC cesty počítají totéž server-side).

  double get _oldDiscount {
    final d = booking.discountAmount ?? 0.0;
    return d > 0 ? d : 0.0;
  }

  double get _oldGross => booking.totalPrice + _oldDiscount;

  double get newGross {
    final g = _oldGross + priceDiff;
    return g > 0 ? g : 0;
  }

  /// Nová výše slevy v Kč po úpravě — ukládá se do bookings.discount_amount.
  double get newDiscountAmount {
    if (_oldDiscount <= 0) return 0;
    // DOPLATEK (gross >= 0): plná cena, sleva zachována (option B).
    if (priceDiff >= 0) return _oldDiscount;
    // VRATKA: uniformní poměrná sazba — procento i voucher se krátí stejně.
    if (_oldGross > 0) return (newGross * _oldDiscount / _oldGross).roundToDouble();
    return 0;
  }

  // ── Věrnostní sleva na doplatek (2026-08-06) ──
  // Kladný rozdíl pronájmu + výbavy (bez dopravy — parita se vznikem rezervace,
  // kde loyalty base = pronájem + výbava) se snižuje o % dle aktuálního ranku.
  // Vratky se nemění. Zrcadlí SQL _apply_booking_changes_core.

  /// Část rozdílu podléhající věrnostní slevě — doprava se vyjímá.
  double get _loyaltyEligibleDiff {
    final d = priceDiff - deliveryFeeDelta;
    return d > 0 ? d : 0;
  }

  /// Věrnostní sleva na doplatek v Kč — přičítá se k bookings.loyalty_discount_amount.
  double get loyaltySurchargeDiscount {
    if (loyaltyPercent <= 0) return 0;
    return (_loyaltyEligibleDiff * loyaltyPercent / 100).roundToDouble();
  }

  /// Nová celková cena (netto, po slevě) — ukládá se do bookings.total_price.
  double get newTotal {
    final t = newGross - newDiscountAmount - loyaltySurchargeDiscount;
    return t > 0 ? t.roundToDouble() : 0;
  }

  /// Rozdíl PO slevě — tohle se účtuje bránou (>0) nebo vrací refundem (<0).
  double get effectivePriceDiff => newTotal - booking.totalPrice;

  bool get hasChanges =>
      diffDays != 0 ||
      (newMotoId != null && newMotoId != booking.motoId) ||
      // Metody sémanticky (pobočka↔adresa) — DB drží synonyma pobočky
      // ('store'/'pickup'/'branch'/'rental'), obrazovka normalizuje na store.
      (pickupMethod == 'delivery') != (booking.pickupMethod == 'delivery') ||
      (returnMethod == 'delivery') != (booking.returnMethod == 'delivery') ||
      pickupTime != (booking.pickupTime ?? '09:00') ||
      returnTime != (booking.returnTime ?? '19:00') ||
      extrasChanged ||
      deliveryFeeDelta != 0 ||
      pickupAddressChanged ||
      returnAddressChanged ||
      helmetSize != booking.helmetSize ||
      jacketSize != booking.jacketSize ||
      pantsSize != booking.pantsSize ||
      bootsSize != booking.bootsSize ||
      glovesSize != booking.glovesSize ||
      passengerHelmetSize != booking.passengerHelmetSize ||
      passengerJacketSize != booking.passengerJacketSize ||
      passengerPantsSize != booking.passengerPantsSize ||
      passengerBootsSize != booking.passengerBootsSize;
}
