// verify:render — v5.0.1 photo → video + branch chip on bike photos.
import 'cases_v501_core.dart' show loadMaterialIconsFont;
import 'cases_v501_media.dart';
import 'render_harness.dart';

void main() => renderMatrix(v501MediaCases(), setUpAllExtra: loadMaterialIconsFont);
