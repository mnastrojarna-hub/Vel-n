import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../catalog/catalog_provider.dart';
import '../catalog/moto_model.dart';
import 'sos_provider.dart';

/// Rental days a free replacement must cover: today → the end of the
/// customer's booking (today when unknown or already past) — the range
/// `sos_swap_bookings` checks on the server.
(DateTime, DateTime) sosReplacementRange(DateTime now, DateTime? bookingEnd) {
  final today = DateTime(now.year, now.month, now.day);
  var end = bookingEnd == null ? today : DateTime(bookingEnd.year, bookingEnd.month, bookingEnd.day);
  if (end.isBefore(today)) end = today;
  return (today, end);
}

/// Bikes worth checking: not the broken one, no trailer, not in
/// maintenance, branch open.
List<Motorcycle> sosReplacementCandidates(List<Motorcycle> all, String? currentMotoId) => [
      for (final m in all)
        if (m.id != currentMotoId && !m.isTrailer && m.status != 'maintenance' && m.branchIsOpen != false) m,
    ];

/// The server refused the bike: `sos_swap_bookings` RAISEs "Vybraná motorka
/// není do konce pronájmu volná — vyberte prosím jinou." (P0001). A retry
/// fails the same way — the customer has to pick another bike.
bool isSosMotoTakenError(Object? e) =>
    e is PostgrestException && e.code == 'P0001' && e.message.contains('do konce pronájmu volná');

/// Replacement bikes the customer may pick: [sosReplacementCandidates] that
/// are FREE for the rest of the rental — the same read-only
/// `motoAvailableForRange` check the catalogue date filter uses, in
/// parallel. Before, the list showed EVERY bike and the server refused the
/// taken ones only after "Potvrdit" (a dead end with Retry). When the
/// incident state is not available (outage) the list still shows, checked
/// for today — the confirm step reports the incident problem with Call /
/// 112 as before.
final sosReplacementMotosProvider = FutureProvider.autoDispose<List<Motorcycle>>((ref) async {
  final all = await ref.watch(motorcyclesProvider.future);
  SosIncident? inc;
  try {
    inc = await ref.watch(activeSosProvider.future);
  } catch (_) {
    inc = null;
  }
  final candidates = sosReplacementCandidates(all, inc?.motoId);
  final (start, end) = sosReplacementRange(DateTime.now(), inc?.bookingEndDate);
  final free = await Future.wait(candidates.map((m) => motoAvailableForRange(m.id, start, end)));
  return [
    for (var i = 0; i < candidates.length; i++)
      if (free[i]) candidates[i],
  ];
});
