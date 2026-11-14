// verify:render — v5.0.1 bike filter card + Motorky list (+ the Material
// Icons font, so the motorcycle glyph is drawn, not a box).
import 'render_harness.dart';
import 'cases_v501_core.dart' show loadMaterialIconsFont;
import 'cases_v501_filter.dart';

void main() => renderMatrix(v501FilterCases(), setUpAllExtra: loadMaterialIconsFont);
