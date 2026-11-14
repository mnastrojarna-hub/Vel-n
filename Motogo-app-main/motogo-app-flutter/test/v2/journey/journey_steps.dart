// Journey rig — step script runner. A script is a JSON array of steps:
//   {"tap":[x,y]}          tap at logical px of the 360×780 screen (= PNG px)
//   {"tapText":"…"}        tap the first visible, tappable text (exact, then
//                          contains); {"tapText":"…","index":1} = 2nd match
//   {"type":"…"}           replace the text of the focused field
//   {"scroll":[x,y,dy]}    drag from (x,y); dy > 0 reveals content BELOW
//   {"swipe":[x,y,dy]}     quick flick over dy px (snapping lists: next item)
//   {"back":true}          system back (Android back button / predictive back)
//   {"wait":ms}            let time pass
//   {"go":"/path"}         JUMP: router.go — not a click, logged as JUMP
//   {"tapKey":"motoFltClear"}  tapText with the Czech text of an i18n key
//   {"tapType":"MotoFilterCardV2","dy":24}  tap a widget by its class name,
//                          at its centre x and dy px below its top
//                          (no dy = its centre); "index" = n-th match
//   {"lifecycle":"pause"|"resume"|"cycle"}  app to background / back
//   {"note":"…"}           any step may carry a note (copied to the log)
// After every step the rig settles and writes <dir>/<nn>.png + one log line.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';

import 'journey_backend.dart';
import 'journey_media.dart';
import 'journey_rig.dart';
import '../support/shot_images.dart' show shotImagesOn;

const _detectors = {'GestureDetector', 'RawGestureDetector', 'InkWell', 'InkResponse'};

/// What is under (x,y): the topmost semantics node with a tap action (its
/// label) and the nearest gesture widget + its nearest app widget.
String probe(WidgetTester tester, Offset p) {
  final root = tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  SemanticsNode? best, labelled;
  void walk(SemanticsNode n, Matrix4 parent) {
    final m = n.transform == null ? parent : parent.multiplied(n.transform!);
    final r = MatrixUtils.transformRect(m, n.rect);
    final data = n.getSemanticsData();
    if (r.contains(p * tester.view.devicePixelRatio) && !n.isInvisible) {
      if (data.hasAction(SemanticsAction.tap) || data.flagsCollection.isTextField) best = n;
      if (data.label.isNotEmpty || data.value.isNotEmpty) labelled = n;
    }
    n.visitChildren((c) {
      walk(c, m);
      return true;
    });
  }

  if (root != null) walk(root, Matrix4.identity());
  String? sem;
  final pick = best ?? labelled;
  if (pick != null) {
    final d = pick.getSemanticsData();
    final label = [d.label, d.value].where((s) => s.isNotEmpty).join(' / ').replaceAll('\n', ' ');
    sem = '"${label.length > 80 ? '${label.substring(0, 80)}…' : label}"';
  }
  // Gesture widget under the point.
  final hit = HitTestResult();
  tester.binding.hitTestInView(hit, p, tester.view.viewId);
  String? widget = hit.path.any((e) => e.target is RenderEditable) ? 'TextField' : null;
  for (final e in widget == null ? hit.path : const <HitTestEntry>[]) {
    final t = e.target;
    if (t is! RenderObject) continue;
    final c = t.debugCreator;
    if (c is! DebugCreator) continue;
    String? det;
    String? app;
    c.element.visitAncestorElements((a) {
      final name = a.widget.runtimeType.toString();
      if (det == null && _detectors.contains(name)) {
        det = name;
      } else if (det != null && (name.startsWith('Mg') || name.endsWith('V2') || name.endsWith('Button') ||
          name.contains('Tile') || name.contains('Card') || name.contains('Chip'))) {
        app = name;
        return false;
      }
      return true;
    });
    if (det != null) {
      widget = app == null ? det : '$app>$det';
      break;
    }
  }
  if (best == null && widget == null) return 'MISS (nothing tappable here${sem == null ? '' : '; under the finger: $sem'})';
  return 'HIT ${sem ?? '(no label)'} <${widget ?? 'semantics only'}>';
}

/// True when a dialog / bottom sheet / popup sits on top.
bool modalOpen() => find
    .byWidgetPredicate((w) => w is ModalBarrier && (w.dismissible || (w.color != null && w.color!.a > 0)))
    .evaluate()
    .isNotEmpty;

Future<String> _tapText(JourneyRig rig, String text, int index) async {
  final t = rig.tester;
  for (final f in [find.text(text, findRichText: true), find.textContaining(text, findRichText: true)]) {
    final hits = f.hitTestable().evaluate().toList();
    if (hits.length > index) {
      final box = hits[index].renderObject as RenderBox;
      final c = box.localToGlobal(box.size.center(Offset.zero));
      final what = probe(t, c);
      await t.tapAt(c);
      return '@(${c.dx.round()},${c.dy.round()}) $what';
    }
  }
  return 'NOT FOUND (no visible text "$text")';
}

Future<void> _scroll(WidgetTester t, Offset from, double dy) async {
  // Slow drag + hold before release = exact distance, no fling.
  final g = await t.startGesture(from, kind: PointerDeviceKind.touch);
  const steps = 12;
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(0, -dy / steps));
    await t.pump(const Duration(milliseconds: 16));
  }
  await t.pump(const Duration(milliseconds: 200));
  await g.up();
}

/// Runs [steps]; writes `<dir>/00.png` (boot) … `<dir>/<nn>.png` + log.txt.
Future<void> runJourney(JourneyRig rig, List<dynamic> steps, String dir) async {
  // The same debug-only assertion as [JourneyRig.guard], when the framework
  // reports it through FlutterError.onError (a notifier fired during a
  // build): logged as DEBUG-ASSERT, everything else still fails the run.
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final msg = d.exceptionAsString();
    if (msg.contains('markNeedsBuild() called during build')) {
      final who = RegExp(r'This (\w+) widget cannot be marked').firstMatch(msg)?.group(1) ?? '?';
      final by = '${d.stack}'.split('\n').where((l) => l.contains('package:motogo_app')).take(1).join().trim();
      rig.debugAsserts.add('markNeedsBuild during build ($who; $by)');
      return;
    }
    prev?.call(d);
  };
  try {
    await _run(rig, steps, dir);
  } finally {
    FlutterError.onError = prev;
  }
}

Future<void> _run(JourneyRig rig, List<dynamic> steps, String dir) async {
  final t = rig.tester;
  // Fake (test) time since boot, so a script's waits can be read.
  final t0 = t.binding.clock.now();
  String clock() => ' | t=${(t.binding.clock.now().difference(t0).inMilliseconds / 1000).toStringAsFixed(1)}s';
  Directory(dir).createSync(recursive: true);
  final log = File('$dir/log.txt')..writeAsStringSync('');
  void line(String s) => log.writeAsStringSync('$s\n', mode: FileMode.append);
  line('state=${rig.data.state.id} size=360x780 lang=cs textScale=1.0 reducedMotion=${rig.motion ? 'off' : 'on'} flag=${rig.v2 ? 'v2' : 'old'}'
      ' photos=${shotImagesOn ? 'real' : 'placeholder'} video=${journeyVideoMode ?? 'app'}');
  String err() {
    final e = t.takeException();
    final dbg = rig.debugAsserts.toSet().map((a) => ' | DEBUG-ASSERT $a').join();
    rig.debugAsserts.clear();
    return (e == null ? '' : ' | EXCEPTION ${'$e'.split('\n').first}') + dbg;
  }

  await rig.shot('$dir/00.png');
  line('00 | boot | route=${rig.location} | modal=${modalOpen() ? 'yes' : 'no'}${err()}');
  for (var i = 0; i < steps.length; i++) {
    final n = (i + 1).toString().padLeft(2, '0');
    final s = Map<String, dynamic>.from(steps[i] as Map);
    final before = journeyRequests.length;
    var what = '';
    try {
      what = await rig.guard(() => _step(rig, s));
      await rig.settle();
    } catch (e) {
      what = '$what | STEP FAILED ${'$e'.split('\n').first}';
    }
    await rig.shot('$dir/$n.png');
    final calls = journeyRequests.sublist(before).toSet().take(6).join(', ');
    final note = s['note'] == null ? '' : ' | note=${s['note']}';
    final step = jsonEncode(Map.of(s)..remove('note'));
    line('$n | $step | $what | route=${rig.location} | modal=${modalOpen() ? 'yes' : 'no'}'
        '${calls.isEmpty ? '' : ' | server=[$calls]'}${clock()}$note${err()}');
  }
}

/// One step's action; returns what it hit / did.
Future<String> _step(JourneyRig rig, Map<String, dynamic> s) async {
  final t = rig.tester;
  var what = '';
  if (s['tap'] is List) {
    final p = Offset((s['tap'][0] as num).toDouble(), (s['tap'][1] as num).toDouble());
    what = probe(t, p);
    await t.tapAt(p);
  } else if (s['tapText'] is String) {
    what = await _tapText(rig, s['tapText'] as String, (s['index'] as num?)?.toInt() ?? 0);
  } else if (s['type'] is String) {
    if (!t.testTextInput.hasAnyClients) {
      what = 'NO FOCUSED FIELD (tap a field first)';
    } else {
      t.testTextInput.enterText(s['type'] as String);
      what = 'typed';
    }
  } else if (s['scroll'] is List) {
    final a = s['scroll'] as List;
    await _scroll(t, Offset((a[0] as num).toDouble(), (a[1] as num).toDouble()), (a[2] as num).toDouble());
    what = 'scrolled';
  } else if (s['swipe'] is List) {
    // A quick flick (like a thumb): snapping lists move one item.
    final a = s['swipe'] as List;
    final dy = (a[2] as num).toDouble();
    await t.flingFrom(Offset((a[0] as num).toDouble(), (a[1] as num).toDouble()), Offset(0, -dy), 1200);
    what = 'swiped';
  } else if (s['back'] == true) {
    // ignore: invalid_use_of_protected_member
    final handled = await t.binding.handlePopRoute();
    what = 'system back${handled ? '' : ' (not handled → app would close)'}';
  } else if (s['wait'] is num) {
    await t.pump(Duration(milliseconds: (s['wait'] as num).toInt()));
    what = 'waited';
  } else if (s['tapKey'] is String) {
    final k = s['tapKey'] as String;
    final text = translations['cs']?[k];
    what = text == null
        ? 'UNKNOWN I18N KEY "$k"'
        : 'key $k = "$text" ${await _tapText(rig, text, (s['index'] as num?)?.toInt() ?? 0)}';
  } else if (s['tapType'] is String) {
    what = await _tapType(t, s['tapType'] as String, (s['dy'] as num?)?.toDouble(), (s['index'] as num?)?.toInt() ?? 0);
  } else if (s['lifecycle'] is String) {
    what = await _lifecycle(t, s['lifecycle'] as String);
  } else if (s['go'] is String) {
    rig.router.go(s['go'] as String);
    what = 'JUMP (router.go, not a click)';
  } else {
    what = 'UNKNOWN STEP';
  }
  return what;
}

Future<String> _tapType(WidgetTester t, String type, double? dy, int index) async {
  final hits = find.byWidgetPredicate((w) => w.runtimeType.toString() == type).evaluate().toList();
  if (hits.length <= index) return 'NOT FOUND (no widget $type)';
  final ro = hits[index].renderObject;
  if (ro is! RenderBox || !ro.hasSize) return 'NOT FOUND ($type has no box)';
  final r = ro.localToGlobal(Offset.zero) & ro.size;
  final p = dy == null ? r.center : Offset(r.center.dx, r.top + dy);
  final what = probe(t, p);
  await t.tapAt(p);
  return '$type @(${p.dx.round()},${p.dy.round()}) $what';
}

/// Background (inactive → hidden → paused) and back (→ resumed), in the
/// order the platform reports them.
Future<String> _lifecycle(WidgetTester t, String what) async {
  const pause = [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];
  const resume = [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed];
  final states = switch (what) {
    'pause' => pause,
    'resume' => resume,
    'cycle' => [...pause, ...resume],
    _ => const <AppLifecycleState>[],
  };
  if (states.isEmpty) return 'UNKNOWN LIFECYCLE "$what" (pause | resume | cycle)';
  for (final st in states) {
    t.binding.handleAppLifecycleStateChanged(st);
    await t.pump(const Duration(milliseconds: 50));
  }
  return 'app ${what == 'pause' ? 'in background' : what == 'resume' ? 'back in front' : 'to background and back'}';
}
