/// Booking draft — collects all data during booking flow.
class BookingDraft {
  String? motoId;
  String? motoName;
  String? motoImage;
  DateTime? startDate;
  DateTime? endDate;
  String? pickupTime;
  String pickupMethod; // 'store' or 'delivery'
  String returnMethod; // 'store' or 'delivery'
  String? pickupAddress;
  String? pickupCity;
  String? pickupZip;
  double? pickupLat;
  double? pickupLng;
  String? returnAddress;
  String? returnCity;
  String? returnZip;
  double? returnLat;
  double? returnLng;
  String? insuranceType;

  /// Přiřazený kus vozíku (motorcycles.id, is_trailer=true) když si zákazník
  /// přidá vozík jako příslušenství. Zapisuje se do bookings.trailer_moto_id
  /// → blokuje kalendář vozíku. NULL = vozík nevybrán.
  String? trailerMotoId;
  List<SelectedExtra> extras;
  List<AppliedDiscount> discounts;
  String? notes;
  String? helmetSize;
  String? glovesSize;
  String? jacketSize;
  String? pantsSize;
  String? bootsSize;
  String? passengerHelmetSize;
  String? passengerJacketSize;
  String? passengerPantsSize;
  /// Zákazník má vlastní výbavu — při přistavení (delivery) přeskočí výběr
  /// základní výbavy zdarma (helma, rukavice, bunda, kalhoty).
  bool ownGear;
  bool consentVop;
  bool consentGdpr;
  bool consentKids;

  BookingDraft({
    this.motoId,
    this.motoName,
    this.motoImage,
    this.startDate,
    this.endDate,
    this.pickupTime,
    this.pickupMethod = 'store',
    this.returnMethod = 'store',
    this.pickupAddress,
    this.pickupCity,
    this.pickupZip,
    this.pickupLat,
    this.pickupLng,
    this.returnAddress,
    this.returnCity,
    this.returnZip,
    this.returnLat,
    this.returnLng,
    this.insuranceType,
    this.trailerMotoId,
    this.extras = const [],
    this.discounts = const [],
    this.notes,
    this.helmetSize,
    this.glovesSize,
    this.jacketSize,
    this.pantsSize,
    this.bootsSize,
    this.passengerHelmetSize,
    this.passengerJacketSize,
    this.passengerPantsSize,
    this.ownGear = false,
    this.consentVop = false,
    this.consentGdpr = false,
    this.consentKids = false,
  });

  int get dayCount {
    if (startDate == null || endDate == null) return 0;
    return endDate!.difference(startDate!).inDays + 1; // inclusive
  }

  /// Creates a new BookingDraft with updated fields.
  /// Must create NEW instance — Riverpod StateProvider compares references.
  BookingDraft copyWith({
    String? Function()? motoId,
    String? Function()? motoName,
    String? Function()? motoImage,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    String? Function()? pickupTime,
    String? pickupMethod,
    String? returnMethod,
    String? Function()? pickupAddress,
    String? Function()? pickupCity,
    String? Function()? pickupZip,
    double? Function()? pickupLat,
    double? Function()? pickupLng,
    String? Function()? returnAddress,
    String? Function()? returnCity,
    String? Function()? returnZip,
    double? Function()? returnLat,
    double? Function()? returnLng,
    String? Function()? insuranceType,
    String? Function()? trailerMotoId,
    List<SelectedExtra>? extras,
    List<AppliedDiscount>? discounts,
    String? Function()? notes,
    String? Function()? helmetSize,
    String? Function()? glovesSize,
    String? Function()? jacketSize,
    String? Function()? pantsSize,
    String? Function()? bootsSize,
    String? Function()? passengerHelmetSize,
    String? Function()? passengerJacketSize,
    String? Function()? passengerPantsSize,
    bool? ownGear,
    bool? consentVop,
    bool? consentGdpr,
    bool? consentKids,
  }) {
    return BookingDraft(
      motoId: motoId != null ? motoId() : this.motoId,
      motoName: motoName != null ? motoName() : this.motoName,
      motoImage: motoImage != null ? motoImage() : this.motoImage,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      pickupTime: pickupTime != null ? pickupTime() : this.pickupTime,
      pickupMethod: pickupMethod ?? this.pickupMethod,
      returnMethod: returnMethod ?? this.returnMethod,
      pickupAddress: pickupAddress != null ? pickupAddress() : this.pickupAddress,
      pickupCity: pickupCity != null ? pickupCity() : this.pickupCity,
      pickupZip: pickupZip != null ? pickupZip() : this.pickupZip,
      pickupLat: pickupLat != null ? pickupLat() : this.pickupLat,
      pickupLng: pickupLng != null ? pickupLng() : this.pickupLng,
      returnAddress: returnAddress != null ? returnAddress() : this.returnAddress,
      returnCity: returnCity != null ? returnCity() : this.returnCity,
      returnZip: returnZip != null ? returnZip() : this.returnZip,
      returnLat: returnLat != null ? returnLat() : this.returnLat,
      returnLng: returnLng != null ? returnLng() : this.returnLng,
      insuranceType: insuranceType != null ? insuranceType() : this.insuranceType,
      trailerMotoId: trailerMotoId != null ? trailerMotoId() : this.trailerMotoId,
      extras: extras ?? this.extras,
      discounts: discounts ?? this.discounts,
      notes: notes != null ? notes() : this.notes,
      helmetSize: helmetSize != null ? helmetSize() : this.helmetSize,
      glovesSize: glovesSize != null ? glovesSize() : this.glovesSize,
      jacketSize: jacketSize != null ? jacketSize() : this.jacketSize,
      pantsSize: pantsSize != null ? pantsSize() : this.pantsSize,
      bootsSize: bootsSize != null ? bootsSize() : this.bootsSize,
      passengerHelmetSize: passengerHelmetSize != null ? passengerHelmetSize() : this.passengerHelmetSize,
      passengerJacketSize: passengerJacketSize != null ? passengerJacketSize() : this.passengerJacketSize,
      passengerPantsSize: passengerPantsSize != null ? passengerPantsSize() : this.passengerPantsSize,
      ownGear: ownGear ?? this.ownGear,
      consentVop: consentVop ?? this.consentVop,
      consentGdpr: consentGdpr ?? this.consentGdpr,
      consentKids: consentKids ?? this.consentKids,
    );
  }
}

/// Selected extra / accessory — mirrors extra checkboxes from templates.
class SelectedExtra {
  final String id;
  final String name;
  final double price;
  int quantity;
  String? size;

  SelectedExtra({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.size,
  });
}

/// Applied discount (promo code or voucher).
/// Mirrors _appliedBookingCodes[] from cart-booking-discount.js.
class AppliedDiscount {
  final String code;
  final String? promoId;
  final DiscountType type;
  final double value; // percentage (0-100) or fixed amount in Kč
  double calculatedAmount; // actual Kč discount after calculation

  /// true = dárkový poukaz (peníze), false = promo kód. Informativní —
  /// věrnostní sleva (ranky) se kombinuje s OBOJÍM, slevy se sčítají.
  final bool isVoucher;

  AppliedDiscount({
    required this.code,
    this.promoId,
    required this.type,
    required this.value,
    this.calculatedAmount = 0,
    this.isVoucher = false,
  });
}

enum DiscountType { percent, fixed }

/// Price breakdown — result of price calculation.
class PriceBreakdown {
  final double basePrice;
  final double extrasTotal;
  final double pickupDeliveryFee;
  final double returnDeliveryFee;
  final double insuranceFee;
  final double discountTotal;
  final double total;
  final int days;

  /// Věrnostní sleva (ranky) — JEN pro rezervace v aplikaci. Počítá se
  /// z pronájmu + příslušenství (bez přistavení a pojištění) a KOMBINUJE
  /// se s promo kódy i dárkovými vouchery (slevy se sčítají).
  final double loyaltyDiscount;
  final int loyaltyPercent;
  final int loyaltyLevel;
  final String? loyaltyRankName;

  /// Sleva 50 % na 1. den při pozdním vyzvednutí (>=12:00) a rezervaci >=2 dny.
  /// Platí pro web i app. Oddělená od promo/voucher i věrnostní slevy.
  final double latePickupDiscount;

  const PriceBreakdown({
    required this.basePrice,
    required this.extrasTotal,
    required this.pickupDeliveryFee,
    required this.returnDeliveryFee,
    this.insuranceFee = 0,
    required this.discountTotal,
    required this.total,
    required this.days,
    this.loyaltyDiscount = 0,
    this.loyaltyPercent = 0,
    this.loyaltyLevel = 0,
    this.loyaltyRankName,
    this.latePickupDiscount = 0,
  });

  double get deliveryFee => pickupDeliveryFee + returnDeliveryFee;

  double get subtotalBeforeDiscount =>
      basePrice + extrasTotal + deliveryFee + insuranceFee;
}

/// Extras catalog item — from extras_catalog Supabase table.
class ExtraCatalogItem {
  final String id;
  final String name;
  final double price;
  final String? description;
  final String? icon;
  final bool needsSize;
  final List<String> sizes;

  const ExtraCatalogItem({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.icon,
    this.needsSize = false,
    this.sizes = const [],
  });

  factory ExtraCatalogItem.fromJson(Map<String, dynamic> json) {
    return ExtraCatalogItem(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      needsSize: json['needs_size'] as bool? ?? false,
      sizes: (json['sizes'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

/// Generic gear sizes — kept as a backward-compatible default for callers that
/// don't pass a gear-type-specific list. Prefer [gearSizesFor].
const gearSizes = ['XS', 'S', 'M', 'L', 'XL', '2XL'];

/// Available boot sizes (numeric EU sizing) — generic default.
const bootSizes = ['39', '40', '41', '42', '43', '44', '45', '46', '47', '48'];

// ── Velikosti výbavy pro DOSPĚLÉ — dle motogo-web-php; bundy a kalhoty
//    rozšířené až do 6XL dle požadavku. ──
const helmetSizesAdult = ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'];
const jacketSizesAdult = ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', '6XL'];
const glovesSizesAdult = ['M', 'L', 'XL', '2XL', '3XL'];
const pantsSizesAdult = ['M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', '6XL'];
const bootSizesAdult = ['39', '40', '41', '42', '43', '44', '45', '46', '47', '48'];

// ── Velikosti výbavy pro DĚTSKÉ motorky — dle motogo-web-php childSizes. ──
const helmetSizesKids = ['YM', 'XS', 'S'];
const jacketSizesKids = ['YM 4–6 let', 'Vesta 4–9 let'];
const glovesSizesKids = ['4–7 let', '8–12 let'];
const pantsSizesKids = ['4–7 let', '7–9 let'];
const bootSizesKids = ['33', '35'];

/// Returns the size list for a gear [type] — one of
/// `helmet` / `gloves` / `jacket` / `pants` / `boots` — switching to
/// children's sizing when [kids] is true (dětská motorka, license_required='N').
List<String> gearSizesFor(String type, {required bool kids}) {
  switch (type) {
    case 'gloves':
      return kids ? glovesSizesKids : glovesSizesAdult;
    case 'jacket':
      return kids ? jacketSizesKids : jacketSizesAdult;
    case 'pants':
      return kids ? pantsSizesKids : pantsSizesAdult;
    case 'boots':
      return kids ? bootSizesKids : bootSizesAdult;
    case 'helmet':
    default:
      return kids ? helmetSizesKids : helmetSizesAdult;
  }
}

/// Default extras matching the hardcoded ones in templates-booking-form2.js.
/// `extra-spolujezdec` and `extra-boty-spolu` are passenger items — they are
/// hidden for children's bikes (which never carry a passenger).
const defaultExtras = [
  // Ceny dle webu (accessory_types: passenger_gear=690, boots_rider/passenger=290).
  ExtraCatalogItem(
    id: 'extra-spolujezdec',
    name: 'Výbava spolujezdce',
    price: 690,
    description: 'Helma, rukavice, vesta',
    icon: '👥',
  ),
  ExtraCatalogItem(
    id: 'extra-boty-ridic',
    name: 'Boty řidiče',
    price: 290,
    description: 'Moto boty – uveďte velikost',
    icon: '👢',
    needsSize: true,
    sizes: bootSizesAdult,
  ),
  ExtraCatalogItem(
    id: 'extra-boty-spolu',
    name: 'Boty spolujezdce',
    price: 290,
    description: 'Moto boty – uveďte velikost',
    icon: '👟',
    needsSize: true,
    sizes: bootSizesAdult,
  ),
];

/// Od tohoto věrnostního ranku (loyalty level) má zákazník veškerou placenou
/// výbavu — výbavu spolujezdce i veškerou obuv — ZDARMA. Platí v appce i na
/// webu (web zjistí rank po přihlášení). Základní výbava řidiče je zdarma vždy.
const loyaltyFreeGearLevel = 3;

/// ID placených gear extras, které jsou od [loyaltyFreeGearLevel] zdarma.
const freeGearExtraIds = {
  'extra-spolujezdec',
  'extra-boty-ridic',
  'extra-boty-spolu',
};
