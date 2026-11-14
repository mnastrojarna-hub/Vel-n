// verify:render — auth_sos_misc package (ASM-*) views: large text + reduced
// motion, 8 languages × 320 / 360 / 412 (MG_VERIFY_RENDER=1).
import 'cases_ux_auth_sos_misc.dart';
import 'render_harness.dart';

void main() => renderMatrix(authSosMiscUxCases());
