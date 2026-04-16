import '../booking/booking_models.dart';
import '../catalog/moto_model.dart';
import 'reservation_models.dart';

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
  final String pickupMethod;
  final String returnMethod;
  final String? helmetSize, jacketSize, pantsSize, bootsSize, glovesSize;
  final String? passengerHelmetSize, passengerJacketSize, passengerPantsSize;

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
    required this.pickupMethod,
    required this.returnMethod,
    this.helmetSize, this.jacketSize, this.pantsSize,
    this.bootsSize, this.glovesSize,
    this.passengerHelmetSize, this.passengerJacketSize, this.passengerPantsSize,
  });

  double get extrasTotal {
    const prices = {'spolujezdec': 400.0, 'boty_ridic': 300.0, 'boty_spolujezdec': 300.0};
    return selectedExtras.fold(0.0, (sum, id) => sum + (prices[id] ?? 0));
  }

  int get origDays => booking.dayCount;
  int get newDays {
    if (newStart == null || newEnd == null) return origDays;
    return newEnd!.difference(newStart!).inDays + 1;
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

  double get dateChangeAmount {
    if (diffDays == 0 || newStart == null || newEnd == null) return 0;
    if (motoPrices != null) {
      final origRange = motoPrices!.totalForRange(booking.startDate, booking.endDate);
      final newRange = motoPrices!.totalForRange(newStart!, newEnd!);
      if (diffDays > 0) {
        return newRange - origRange;
      } else {
        final raw = origRange - newRange;
        final pct = StornoCalc.refundPercent(newEnd!);
        return -(raw * pct / 100);
      }
    }
    if (diffDays > 0) return diffDays * origDailyPrice;
    final raw = diffDays.abs() * origDailyPrice;
    final pct = StornoCalc.refundPercent(newEnd ?? booking.endDate);
    return -(raw * pct / 100);
  }

  double get priceDiff {
    if (newStart == null || newEnd == null) return 0;
    double diff = dateChangeAmount;
    diff += pickupDelivFee + returnDelivFee;
    diff += extrasTotal;
    if (newMotoId != null && newMotoId != booking.motoId && newMotoPrices != null) {
      final newTotal = newMotoPrices!.totalForRange(newStart!, newEnd!);
      final origTotal = motoPrices?.totalForRange(newStart!, newEnd!)
          ?? (origDailyPrice * newDays);
      diff += newTotal - origTotal;
    }
    return diff;
  }

  bool get hasChanges =>
      diffDays != 0 ||
      (newMotoId != null && newMotoId != booking.motoId) ||
      pickupMethod != booking.pickupMethod ||
      returnMethod != booking.returnMethod ||
      extrasTotal > 0 ||
      pickupDelivFee > 0 ||
      returnDelivFee > 0 ||
      helmetSize != booking.helmetSize ||
      jacketSize != booking.jacketSize ||
      pantsSize != booking.pantsSize ||
      bootsSize != booking.bootsSize ||
      glovesSize != booking.glovesSize ||
      passengerHelmetSize != booking.passengerHelmetSize ||
      passengerJacketSize != booking.passengerJacketSize ||
      passengerPantsSize != booking.passengerPantsSize;
}
