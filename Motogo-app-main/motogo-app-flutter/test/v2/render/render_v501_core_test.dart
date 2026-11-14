// verify:render — v5.0.1 shared pieces (motorcycle glyph, neon menu,
// branch chip).
import 'render_harness.dart';
import 'cases_v501_core.dart';

void main() => renderMatrix(v501CoreCases(), setUpAllExtra: loadMaterialIconsFont);
