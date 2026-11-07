// verify:render cases — res_profile package (RP-*): ride feedback sheet,
// "Motorky na pobočkách" sheet (card expanded), document viewer chrome with
// the A4 skeleton, detail of a staffed booking (tiles + navigate CTA) and a
// self-service pickup day with codes. Reservation list / detail / edit and
// the Profil screens come from cases_res.dart / cases_profile*.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/documents/v2/doc_viewer_chrome_v2.dart';
import 'package:motogo_app/features/profile/v2/branches_sheet_v2.dart';
import 'package:motogo_app/features/reservations/v2/ride_feedback_sheet_v2.dart';

import '../screens/reservations_cases.dart';
import '../support/fakes_reservations.dart';
import 'render_harness.dart';

const _branches = [
  {
    'id': 'b1',
    'name': 'MotoGo24 Velké Němčice',
    'address': 'Boudky',
    'city': '691 63 Velké Němčice',
    'type': 'samoobslužná',
    'is_open': true,
    'phone': '+420774256271',
    'branch_code': 'VN',
    'gps_lat': 49.0043,
    'gps_lng': 16.6721,
  },
  {'id': 'b2', 'name': 'MotoGo24 Mezná', 'address': 'Mezná 9', 'city': '393 01 Pelhřimov', 'type': 'obslužná', 'is_open': true},
];

final _motos = {
  'b1': [
    {'id': 'm1', 'model': 'Husqvarna 701 SM', 'brand': 'Husqvarna', 'engine_cc': 693, 'power_kw': 55, 'license_required': 'A'},
    {'id': 'm2', 'model': 'BMW R 1200 GS Adventure', 'brand': 'BMW', 'engine_cc': 1170, 'power_kw': 92, 'license_required': 'A'},
  ],
};

Future<void> _expandFirst(WidgetTester t) async {
  final f = find.text('MotoGo24 Velké Němčice');
  if (f.evaluate().isEmpty) return;
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Widget _feedback() => Align(
      alignment: Alignment.bottomCenter,
      child: RideFeedbackSheetV2(
        res: resv('d5', status: 'completed', from: -6, to: -4),
        rating: 2,
        controller: TextEditingController(),
        sending: false,
        emptyTried: true,
        maxLength: 2000,
        onSend: () {},
      ),
    );

List<RenderCase> resProfileUxCases() {
  final staffed = resv('m1', status: 'reserved', from: 5, to: 7, self: false, bike: 'BMW R 1200 GS Adventure');
  return [
    RenderCase('rpux', 'sheet', 'ride_feedback', _feedback, () => resOverrides()),
    RenderCase('rpux', 'sheet', 'branches_open',
        () => SingleChildScrollView(child: BranchesSheetV2(branches: _branches, motosByBranch: _motos)),
        () => resOverrides(),
        after: _expandFirst),
    RenderCase(
        'rpux',
        'viewer',
        'loading',
        () => DocViewerScaffoldV2(
            title: 'Předávací protokol — Husqvarna 701 SM #55556666', onClose: () {}, body: const DocA4SkeletonV2()),
        () => const [],
        scaffold: false,
        loading: true),
    RenderCase('rpux', 'detail', 'staffed', () => detailView(staffed), () => resOverrides()),
    RenderCase('rpux', 'detail', 'pickup_day',
        () => detailView(resv('d1', status: 'reserved', from: 0, to: 2),
            codes: [code('accessories', '4821'), code('motorcycle', '7395')]),
        () => resOverrides()),
  ];
}
