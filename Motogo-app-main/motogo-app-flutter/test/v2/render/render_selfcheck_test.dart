// verify:render self-check: the inspector really reports overflow, clipped
// / truncated / bleeding text, raw keys and fallback-language strings
// (each probe must produce its finding; a clean frame produces none).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';

import 'render_inspect.dart';

Future<List<RFinding>> _probe(WidgetTester t, Widget w, {String lang = 'de'}) async {
  t.view.physicalSize = const Size(320, 690) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SafeArea(child: w))));
  t.takeException();
  return inspectFrame(t.binding.renderViews.first, lang, const Size(320, 690));
}


void main() {
  testWidgets('clean frame → no failing findings', (t) async {
    final f = await _probe(t, const Center(child: Text('Hallo')));
    expect(f.where((x) => x.fail), isEmpty);
  });
  testWidgets('ellipsized app copy → truncated-ui', (t) async {
    final s = translations['de']!['v2CalNote']!;
    final f = await _probe(t, SizedBox(width: 80, child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis)));
    expect(f.map((x) => x.kind), contains('truncated-ui'));
  });
  testWidgets('text cut by a fixed box → clipped / text-box-overflow', (t) async {
    final f = await _probe(t, const Align(alignment: Alignment.topLeft, child: ClipRect(child: SizedBox(width: 60, height: 12, child: OverflowBox(maxHeight: 200, alignment: Alignment.topLeft, child: Text('Erneut versuchen bitte jetzt'))))));
    expect(f.map((x) => x.kind), contains('clipped'));
    final g = await _probe(t, const Align(alignment: Alignment.topLeft, child: SizedBox(width: 60, height: 12, child: Text('Erneut versuchen bitte jetzt', overflow: TextOverflow.clip))));
    expect(g.map((x) => x.kind), contains('text-box-overflow'));
  });
  testWidgets('raw key and fallback string are reported', (t) async {
    // A probe key only English has → German shows the English text.
    translations['en']!['zzRenderProbeOnlyEn'] = 'Only in English probe sentence';
    addTearDown(() => translations['en']!.remove('zzRenderProbeOnlyEn'));
    final f = await _probe(t, const Column(children: [Text('v2CalNote'), Text('Only in English probe sentence')]), lang: 'nl');
    expect(f.map((x) => x.kind), containsAll(['raw-key', 'fallback']));
  });
  testWidgets('labels inside ExcludeSemantics / Semantics(excludeSemantics) are inspected', (t) async {
    final s = translations['de']!['v2CalNote']!;
    final f = await _probe(t, Column(children: [
      ExcludeSemantics(child: SizedBox(width: 80, child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis))),
      Semantics(excludeSemantics: true, label: 'x', child: const SizedBox(width: 60, child: Text('Termin & Übergabe', maxLines: 1, softWrap: false, overflow: TextOverflow.fade))),
    ]));
    expect(f.map((x) => x.kind), containsAll(['truncated-ui', 'text-box-overflow']));
  });
  testWidgets('a word split across lines → word-break; a normal wrap → nothing', (t) async {
    final rec = translations['cs']!['rideRecording']!.toUpperCase();
    final f = await _probe(t, SizedBox(width: 48, child: Text(rec)), lang: 'cs');
    expect(f.map((x) => x.kind), contains('word-break-ui'));
    final g = await _probe(t, const SizedBox(width: 200, child: Text('Erneut versuchen bitte jetzt')));
    expect(g.map((x) => x.kind), isNot(contains(startsWith('word-break'))));
  });
  testWidgets('text pushed off the right edge → offscreen', (t) async {
    final f = await _probe(t, const OverflowBox(maxWidth: 900, alignment: Alignment.centerLeft, child: Text('Sehr lange Beschriftung die nicht passt und rechts aus dem Bildschirm läuft ganz weit')));
    expect(f.map((x) => x.kind), anyOf(contains('offscreen'), contains('clipped')));
  });
}
