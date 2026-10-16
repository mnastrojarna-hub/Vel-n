// verify:render — Home v2 (large text + reduced motion, 8 languages ×
// 320/360/412).
import '../support/fakes_home.dart' show mockPathProvider;
import 'cases_home.dart';
import 'render_harness.dart';

void main() => renderMatrix(homeRenderCases(), setUpAllExtra: () async => mockPathProvider());
