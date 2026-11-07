// verify:render — catalog_booking package states (large text + reduced
// motion, 8 languages × 320/360/412).
import '../support/fakes_booking.dart' show mockBookingPathProvider;
import '../support/fakes_home.dart' show mockPathProvider;
import 'cases_ux_catalog_booking.dart';
import 'render_harness.dart';

void main() => renderMatrix(uxCatalogBookingRenderCases(), setUpAllExtra: () async {
      mockPathProvider();
      mockBookingPathProvider();
    });
