// verify:render — routes_rides package (F-*) views: large text + reduced
// motion, 8 languages × 320 / 360 / 412 (MG_VERIFY_RENDER=1).
import '../support/fakes_home.dart' show mockPathProvider;
import 'cases_ux_routes_nav.dart';
import 'cases_ux_routes_rides.dart';
import 'render_harness.dart';

void main() => renderMatrix([...routesRidesUxCases(), ...routesNavUxCases()], setUpAllExtra: () async => mockPathProvider());
