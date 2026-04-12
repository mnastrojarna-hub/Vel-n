/// Motorcycle data model — mirrors the MOTOS object from data/motos.js.
class Motorcycle {
  final String id;
  final String model;
  final String? brand;
  final String? spz;
  final String? category;
  final String? licenseRequired; // A, A2, A1, AM, B, N
  final int? powerKw;
  final int? powerHp;
  final int? engineCc;
  final String? engineType;
  final int? torqueNm;
  final int? weightKg;
  final double? fuelTankL;
  final int? seatHeightMm;
  final bool? hasAbs;
  final bool? hasAsc;
  final String? description;
  final String? idealUsage;
  final List<String> features;
  final String? imageUrl;
  final List<String> images;
  final String? color;
  final String? manualUrl;
  final String? status; // active, maintenance, unavailable, retired
  final String? branchId;
  final String? branchName;
  final String? branchCity;
  final double? depositAmount;
  final double? insurancePrice;
  final int? minRentalDays;
  final int? maxRentalDays;
  final int? mileage;
  final DayPrices? prices;

  const Motorcycle({
    required this.id,
    required this.model,
    this.brand,
    this.spz,
    this.category,
    this.licenseRequired,
    this.powerKw,
    this.powerHp,
    this.engineCc,
    this.engineType,
    this.torqueNm,
    this.weightKg,
    this.fuelTankL,
    this.seatHeightMm,
    this.hasAbs,
    this.hasAsc,
    this.description,
    this.idealUsage,
    this.features = const [],
    this.imageUrl,
    this.images = const [],
    this.color,
    this.manualUrl,
    this.status,
    this.branchId,
    this.branchName,
    this.branchCity,
    this.depositAmount,
    this.insurancePrice,
    this.minRentalDays,
    this.maxRentalDays,
    this.mileage,
    this.prices,
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
      powerKw: (json['power_kw'] as num?)?.toInt(),
      powerHp: (json['power_hp'] as num?)?.toInt(),
      engineCc: (json['engine_cc'] as num?)?.toInt(),
      engineType: json['engine_type'] as String?,
      torqueNm: (json['torque_nm'] as num?)?.toInt(),
      weightKg: (json['weight_kg'] as num?)?.toInt(),
      fuelTankL: (json['fuel_tank_l'] as num?)?.toDouble(),
      seatHeightMm: (json['seat_height_mm'] as num?)?.toInt(),
      hasAbs: json['has_abs'] as bool?,
      hasAsc: json['has_asc'] as bool?,
      description: json['description'] as String?,
      idealUsage: _parseStringList(json['ideal_usage']).join(', '),
      features: _parseStringList(json['features']),
      imageUrl: json['image_url'] as String?,
      images: _parseStringList(json['images']),
      color: json['color'] as String?,
      manualUrl: json['manual_url'] as String?,
      status: json['status'] as String?,
      branchId: json['branch_id'] as String?,
      branchName: branch?['name'] as String?,
      branchCity: branch?['city'] as String?,
      depositAmount: (json['deposit_amount'] as num?)?.toDouble(),
      insurancePrice: (json['insurance_price'] as num?)?.toDouble(),
      minRentalDays: (json['min_rental_days'] as num?)?.toInt(),
      maxRentalDays: (json['max_rental_days'] as num?)?.toInt(),
      mileage: (json['mileage'] as num?)?.toInt(),
      prices: DayPrices.fromMotoJson(json),
    );
  }

  /// Primary display image — first from images[], fallback to image_url.
  String get displayImage =>
      images.isNotEmpty ? images.first : (imageUrl ?? '');

  /// Formatted price string for display (cheapest day).
  String get priceLabel {
    if (prices == null) return '';
    final min = prices!.cheapest;
    return '${min.toStringAsFixed(0)} Kč';
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
    if (licenseRequired != null) list.add(MapEntry('ŘP kategorie', licenseRequired!));
    if (hasAbs != null) list.add(MapEntry('ABS / ASC', '${hasAbs! ? "Ano" : "Ne"} / ${hasAsc == true ? "Ano" : "Ne"}'));
    return list;
  }

  static List<String> _parseStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [];
  }
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
