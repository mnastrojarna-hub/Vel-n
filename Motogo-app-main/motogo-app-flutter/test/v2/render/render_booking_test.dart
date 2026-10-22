// verify:render — booking form v2 (large text + reduced motion, 8
// languages × 320/360/412).
import '../support/fakes_booking.dart' show mockBookingPathProvider;
import 'cases_booking.dart';
import 'render_harness.dart';

void main() => renderMatrix(bookingRenderCases(), setUpAllExtra: () async => mockBookingPathProvider());
