// verify:coverage — surfaces drawn with the REAL widget that no other
// render case draws (MG_VERIFY_RENDER=1).
import '../support/fakes_home.dart' show mockPathProvider;
import 'cases_ux_coverage.dart';
import 'render_harness.dart';

void main() => renderMatrix(coverageUxCases(), setUpAllExtra: () async => mockPathProvider());
