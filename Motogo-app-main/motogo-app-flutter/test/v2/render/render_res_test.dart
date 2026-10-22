// verify:render — Reservations v2 list / detail / edit / dialogs (large
// text + reduced motion, 8 languages × 320/360/412).
import '../support/fakes_home.dart' show mockPathProvider;
import 'cases_res.dart';
import 'render_harness.dart';

void main() => renderMatrix(resRenderCases(), setUpAllExtra: () async => mockPathProvider());
