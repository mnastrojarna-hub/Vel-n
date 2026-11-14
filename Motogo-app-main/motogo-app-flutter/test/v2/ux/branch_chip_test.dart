// Branch chip for a bike photo (owner v5.0.1: "v horním pravém rohu fotky
// … kde se to nachází … důrazně výrazný, třeba zelený"): the label (short
// branch name + mode) and the chip (one line, ellipsis, max width).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/widgets/mg_branch_chip.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';

import '../support/v2_harness.dart';

String? _label(String? name, String? city, String? type) =>
    mgBranchChipLabel(name: name, city: city, type: type, self: 'samoobsluha', staffed: 's obsluhou');

void main() {
  setUpAll(loadMontserrat);

  test('short name drops the brand; city as fallback; null without a branch', () {
    expect(mgBranchShortName('MotoGo24 Mezná', 'Pelhřimov'), 'Mezná');
    expect(mgBranchShortName('MotoGo 24 – Velké Němčice', null), 'Velké Němčice');
    expect(mgBranchShortName('MotoGo Mezná', null), 'Mezná');
    expect(mgBranchShortName('motogo24: Brno', null), 'Brno');
    expect(mgBranchShortName('Mezná', null), 'Mezná');
    expect(mgBranchShortName('Motocentrum Jih', null), 'Motocentrum Jih', reason: 'only the brand prefix is cut');
    expect(mgBranchShortName('MotoGo24', 'Pelhřimov'), 'Pelhřimov');
    expect(mgBranchShortName('  ', ' '), isNull);
    expect(mgBranchShortName(null, null), isNull);
  });

  test('label = short name · mode (when the type is known)', () {
    expect(_label('MotoGo24 Mezná', null, 'obslužná'), 'Mezná · s obsluhou');
    expect(_label('MotoGo24 Velké Němčice', null, 'samoobslužná'), 'Velké Němčice · samoobsluha');
    expect(_label('MotoGo24 Mezná', null, null), 'Mezná');
    expect(_label(null, null, 'obslužná'), isNull);
  });

  testWidgets('bike label in the app language (cs / en)', (t) async {
    const m = Motorcycle(id: 'x', model: 'X', branchName: 'MotoGo24 Velké Němčice', branchType: 'samoobslužná');
    String? got;
    for (final lang in ['cs', 'en']) {
      await pumpV2(t, Builder(builder: (c) {
        got = mgBikeBranchChipLabel(t_(c), m);
        return const SizedBox();
      }), lang: lang);
      expect(got, lang == 'cs' ? 'Velké Němčice · samoobsluha' : 'Velké Němčice · self-service');
    }
  });

  testWidgets('chip: one line, ellipsis, never wider than maxWidth', (t) async {
    expect(mgBranchChipMaxWidth(360), moreOrLessEquals(223.2));
    expect(mgBranchChipMaxWidth(150), 120);
    expect(mgBranchChipMaxWidth(800), 250);
    await pumpV2(
      t,
      const Align(
        alignment: Alignment.topRight,
        child: MgBranchChip(label: 'Velké Němčice u Brna · samoobsluha nonstop', maxWidth: 160),
      ),
    );
    final box = t.getSize(find.byKey(const ValueKey('mg-branch-chip')));
    expect(box.width, lessThanOrEqualTo(160));
    expect(box.height, lessThan(32), reason: 'one line');
    final text = t.widget<Text>(find.textContaining('Velké Němčice'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(t.takeException(), isNull);
  });

  testWidgets('chip: a label that does not fit falls back to the name (the mode is dropped, not cut)', (t) async {
    await pumpV2(
      t,
      const Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        MgBranchChip(key: ValueKey('wide'), label: 'Mezná · s obsluhou', shortLabel: 'Mezná', maxWidth: 220),
        MgBranchChip(key: ValueKey('narrow'), label: 'Velké Němčice · samoobsluha', shortLabel: 'Velké Němčice', maxWidth: 150),
      ]),
    );
    expect(find.descendant(of: find.byKey(const ValueKey('wide')), matching: find.text('Mezná · s obsluhou')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('narrow')), matching: find.text('Velké Němčice')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

AppTranslations t_(BuildContext c) => t(c);
