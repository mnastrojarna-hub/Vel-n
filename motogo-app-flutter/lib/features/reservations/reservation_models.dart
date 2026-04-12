/// Reservation status — mirrors _mapStatus() from reservations-ui.js.
enum ResStatus {
  aktivni,      // Active — current date between start and end
  nadchazejici, // Upcoming — start date in future
  dokoncene,    // Completed — end date in past or status=completed
  cancelled,    // Cancelled
}

/// Parsed booking with moto info — from Supabase bookings + motorcycles join.
class Reservation {
  final String id;
  final String? motoId;
  final String motoName;
  final String? motoImage;
  final String? category;
  final String? branchName;
  final String status; // pending, reserved, active, completed, cancelled
  final String paymentStatus; // unpaid, paid, refunded, partial_refund
  final DateTime startDate;
  final DateTime endDate;
  final String? pickupTime;
  final String pickupMethod;
  final String? pickupAddress;
  final String returnMethod;
  final String? returnAddress;
  final double totalPrice;
  final double? deliveryFee;
  final double? extrasPrice;
  final double? discountAmount;
  final String? discountCode;
  final bool sosReplacement;
  final bool endedBySos;
  final String? sosIncidentId;
  final int? rating;
  final DateTime? ratedAt;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? pickedUpAt;
  final DateTime? returnedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? stripePaymentIntentId;
  final String? contractUrl;
  final String? paymentMethod;
  final double? pickupLat;
  final double? pickupLng;
  final double? returnLat;
  final double? returnLng;
  final String? branchAddress;
  final String? branchCity;
  final double? branchLat;
  final double? branchLng;
  final double? stornoFee;
  final double? refundAmount;
  final String? motoLicenseRequired; // A, A2, A1, AM, B, N
  final String? helmetSize;
  final String? jacketSize;
  final String? pantsSize;
  final String? bootsSize;
  final String? glovesSize;
  final String? passengerHelmetSize;
  final String? passengerJacketSize;
  final String? passengerPantsSize;

  const Reservation({
    required this.id,
    this.motoId,
    required this.motoName,
    this.motoImage,
    this.category,
    this.branchName,
    required this.status,
    required this.paymentStatus,
    required this.startDate,
    required this.endDate,
    this.pickupTime,
    this.pickupMethod = 'branch',
    this.pickupAddress,
    this.returnMethod = 'branch',
    this.returnAddress,
    required this.totalPrice,
    this.deliveryFee,
    this.extrasPrice,
    this.discountAmount,
    this.discountCode,
    this.sosReplacement = false,
    this.endedBySos = false,
    this.sosIncidentId,
    this.rating,
    this.ratedAt,
    required this.createdAt,
    this.confirmedAt,
    this.pickedUpAt,
    this.returnedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.stripePaymentIntentId,
    this.contractUrl,
    this.paymentMethod,
    this.pickupLat,
    this.pickupLng,
    this.returnLat,
    this.returnLng,
    this.branchAddress,
    this.branchCity,
    this.branchLat,
    this.branchLng,
    this.stornoFee,
    this.refundAmount,
    this.motoLicenseRequired,
    this.helmetSize,
    this.jacketSize,
    this.pantsSize,
    this.bootsSize,
    this.glovesSize,
    this.passengerHelmetSize,
    this.passengerJacketSize,
    this.passengerPantsSize,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final moto = json['motorcycles'] as Map<String, dynamic>?;
    final branch = moto?['branches'] as Map<String, dynamic>?;

    return Reservation(
      id: json['id'] as String,
      motoId: json['moto_id'] as String?,
      motoName: moto?['model'] as String? ?? 'Motorka',
      motoImage: moto?['image_url'] as String?,
      category: moto?['category'] as String?,
      branchName: branch?['name'] as String?,
      branchAddress: branch?['address'] as String?,
      branchCity: branch?['city'] as String?,
      branchLat: (branch?['gps_lat'] as num?)?.toDouble(),
      branchLng: (branch?['gps_lng'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      pickupTime: json['pickup_time'] as String?,
      pickupMethod: json['pickup_method'] as String? ?? 'branch',
      pickupAddress: json['pickup_address'] as String?,
      returnMethod: json['return_method'] as String? ?? 'branch',
      pickupLat: (json['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (json['pickup_lng'] as num?)?.toDouble(),
      returnAddress: json['return_address'] as String?,
      returnLat: (json['return_lat'] as num?)?.toDouble(),
      returnLng: (json['return_lng'] as num?)?.toDouble(),
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble(),
      extrasPrice: (json['extras_price'] as num?)?.toDouble(),
      discountAmount: (json['discount_amount'] as num?)?.toDouble(),
      discountCode: json['discount_code'] as String?,
      sosReplacement: json['sos_replacement'] as bool? ?? false,
      endedBySos: json['ended_by_sos'] as bool? ?? false,
      sosIncidentId: json['sos_incident_id'] as String?,
      rating: json['rating'] as int?,
      ratedAt: json['rated_at'] != null ? DateTime.parse(json['rated_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      confirmedAt: json['confirmed_at'] != null ? DateTime.parse(json['confirmed_at'] as String) : null,
      pickedUpAt: json['picked_up_at'] != null ? DateTime.parse(json['picked_up_at'] as String) : null,
      returnedAt: json['returned_at'] != null ? DateTime.parse(json['returned_at'] as String) : null,
      cancelledAt: json['cancelled_at'] != null ? DateTime.parse(json['cancelled_at'] as String) : null,
      cancellationReason: json['cancellation_reason'] as String?,
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      contractUrl: json['contract_url'] as String?,
      paymentMethod: json['payment_method'] as String?,
      stornoFee: (json['storno_fee'] as num?)?.toDouble(),
      refundAmount: (json['refund_amount'] as num?)?.toDouble(),
      motoLicenseRequired: moto?['license_required'] as String?,
      helmetSize: json['helmet_size'] as String?,
      jacketSize: json['jacket_size'] as String?,
      pantsSize: json['pants_size'] as String?,
      bootsSize: json['boots_size'] as String?,
      glovesSize: json['gloves_size'] as String?,
      passengerHelmetSize: json['passenger_helmet_size'] as String?,
      passengerJacketSize: json['passenger_jacket_size'] as String?,
      passengerPantsSize: json['passenger_pants_size'] as String?,
    );
  }

  /// Compute display status — mirrors _mapStatus() from reservations-ui.js.
  /// A reservation can only be "aktivní" when Stripe payment is confirmed.
  ResStatus get displayStatus {
    if (status == 'cancelled') return ResStatus.cancelled;
    if (status == 'completed' || endedBySos) return ResStatus.dokoncene;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    if (today.isAfter(e)) return ResStatus.dokoncene;
    if (!today.isBefore(s) && !today.isAfter(e)) {
      // Unpaid reservation must never show as active
      if (paymentStatus != 'paid') return ResStatus.nadchazejici;
      return ResStatus.aktivni;
    }
    return ResStatus.nadchazejici;
  }

  int get dayCount => endDate.difference(startDate).inDays + 1;

  String get shortId => '#${id.substring(id.length - 8).toUpperCase()}';

  String get dateRange {
    final s = '${startDate.day}. ${startDate.month}.';
    final e = '${endDate.day}. ${endDate.month}. ${endDate.year}';
    return '$s – $e';
  }
}

/// Storno refund calculation — mirrors conditions from booking-edit-price.js.
class StornoCalc {
  /// Calculate refund percentage based on hours until the date being removed.
  /// 7+ days (168h) = 100%, 2-7 days (48-168h) = 50%, <2 days = 0%.
  static int refundPercent(DateTime removedDate) {
    final hoursUntil = removedDate.difference(DateTime.now()).inHours;
    if (hoursUntil >= 168) return 100; // 7+ days
    if (hoursUntil >= 48) return 50;   // 2-7 days
    return 0;                           // <2 days
  }

  static double refundAmount(double amount, DateTime removedDate) {
    return amount * refundPercent(removedDate) / 100;
  }
}
