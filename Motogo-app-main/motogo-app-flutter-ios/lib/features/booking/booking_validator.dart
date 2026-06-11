import '../../core/i18n/translations.dart';
import '../reservations/reservation_models.dart';

/// Booking validation — license compatibility + overlap prevention.
class BookingValidator {
  /// License hierarchy: which categories does a given license cover?
  /// A covers A, A2, A1, AM; A2 covers A2, A1, AM; etc.
  static const _licenseCoverage = <String, List<String>>{
    'A': ['A', 'A2', 'A1', 'AM'],
    'A2': ['A2', 'A1', 'AM'],
    'A1': ['A1', 'AM'],
    'AM': ['AM'],
    'B': ['AM'],
  };

  /// Check if user's license groups allow riding a motorcycle
  /// that requires [motoLicense].
  /// Returns null if OK, or error message string.
  static String? checkLicense({
    required List<String> userLicenseGroups,
    required String? motoLicense,
  }) {
    // N = no license required (children's bikes) — anyone can ride
    if (motoLicense == null || motoLicense == 'N') return null;

    if (userLicenseGroups.isEmpty) {
      return (translations['cs']?['validationNoLicense'] ?? '')
          .replaceAll('{license}', motoLicense);
    }

    // Check if any of user's license groups covers the required category
    for (final group in userLicenseGroups) {
      final covers = _licenseCoverage[group.toUpperCase()];
      if (covers != null && covers.contains(motoLicense.toUpperCase())) {
        return null; // user has sufficient license
      }
    }

    final userGroups = userLicenseGroups.join(', ');
    return (translations['cs']?['validationInsufficientLicense'] ?? '')
        .replaceAll('{groups}', userGroups)
        .replaceAll('{license}', motoLicense);
  }

  /// Check if the user already has an active/upcoming non-children's
  /// reservation that overlaps with the selected date range.
  /// [isChildrensMoto] — true if the motorcycle being booked is children's (N).
  /// Returns null if OK, or error message string.
  static String? checkOverlap({
    required List<Reservation> userReservations,
    required DateTime startDate,
    required DateTime endDate,
    required bool isChildrensMoto,
  }) {
    // Children's motorcycles are exempt from the overlap rule
    if (isChildrensMoto) return null;

    final newStart = DateTime(startDate.year, startDate.month, startDate.day);
    final newEnd = DateTime(endDate.year, endDate.month, endDate.day);

    for (final res in userReservations) {
      // Only check active/upcoming reservations (not cancelled/completed)
      final status = res.displayStatus;
      if (status == ResStatus.cancelled || status == ResStatus.dokoncene) {
        continue;
      }

      // Skip children's motorcycle reservations — they don't block
      if (res.motoLicenseRequired == 'N') continue;

      final resStart = DateTime(
          res.startDate.year, res.startDate.month, res.startDate.day);
      final resEnd =
          DateTime(res.endDate.year, res.endDate.month, res.endDate.day);

      // Check date overlap: ranges overlap if start <= otherEnd && end >= otherStart
      if (!newStart.isAfter(resEnd) && !newEnd.isBefore(resStart)) {
        final fmt = _fmtDate(resStart);
        final fmtEnd = _fmtDate(resEnd);
        return (translations['cs']?['validationOverlap'] ?? '')
            .replaceAll('{start}', fmt)
            .replaceAll('{end}', fmtEnd)
            .replaceAll('{moto}', res.motoName);
      }
    }

    return null;
  }

  /// Pickup lead-time validation — prevents booking in the past (retroactively)
  /// and enforces the delivery lead time. Mirrors the web's `_rezMinPickupTime`.
  ///
  /// Rules (confirmed with product owner):
  ///  - Delivery ("delivery"): pickup datetime must be at least +6 h from now.
  ///  - Staffed branch pickup ([branchType] == 'obslužná'): at least +1 h.
  ///  - Self-service branch pickup ('samoobslužná' / unknown): strictly in the
  ///    future (no backwards booking, no minimum buffer).
  ///
  /// [pickupTime] is "HH:MM" (defaults to 09:00, matching the booking insert).
  /// Returns null if OK, or a localized error message.
  static String? checkPickupLeadTime({
    required DateTime? startDate,
    required String? pickupTime,
    required bool isDelivery,
    String? branchType,
    String lang = 'cs',
  }) {
    if (startDate == null) return null;

    var hh = 9, mm = 0;
    final parts = (pickupTime ?? '').split(':');
    if (parts.length == 2) {
      hh = int.tryParse(parts[0]) ?? 9;
      mm = int.tryParse(parts[1]) ?? 0;
    }
    final pickup = DateTime(
        startDate.year, startDate.month, startDate.day, hh, mm);

    final now = DateTime.now();
    final Duration minLead;
    if (isDelivery) {
      minLead = const Duration(hours: 6);
    } else if (branchType == 'obslužná') {
      minLead = const Duration(hours: 1);
    } else {
      minLead = Duration.zero; // samoobslužná / neznámá → jen ne do minulosti
    }

    // Pickup must be strictly after now (+ lead time).
    if (!pickup.isAfter(now.add(minLead))) {
      final String key;
      if (isDelivery) {
        key = 'validationDeliveryLeadTime';
      } else if (branchType == 'obslužná') {
        key = 'validationStaffedLeadTime';
      } else {
        key = 'validationPastPickup';
      }
      return translations[lang]?[key] ?? translations['cs']?[key] ?? '';
    }
    return null;
  }

  static String _fmtDate(DateTime d) => '${d.day}.${d.month}.${d.year}';
}
