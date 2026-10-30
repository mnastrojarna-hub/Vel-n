// verify:render — booking form "nic nevyplňovat dvakrát" (large text +
// reduced motion, 8 languages × 320/360/412): answered address row, own
// voucher chips, address quick options, passenger / boots size sheets.
import '../support/fakes_booking.dart' show mockBookingPathProvider;
import 'cases_booking_prefill.dart';
import 'render_harness.dart';

void main() => renderMatrix(bookingPrefillRenderCases(), setUpAllExtra: () async => mockBookingPathProvider());
