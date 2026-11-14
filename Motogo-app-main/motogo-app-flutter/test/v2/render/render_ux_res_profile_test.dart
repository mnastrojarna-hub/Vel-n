// verify:render — res_profile package (RP-*) views: large text + reduced
// motion, 8 languages × 320 / 360 / 412 (MG_VERIFY_RENDER=1).
import '../support/fakes_home.dart' show mockPathProvider;
import 'cases_ux_res_profile.dart';
import 'render_harness.dart';

void main() => renderMatrix(resProfileUxCases(), setUpAllExtra: () async => mockPathProvider());
