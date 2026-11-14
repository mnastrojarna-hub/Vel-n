// Repair "e_last2" (2026-11-13), new look only: the K4-02 fix (Profil keeps
// its place while the personal form switches pull-to-refresh off) is opt-in
// on MgPage. Every other page keeps the earlier behaviour: when its
// pull-to-refresh follows a mode (Motorky calculator -> list, Moje jízdy
// sub-tabs), the new mode opens at the top with the mode switch and the
// dates in view.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';

import '../journey/journey_rig.dart';
import '../journey/journey_states.dart';

class _Toggle extends StatefulWidget {
  final bool keep;
  final ScrollController ctrl;
  const _Toggle({required this.keep, required this.ctrl});
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool refresh = true;
  void set(bool v) => setState(() => refresh = v);
  @override
  Widget build(BuildContext context) => MgPage(
        controller: widget.ctrl,
        keepScrollOnRefreshToggle: widget.keep,
        onRefresh: refresh ? () async {} : null,
        slivers: [SliverList.list(children: [for (var i = 0; i < 60; i++) SizedBox(height: 60, child: Text('row $i'))])],
      );
}

double _offset(ScrollController c) => c.positions.last.pixels;

void main() {
  for (final keep in [false, true]) {
    testWidgets('MgPage: refresh toggle ${keep ? 'keeps the place (opt-in)' : 'opens at the top (default)'}', (t) async {
      final ctrl = ScrollController();
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(home: _Toggle(keep: keep, ctrl: ctrl)),
      ));
      ctrl.jumpTo(800);
      await t.pump();
      expect(_offset(ctrl), 800);
      final st = t.state<_ToggleState>(find.byType(_Toggle));
      st.set(false);
      await t.pump();
      expect(_offset(ctrl), keep ? 800 : 0);
      st.set(true);
      await t.pump();
      expect(_offset(ctrl), keep ? 800 : 0);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('Motorky: calculator scrolled down -> "Zobrazit volné motorky" opens the list at the top', (t) async {
    final rig = await JourneyRig.boot(t, JourneyState.ready);
    await t.tapAt(t.getCenter(find.text('Motorky').hitTestable().first));
    await rig.settle();
    await t.tapAt(t.getCenter(find.text('Spočítat cenu').hitTestable().first));
    await rig.settle();
    expect(find.byType(MotorkyScreenV2), findsOneWidget);
    final page = find.descendant(of: find.byType(MotorkyScreenV2), matching: find.byType(Scrollable)).first;
    ScrollPosition pos() => t.state<ScrollableState>(page).position;
    pos().jumpTo(600);
    await rig.settle();
    expect(pos().pixels, greaterThan(300), reason: 'calculator scrolled down');
    // The last write of the calculator's "Zobrazit volné motorky" (_showFree).
    ProviderScope.containerOf(t.element(find.byType(MotorkyScreenV2))).read(catalogModeProvider.notifier).state = CatalogMode.find;
    await rig.settle();
    expect(pos().pixels, 0, reason: 'the list opens at the top');
    expect(find.text('Najít motorku').hitTestable(), findsWidgets, reason: 'mode switch in view');
    expect(t.takeException(), isNull);
    await rig.dispose();
  });
}
