// Journey rig — click-through run (README.md). Skipped unless MG_JOURNEY=1:
//   MG_JOURNEY=1 MG_JOURNEY_STATE=ready MG_JOURNEY_SCRIPT=/path/steps.json \
//   MG_JOURNEY_DIR=/path/out flutter test --no-pub test/v2/journey/journey_run_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'journey_rig.dart';
import 'journey_states.dart';
import 'journey_steps.dart';

String? _env(String k) {
  final v = Platform.environment[k];
  return v == null || v.isEmpty ? null : v;
}

void main() {
  final on = _env('MG_JOURNEY') == '1';
  testWidgets('journey run', (tester) async {
    final state = JourneyState.parse(_env('MG_JOURNEY_STATE') ?? 'ready');
    final script = _env('MG_JOURNEY_SCRIPT');
    final steps = script == null ? const <dynamic>[] : jsonDecode(File(script).readAsStringSync()) as List<dynamic>;
    final dir = _env('MG_JOURNEY_DIR') ?? '${Directory.systemTemp.path}/mg_journey';
    final rig = await JourneyRig.boot(tester, state, start: _env('MG_JOURNEY_START'));
    await runJourney(rig, steps, dir);
    await rig.dispose();
    // ignore: avoid_print
    print('journey: ${steps.length} steps → $dir (log.txt + PNGs)');
  }, skip: !on, timeout: const Timeout(Duration(minutes: 20)));
}
