// verify:render — catalog v2: Motorky, calculator, sheets, bike detail
// (large text + reduced motion, 8 languages × 320/360/412).
import '../support/fakes_home.dart' show mockPathProvider;
import 'cases_catalog.dart';
import 'render_harness.dart';

void main() => renderMatrix(catalogRenderCases(), setUpAllExtra: () async => mockPathProvider());
