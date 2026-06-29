import '../../core/currency.dart';
/// Motorcycle data model — mirrors the MOTOS object from data/motos.js.
class Motorcycle {
  final String id;
  final String model;
  final String? brand;
  final String? spz;
  final String? category;
  final String? licenseRequired; // A, A2, A1, AM, B, N (legacy single — primární hodnota)

  /// Skupiny ŘP přijímané motorkou (motorcycles.license_groups, text[]).
  /// OR-sémantika — stačí, aby zákazník měl kteroukoliv. Prázdné → fallback
  /// na [licenseRequired] (viz [licenseGroupsOrFallback]).
  final List<String> licenseGroups;
  final int? powerKw;
  final int? powerHp;
  final int? engineCc;
  final String? engineType;
  final String? transmission;
  final String? drivetrain; // chain, shaft, belt
  final int? torqueNm;
  final int? weightKg;
  final double? fuelTankL;
  final double? fuelConsumptionL100km;
  final String? fuelType;
  final int? topSpeedKmh;
  final String? brakeType;
  final int? seatsCount;
  final int? seatHeightMm;
  final int? year;
  final bool? hasAbs;
  final bool? hasAsc;
  final String? description;
  /// Auto-překlady z Velína (`motorcycles.translations` = `{lang:{description:…}}`).
  final Map? translations;
  final String? idealUsage;
  final List<String> features;

  /// Parameters selected in Velín to show in the "Základní údaje" section
  /// (motorcycles.short_desc_fields, text[]). Empty → default set is used.
  final List<String> shortDescFields;
  final String? imageUrl;
  final List<String> images;

  /// MP4 videa motorky (motorcycles.videos, text[]). Přehrávají se až na detailu;
  /// v přehledu/seznamu se zobrazuje vždy fotka.
  final List<String> videos;
  final String? color;
  final String? manualUrl;
  final String? manualExternalUrl;
  final String? status; // active, maintenance, unavailable, retired
  final String? branchId;
  final String? branchName;
  final String? branchCity;
  final String? branchType; // 'obslužná' (staffed) / 'samoobslužná' (self-service)

  /// Vozík/přívěs za auto (motorcycles.is_trailer). Půjčuje se samostatně bez
  /// výbavy (boty, oblečení…) — rezervační flow pak krok s výbavou skryje.
  final bool isTrailer;
  final double? depositAmount;
  final double? insurancePrice;
  final int? minRentalDays;
  final int? maxRentalDays;
  final int? mileage;
  final DayPrices? prices;

  /// Whether the motorcycle is available today — set by provider after availability check.
  final bool? availableToday;

  const Motorcycle({
    required this.id,
    required this.model,
    this.brand,
    this.spz,
    this.category,
    this.licenseRequired,
    this.licenseGroups = const [],
    this.powerKw,
    this.powerHp,
    this.engineCc,
    this.engineType,
    this.transmission,
    this.drivetrain,
    this.torqueNm,
    this.weightKg,
    this.fuelTankL,
    this.fuelConsumptionL100km,
    this.fuelType,
    this.topSpeedKmh,
    this.brakeType,
    this.seatsCount,
    this.seatHeightMm,
    this.year,
    this.hasAbs,
    this.hasAsc,
    this.description,
    this.translations,
    this.idealUsage,
    this.features = const [],
    this.shortDescFields = const [],
    this.imageUrl,
    this.images = const [],
    this.videos = const [],
    this.color,
    this.manualUrl,
    this.manualExternalUrl,
    this.status,
    this.branchId,
    this.branchName,
    this.branchCity,
    this.branchType,
    this.isTrailer = false,
    this.depositAmount,
    this.insurancePrice,
    this.minRentalDays,
    this.maxRentalDays,
    this.mileage,
    this.prices,
    this.availableToday,
  });

  factory Motorcycle.fromJson(Map<String, dynamic> json) {
    // Branch data comes from join: motorcycles(*, branches(name, city))
    final branch = json['branches'] as Map<String, dynamic>?;

    return Motorcycle(
      id: json['id'] as String,
      model: json['model'] as String? ?? '',
      brand: json['brand'] as String?,
      spz: json['spz'] as String?,
      category: json['category'] as String?,
      licenseRequired: json['license_required'] as String?,
      licenseGroups: _parseStringList(json['license_groups'])
          .map((e) => e.toUpperCase())
          .where((e) => e.isNotEmpty)
          .toList(),
      powerKw: (json['power_kw'] as num?)?.toInt(),
      powerHp: (json['power_hp'] as num?)?.toInt(),
      engineCc: (json['engine_cc'] as num?)?.toInt(),
      engineType: json['engine_type'] as String?,
      transmission: json['transmission'] as String?,
      drivetrain: json['drivetrain'] as String?,
      torqueNm: (json['torque_nm'] as num?)?.toInt(),
      weightKg: (json['weight_kg'] as num?)?.toInt(),
      fuelTankL: (json['fuel_tank_l'] as num?)?.toDouble(),
      fuelConsumptionL100km: (json['fuel_consumption_l100km'] as num?)?.toDouble(),
      fuelType: json['fuel_type'] as String?,
      topSpeedKmh: (json['top_speed_kmh'] as num?)?.toInt(),
      brakeType: json['brake_type'] as String?,
      seatsCount: (json['seats_count'] as num?)?.toInt(),
      seatHeightMm: (json['seat_height_mm'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
      hasAbs: json['has_abs'] as bool?,
      hasAsc: json['has_asc'] as bool?,
      description: json['description'] as String?,
      translations: json['translations'] as Map?,
      idealUsage: _parseStringList(json['ideal_usage']).join(', '),
      features: _parseStringList(json['features']),
      shortDescFields: _parseStringList(json['short_desc_fields']),
      imageUrl: json['image_url'] as String?,
      images: _parseStringList(json['images']),
      videos: _parseStringList(json['videos']),
      color: json['color'] as String?,
      manualUrl: json['manual_url'] as String?,
      manualExternalUrl: json['manual_external_url'] as String?,
      status: json['status'] as String?,
      branchId: json['branch_id'] as String?,
      branchName: branch?['name'] as String?,
      branchCity: branch?['city'] as String?,
      branchType: branch?['type'] as String?,
      isTrailer: json['is_trailer'] as bool? ?? false,
      depositAmount: (json['deposit_amount'] as num?)?.toDouble(),
      insurancePrice: (json['insurance_price'] as num?)?.toDouble(),
      minRentalDays: (json['min_rental_days'] as num?)?.toInt(),
      maxRentalDays: (json['max_rental_days'] as num?)?.toInt(),
      mileage: (json['mileage'] as num?)?.toInt(),
      prices: DayPrices.fromMotoJson(json),
    );
  }

  /// Returns a copy with [availableToday] set.
  Motorcycle withAvailableToday(bool value) => Motorcycle(
    id: id, model: model, brand: brand, spz: spz, category: category,
    licenseRequired: licenseRequired, licenseGroups: licenseGroups,
    powerKw: powerKw, powerHp: powerHp,
    engineCc: engineCc, engineType: engineType, transmission: transmission,
    drivetrain: drivetrain, torqueNm: torqueNm,
    weightKg: weightKg, fuelTankL: fuelTankL,
    fuelConsumptionL100km: fuelConsumptionL100km, fuelType: fuelType,
    topSpeedKmh: topSpeedKmh, brakeType: brakeType, seatsCount: seatsCount,
    seatHeightMm: seatHeightMm, year: year,
    hasAbs: hasAbs, hasAsc: hasAsc, description: description,
    translations: translations,
    idealUsage: idealUsage, features: features,
    shortDescFields: shortDescFields, imageUrl: imageUrl,
    images: images, videos: videos, color: color, manualUrl: manualUrl,
    manualExternalUrl: manualExternalUrl, status: status,
    branchId: branchId, branchName: branchName, branchCity: branchCity,
    branchType: branchType, isTrailer: isTrailer,
    depositAmount: depositAmount, insurancePrice: insurancePrice,
    minRentalDays: minRentalDays, maxRentalDays: maxRentalDays,
    mileage: mileage, prices: prices, availableToday: value,
  );

  /// Primary display image — first from images[], fallback to image_url.
  String get displayImage =>
      images.isNotEmpty ? images.first : (imageUrl ?? '');

  /// Skupiny ŘP přijímané motorkou (uppercase). Primárně [licenseGroups],
  /// fallback na legacy [licenseRequired]. OR-sémantika.
  List<String> get licenseGroupsOrFallback {
    if (licenseGroups.isNotEmpty) return licenseGroups;
    final lr = (licenseRequired ?? '').toUpperCase();
    return lr.isEmpty ? const [] : [lr];
  }

  /// Active manual link — uploaded PDF takes precedence over external URL.
  String? get activeManualUrl =>
      (manualUrl != null && manualUrl!.isNotEmpty)
          ? manualUrl
          : (manualExternalUrl != null && manualExternalUrl!.isNotEmpty
              ? manualExternalUrl
              : null);

  /// Whether the active manual is a PDF uploaded in Velín (vs external link).
  bool get hasManualPdf => manualUrl != null && manualUrl!.isNotEmpty;

  /// Formatted price string for display (cheapest day).
  String get priceLabel {
    if (prices == null) return '';
    final min = prices!.cheapest;
    return '${Money.czk(min)}';
  }

  /// Description with HTML tags/entities removed, for plain-text rendering.
  /// Velín stores the description as rich-text HTML (e.g. `<b>`, `<p>`), which
  /// must not leak into the UI as raw markup. Returns null when empty.
  String? get descriptionPlain {
    final d = description;
    if (d == null) return null;
    final p = stripHtml(d);
    return p.isEmpty ? null : p;
  }

  /// Lokalizovaný popis pro daný jazyk — přednost má auto-překlad z Velína
  /// (`translations[lang].description`), fallback na český `description`.
  /// Bez tohoto se v cizojazyčné appce zobrazoval popis vždy česky.
  String? descriptionPlainFor(String lang) {
    String? d = description;
    final tr = translations;
    if (tr is Map && tr[lang] is Map) {
      final v = (tr[lang] as Map)['description'];
      if (v is String && v.trim().isNotEmpty) d = v;
    }
    if (d == null) return null;
    final p = stripHtml(d);
    return p.isEmpty ? null : p;
  }

  /// "Základní údaje" items — selected via Velín (short_desc_fields). Mirrors
  /// buildShortDescItems() in motogo-web-php/components.php so the app shows the
  /// same parameters as the web detail page and catalog card. [tr] resolves an
  /// i18n key to the localized label. Falls back to a default set when nothing
  /// is selected in Velín.
  List<ShortDescItem> shortDescItems(String Function(String) tr) {
    var keys = shortDescFields.where((k) => k.isNotEmpty).toList();
    if (keys.isEmpty) {
      keys = const ['power_kw', 'category', 'engine', 'drivetrain', 'fuel_consumption_l100km'];
    }
    final items = <ShortDescItem>[];
    for (final k in keys) {
      ShortDescItem? it;
      switch (k) {
        case 'power_kw':
          if (powerKw != null) {
            final card = '$powerKw kW';
            var v = card;
            if (powerHp != null) v += ' (cca $powerHp ${tr('sdHpUnit')})';
            it = ShortDescItem(tr('specPower'), v, card);
          }
        case 'category':
          if (category != null && category!.isNotEmpty) {
            final lbl = _categoryLabel(category!, tr);
            it = ShortDescItem(tr('sdType'), lbl, lbl);
          }
        case 'engine':
          final parts = <String>[];
          if (engineCc != null) parts.add('$engineCc ccm');
          if (engineType != null && engineType!.isNotEmpty) parts.add(engineType!);
          if (transmission != null && transmission!.isNotEmpty) parts.add(transmission!);
          if (parts.isNotEmpty) it = ShortDescItem(tr('specEngine'), parts.join(', '), parts.first);
        case 'engine_cc':
          if (engineCc != null) { final v = '$engineCc ccm'; it = ShortDescItem(tr('sdEngineCc'), v, v); }
        case 'engine_type':
          if (engineType != null && engineType!.isNotEmpty) it = ShortDescItem(tr('sdEngineType'), engineType!, engineType!);
        case 'transmission':
          if (transmission != null && transmission!.isNotEmpty) it = ShortDescItem(tr('sdTransmission'), transmission!, transmission!);
        case 'drivetrain':
          if (drivetrain != null && drivetrain!.isNotEmpty) {
            final v = _drivetrainLabel(drivetrain!, tr);
            it = ShortDescItem(tr('sdDrivetrain'), v, v);
          }
        case 'fuel_consumption_l100km':
          if (fuelConsumptionL100km != null) {
            final v = '${_num(fuelConsumptionL100km!)} l/100 km';
            it = ShortDescItem(tr('sdFuelConsumption'), 'cca $v', v);
          }
        case 'fuel_type':
          if (fuelType != null && fuelType!.isNotEmpty) it = ShortDescItem(tr('sdFuelType'), fuelType!, fuelType!);
        case 'fuel_tank_l':
          if (fuelTankL != null) { final v = '${_num(fuelTankL!)} l'; it = ShortDescItem(tr('specFuelTank'), v, v); }
        case 'torque_nm':
          if (torqueNm != null) { final v = '$torqueNm Nm'; it = ShortDescItem(tr('specTorque'), v, v); }
        case 'top_speed_kmh':
          if (topSpeedKmh != null) { final v = '$topSpeedKmh km/h'; it = ShortDescItem(tr('sdTopSpeed'), v, v); }
        case 'weight_kg':
          if (weightKg != null) { final v = '$weightKg kg'; it = ShortDescItem(tr('specWeight'), v, v); }
        case 'seat_height_mm':
          if (seatHeightMm != null) { final v = '$seatHeightMm mm'; it = ShortDescItem(tr('specSeatHeight'), v, v); }
        case 'seats_count':
          if (seatsCount != null) { final v = '$seatsCount'; it = ShortDescItem(tr('sdSeatsCount'), v, v); }
        case 'brake_type':
          if (brakeType != null && brakeType!.isNotEmpty) it = ShortDescItem(tr('sdBrakeType'), brakeType!, brakeType!);
        case 'has_abs':
          if (hasAbs == true) it = ShortDescItem(tr('sdAbs'), tr('specYes'), 'ABS');
        case 'has_asc':
          if (hasAsc == true) it = ShortDescItem(tr('sdAsc'), tr('specYes'), 'ASC');
        case 'license_required':
          final lg = licenseGroupsOrFallback;
          if (lg.isNotEmpty) {
            final shown = lg.length == 1 && lg.first == 'N'
                ? 'N'
                : lg.where((g) => g != 'N').join(' / ');
            if (shown.isNotEmpty) it = ShortDescItem(tr('specLicenseCategory'), shown, shown);
          }
        case 'year':
          if (year != null) { final v = '$year'; it = ShortDescItem(tr('sdYear'), v, v); }
        case 'color':
          if (color != null && color!.isNotEmpty) it = ShortDescItem(tr('sdColor'), color!, color!);
      }
      if (it != null) items.add(it);
    }
    return items;
  }

  static String _categoryLabel(String cat, String Function(String) tr) {
    const map = {
      'cestovni': 'motoCardCategoryTravel',
      'detske': 'motoCardCategoryChildren',
      'sportovni': 'motoCardCategorySport',
      'naked': 'motoCardCategoryNaked',
      'chopper': 'motoCardCategoryChopper',
      'supermoto': 'motoCardCategorySupermoto',
    };
    final key = map[cat];
    return key != null ? tr(key) : cat;
  }

  static String _drivetrainLabel(String d, String Function(String) tr) {
    switch (d) {
      case 'chain': return tr('sdDrivetrainChain');
      case 'shaft': return tr('sdDrivetrainShaft');
      case 'belt': return tr('sdDrivetrainBelt');
      default: return d;
    }
  }

  /// Formats a number without a trailing ".0" (e.g. 4.0 → "4", 4.5 → "4.5").
  static String _num(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Strips HTML tags and decodes common entities, preserving line breaks from
  /// block-level/`<br>` tags.
  static String stripHtml(String input) {
    var s = input;
    s = s.replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</\s*(p|div|li|h[1-6]|ul|ol|tr)\s*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r' *\n *'), '\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  /// Spec list for detail screen — mirrors specs[] from motos.js.
  List<MapEntry<String, String>> get specList {
    final list = <MapEntry<String, String>>[];
    if (engineCc != null) list.add(MapEntry('Motor', '$engineCc cc${engineType != null ? ' $engineType' : ''}'));
    if (powerKw != null) list.add(MapEntry('Výkon', '$powerKw kW${powerHp != null ? ' / $powerHp k' : ''}'));
    if (torqueNm != null) list.add(MapEntry('Točivý moment', '$torqueNm Nm'));
    if (weightKg != null) list.add(MapEntry('Hmotnost', '$weightKg kg'));
    if (fuelTankL != null) list.add(MapEntry('Nádrž', '$fuelTankL L'));
    if (seatHeightMm != null) list.add(MapEntry('Sedlo', '$seatHeightMm mm'));
    if (licenseGroupsOrFallback.isNotEmpty) {
      final lg = licenseGroupsOrFallback;
      final shown = lg.length == 1 && lg.first == 'N' ? 'N' : lg.where((g) => g != 'N').join(' / ');
      if (shown.isNotEmpty) list.add(MapEntry('ŘP kategorie', shown));
    }
    if (hasAbs != null) list.add(MapEntry('ABS / ASC', '${hasAbs! ? "Ano" : "Ne"} / ${hasAsc == true ? "Ano" : "Ne"}'));
    return list;
  }

  static List<String> _parseStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [];
  }
}

/// A single "Základní údaje" entry. [card] is the compact value without label
/// (for tight layouts); [value] is the full value shown next to [label].
class ShortDescItem {
  final String label;
  final String value;
  final String card;
  const ShortDescItem(this.label, this.value, this.card);
}

/// Per-day pricing — mirrors pricing:{po,ut,st,ct,pa,so,ne} from motos.js
/// and price_mon..price_sun columns from motorcycles table.
class DayPrices {
  final double mon;
  final double tue;
  final double wed;
  final double thu;
  final double fri;
  final double sat;
  final double sun;

  const DayPrices({
    required this.mon,
    required this.tue,
    required this.wed,
    required this.thu,
    required this.fri,
    required this.sat,
    required this.sun,
  });

  factory DayPrices.fromMotoJson(Map<String, dynamic> json) {
    return DayPrices(
      mon: (json['price_mon'] as num?)?.toDouble() ?? 0,
      tue: (json['price_tue'] as num?)?.toDouble() ?? 0,
      wed: (json['price_wed'] as num?)?.toDouble() ?? 0,
      thu: (json['price_thu'] as num?)?.toDouble() ?? 0,
      fri: (json['price_fri'] as num?)?.toDouble() ?? 0,
      sat: (json['price_sat'] as num?)?.toDouble() ?? 0,
      sun: (json['price_sun'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Price for a specific day of week (DateTime.weekday: 1=Mon..7=Sun).
  double forWeekday(int weekday) {
    switch (weekday) {
      case 1: return mon;
      case 2: return tue;
      case 3: return wed;
      case 4: return thu;
      case 5: return fri;
      case 6: return sat;
      case 7: return sun;
      default: return mon;
    }
  }

  /// Cheapest day price (for "od X Kč/den" label).
  double get cheapest {
    final all = [mon, tue, wed, thu, fri, sat, sun].where((p) => p > 0);
    return all.isEmpty ? 0 : all.reduce((a, b) => a < b ? a : b);
  }

  /// Calculate total price for a date range (inclusive start+end).
  /// Mirrors calc_booking_price_v2 logic.
  double totalForRange(DateTime start, DateTime end) {
    double total = 0;
    var d = start;
    while (!d.isAfter(end)) {
      total += forWeekday(d.weekday);
      d = d.add(const Duration(days: 1));
    }
    return total;
  }

  /// Day labels for pricing card display.
  static const dayLabels = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne'];

  List<double> get asList => [mon, tue, wed, thu, fri, sat, sun];
}

/// Booked date range — from RPC get_moto_booked_dates.
class BookedDateRange {
  final DateTime start;
  final DateTime end;
  final String status;

  const BookedDateRange({
    required this.start,
    required this.end,
    required this.status,
  });

  factory BookedDateRange.fromJson(Map<String, dynamic> json) {
    return BookedDateRange(
      start: DateTime.parse(json['start_date'] as String),
      end: DateTime.parse(json['end_date'] as String),
      status: json['status'] as String? ?? '',
    );
  }

  bool containsDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }
}
