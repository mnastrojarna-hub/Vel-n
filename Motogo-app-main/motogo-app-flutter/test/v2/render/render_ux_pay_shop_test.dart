// verify:render — pay_shop package states (large text + reduced motion,
// 8 languages × 320/360/412).
import '../support/fakes_booking.dart' show mockBookingPathProvider;
import 'cases_ux_pay_shop.dart';
import 'render_harness.dart';

void main() => renderMatrix(uxPayShopRenderCases(), setUpAllExtra: () async => mockBookingPathProvider());
