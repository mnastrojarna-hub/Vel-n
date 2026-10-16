// Content parity (PLAN §5.6, "nic nesmí chybět") for the Reservations area:
// every translation key the OLD list / detail / edit screens show must be
// used by the v2 look too (v2 files + the old leaf widgets it keeps), or be
// on the reviewed waiver list below with the reason.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _r = 'lib/features/reservations';

Set<String> _keys(List<String> paths) {
  final out = <String>{};
  final files = <File>[];
  for (final p in paths) {
    if (p.endsWith('/')) {
      files.addAll(Directory(p).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')));
    } else {
      files.add(File(p));
    }
  }
  for (final f in files) {
    final s = f.readAsStringSync();
    for (final re in [
      RegExp(r"tr\('([A-Za-z0-9_.]+)'\)"),
      RegExp(r"trArgs\('([A-Za-z0-9_.]+)'"),
      RegExp(r"t\(context\)\.(?!tr\b|trArgs\b)([a-zA-Z]+)\b"),
      RegExp(r"\btr\.(?!tr\b|trArgs\b|daysWord\b|lang\b)([a-zA-Z]+)\b"),
    ]) {
      out.addAll(re.allMatches(s).map((m) => m.group(1)!));
    }
  }
  return out;
}

void _parity(String name, List<String> old, List<String> v2, Map<String, String> waivers) {
  test('content parity · $name', () {
    final missing = _keys(old).difference(_keys(v2)).difference(waivers.keys.toSet());
    expect(missing, isEmpty, reason: 'old keys not shown by the v2 look (add to v2 or waive with a reason)');
  });
}

void main() {
  const days = 'tr.daysWord() picks the same day1 / days24 / days5 keys per language';
  _parity('list', ['$_r/reservations_screen.dart', '$_r/widgets/reservation_card.dart'], [
    '$_r/v2/',
    '$_r/widgets/cancel_result_dialog.dart',
  ], {
    'cancelReason': 'list storno dialog is unreachable today (card never offers storno); v1 dialog unchanged',
    'cancelReservationTitle': 'same (unreachable list dialog)',
    'currentlyRefund': 'same; v2 detail storno uses it via ResCancelDialog',
    'customerCancelled': 'same; v2 detail storno uses it via ResCancelDialog',
    'day1': days,
    'days24': days,
    'days5': days,
    'noReservations': 'replaced by v2ResEmptyTitle (tykání)',
    'noReservationsDesc': 'replaced by v2ResEmptyBody (old text was formal)',
  });
  _parity('detail', ['$_r/reservation_detail_screen.dart', '$_r/widgets/res_detail_tab_content.dart'], [
    '$_r/v2/',
    '$_r/reservation_detail_screen.dart', // loading / error / open-document paths are shared by both looks
    '$_r/res_actions.dart',
    '$_r/widgets/res_access_codes_card.dart',
    '$_r/widgets/res_pickup_procedure.dart',
    '$_r/widgets/res_payment_details_tab.dart',
    '$_r/widgets/res_location_row.dart',
    '$_r/widgets/res_modification_history.dart',
    '$_r/widgets/res_rating_card.dart',
    '$_r/widgets/res_cancel_dialog.dart',
  ], {
    'detailTab': 'the two tabs became sections of one page (paymentDetailsTab kept as the expander)',
    'payment': '"Platba" row → translated payment-status pill in Peníze',
    'resCategory': 'category shown in the title meta line without the label',
    'resDetailTitle': 'header → photo hero + status pill + "Rezervace #ID" eyebrow',
    'resDurationTotal': 'same value as Délka, shown once as the "3 dny" chip',
    'ssLateGateNote': 'replaced by v2ResLateGate (same content, tykání)',
  });
  _parity('edit', [
    '$_r/reservation_edit_screen.dart',
    '$_r/widgets/reservation_edit_calendar_section.dart',
    '$_r/widgets/reservation_edit_confirm_page.dart',
  ], [
    '$_r/v2/',
    '$_r/reservation_edit_screen.dart', // the State (save, messages) is shared by both looks
  ], {
    'day1': days,
    'days24': days,
    'days5': days,
    'existingLabel': 'old legend → TripLegend (v2CalLeg*)',
    'freeLabel': 'old legend → TripLegend (v2CalLeg*)',
    'moveLegendNew': 'old legend → TripLegend (v2CalLeg*)',
    'occupiedLabel': 'old legend → TripLegend (v2CalLeg*)',
    'shortenedLabel': 'old legend → TripLegend (v2CalLeg*)',
    'extensionWord': 'day delta shown as the "+1 den" chip',
    'shorteningWord': 'day delta shown as the "−1 den" chip',
    'yourActiveReservation': 'original term + status in the header "TEĎ" row',
    'yourUpcomingReservation': 'original term + status in the header "TEĎ" row',
  });
}
