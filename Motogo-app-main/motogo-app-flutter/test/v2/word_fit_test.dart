// MgWordFit (shared v2 typography rule): a label never splits inside a word
// — it scales down first, wraps at spaces only, answers intrinsics (safe in
// IntrinsicHeight) and stays a normal Text for finders / taps.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/widgets/mg_word_fit.dart';

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(data: const MediaQueryData(), child: Center(child: child)),
    );

const _style = TextStyle(fontSize: 16, height: 1, fontFamily: 'FlutterTest');

void main() {
  testWidgets('a long single word scales down instead of breaking', (t) async {
    await t.pumpWidget(_host(const SizedBox(
      width: 140,
      child: MgWordFit(child: Text('Bearbeiten', style: _style, maxLines: 2)),
    )));
    final p = t.renderObject<RenderParagraph>(find.text('Bearbeiten'));
    // One line (16 px) — the 160 px word was laid out at 140 / 0.875.
    expect(p.size.height, 16);
    final box = t.getSize(find.byType(MgWordFit));
    expect(box.width, lessThanOrEqualTo(140));
    expect(box.height, closeTo(14, 0.01));
    expect(t.takeException(), isNull);
  });

  testWidgets('wraps at spaces when every word fits (no scaling)', (t) async {
    await t.pumpWidget(_host(const SizedBox(
      width: 100,
      child: MgWordFit(child: Text('ab cd ef gh', style: _style)),
    )));
    final p = t.renderObject<RenderParagraph>(find.text('ab cd ef gh'));
    expect(p.size.height, 32); // two lines at full size
    expect(t.getSize(find.byType(MgWordFit)).height, 32);
  });

  testWidgets('single-line text scales the whole line', (t) async {
    await t.pumpWidget(_host(const SizedBox(
      width: 150,
      child: MgWordFit(minScale: 0.5, child: Text('abcd efgh ij', style: _style, maxLines: 1, softWrap: false)),
    )));
    final p = t.renderObject<RenderParagraph>(find.text('abcd efgh ij'));
    expect(p.didExceedMaxLines, isFalse);
    expect(t.getSize(find.byType(MgWordFit)).width, lessThanOrEqualTo(150));
  });

  testWidgets('works inside IntrinsicHeight and stays tappable', (t) async {
    var taps = 0;
    await t.pumpWidget(_host(SizedBox(
      width: 200,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: GestureDetector(
              onTap: () => taps++,
              child: const MgWordFit(child: Text('Nejrychlejší', style: _style, maxLines: 2)),
            ),
          ),
          const Expanded(child: MgWordFit(child: Text('Doporučené', style: _style, maxLines: 2))),
        ]),
      ),
    )));
    expect(t.takeException(), isNull);
    await t.tap(find.text('Nejrychlejší'));
    expect(taps, 1);
    // 12 × 16 = 192 px word in a 100 px column → scaled to the 0.8 floor.
    expect(t.getSize(find.byType(IntrinsicHeight)).height, greaterThan(0));
  });
}
