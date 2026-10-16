// verify:render — Profil v2 hub, permissions, branches, loyalty, sheets
// and dialogs (large text + reduced motion, 8 languages × 320/360/412).
import '../support/fakes_home.dart' show mockPathProvider;
import 'cases_profile.dart';
import 'render_harness.dart';

void main() => renderMatrix(profileRenderCases(), setUpAllExtra: () async => mockPathProvider());
