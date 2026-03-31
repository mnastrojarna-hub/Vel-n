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
  List<SelectedExtra> extras;
  List<AppliedDiscount> discounts;
  String? notes;
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
    this.extras = const [],
    this.discounts = const [],
    this.notes,
    this.consentVop = false,
    this.consentGdpr = false,
    this.consentKids = false,
  });

  int get dayCount {
    if (startDate == null || endDate == null) return 0;
    return endDate!.difference(startDate!).inDays + 1; // inclusive
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

  AppliedDiscount({
    required this.code,
    this.promoId,
    required this.type,
    required this.value,
    this.calculatedAmount = 0,
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

  const PriceBreakdown({
    required this.basePrice,
    required this.extrasTotal,
    required this.pickupDeliveryFee,
    required this.returnDeliveryFee,
    this.insuranceFee = 0,
    required this.discountTotal,
    required this.total,
    required this.days,
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

/// Default extras matching the hardcoded ones in templates-booking-form2.js.
const defaultExtras = [
  ExtraCatalogItem(
    id: 'extra-spolujezdec',
    name: 'Výbava spolujezdce',
    price: 400,
    description: 'Helma, rukavice, vesta',
    icon: '👥',
  ),
  ExtraCatalogItem(
    id: 'extra-boty-ridic',
    name: 'Boty řidiče',
    price: 300,
    description: 'Moto boty – uveďte velikost',
    icon: '👢',
    needsSize: true,
    sizes: ['36', '37', '38', '39', '40', '41', '42', '43', '44', '45', '46'],
  ),
  ExtraCatalogItem(
    id: 'extra-boty-spolu',
    name: 'Boty spolujezdce',
    price: 300,
    description: 'Moto boty – uveďte velikost',
    icon: '👟',
    needsSize: true,
    sizes: ['36', '37', '38', '39', '40', '41', '42', '43', '44', '45', '46'],
  ),
];
