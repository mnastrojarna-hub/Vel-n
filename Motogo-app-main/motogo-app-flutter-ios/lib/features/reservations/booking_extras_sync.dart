import 'package:flutter/foundation.dart';

import '../../core/supabase_client.dart';

/// Synchronizace MODELOVANÝCH doplňků (výbava spolujezdce, boty řidiče /
/// spolujezdce) v `booking_extras` při úpravě rezervace z appky.
///
/// Incident 2026-09-28 („ve Velíně dvoje boty / dvoje oblečení“): appka
/// mazala řádky podle českého názvu a živá DB neměla pro zákazníka DELETE
/// politiku → PostgREST bez chyby smazal 0 řádků a následný insert celé sady
/// doplňky ZDVOJIL. Web navíc zapisuje název položky v jazyce zákazníka
/// (Rider boots, Stiefel Fahrer, …), takže český název nestačil ani na čtení.
///
/// Řešení: řádky se rozpoznávají jazykově nezávisle (kořeny názvů), mažou se
/// PODLE ID a počet skutečně smazaných se ověří (`select('id')`). Dokud DELETE
/// politika (`20260928a_booking_extras_owner_delete_dedupe.sql`) není na živé
/// DB, vloží se jen NOVĚ přidané doplňky — nikdy duplicitní.

/// Kořeny názvů bot (cs/en/de/nl/pl/uk; es „Botas“ a fr „Bottes“ pokrývá „bot“).
const _bootsNameRoots = ['bot', 'boots', 'stiefel', 'laarzen', 'buty', 'взуття'];

/// Kořeny názvů výbavy spolujezdce (cs/en/de/nl/es/fr/pl/uk).
const _passengerNameRoots = [
  'spoluj', 'passenger', 'passag', 'beifahrer', 'pasajero', 'pasażer', 'pasazer', 'пасажир',
];

/// Název řádku `booking_extras` → id doplňku appky (`spolujezdec` /
/// `boty_ridic` / `boty_spolujezdec`), nebo null pro nemodelované řádky (vozík,
/// přistavení…). Jazykově nezávislé — web ukládá název v jazyce zákazníka.
String? extraIdFromExtrasName(String name) {
  final n = name.toLowerCase();
  final hasBoots = _bootsNameRoots.any(n.contains);
  final hasPass = _passengerNameRoots.any(n.contains);
  if (hasBoots && hasPass) return 'boty_spolujezdec';
  if (hasBoots) return 'boty_ridic';
  if (hasPass) return 'spolujezdec';
  return null;
}

/// Smaže řádky `booking_extras` podle id a vrátí počet SKUTEČNĚ smazaných
/// (RLS může tiše vrátit 0 — proto `select('id')`).
Future<int> deleteExtrasRowsByIds(String bookingId, List<String> rowIds) async {
  if (rowIds.isEmpty) return 0;
  final res = await MotoGoSupabase.client
      .from('booking_extras')
      .delete()
      .eq('booking_id', bookingId)
      .inFilter('id', rowIds)
      .select('id');
  return (res as List).length;
}

/// Odstraní interní klíče (`_extra` …) z řádků před INSERTem.
Map<String, dynamic> stripInternalKeys(Map row) => {
      for (final e in row.entries)
        if (!e.key.toString().startsWith('_')) e.key.toString(): e.value,
    };

/// Nahradí modelované doplňky: smaže původní řádky ([origRowIds]) a vloží nový
/// stav [rows] (každý řádek nese `_extra` = id doplňku). Když se nepodařilo
/// smazat všechny původní řádky, vloží se JEN doplňky, které v [origExtraIds]
/// nebyly (přidané) — odebrání se pak neprojeví, ale nic se nezdvojí.
Future<void> replaceModeledExtras({
  required String bookingId,
  required List<String> origRowIds,
  required Set<String> origExtraIds,
  required List rows,
}) async {
  var deleted = 0;
  try {
    deleted = await deleteExtrasRowsByIds(bookingId, origRowIds);
  } catch (e) {
    debugPrint('[Extras] delete failed: $e');
  }
  final full = deleted >= origRowIds.length;
  if (!full) {
    debugPrint('[Extras] deleted $deleted/${origRowIds.length} rows — '
        'inserting only newly added extras');
  }
  final toInsert = <Map<String, dynamic>>[
    for (final r in rows)
      if (r is Map && (full || !origExtraIds.contains(r['_extra'])))
        stripInternalKeys(r),
  ];
  if (toInsert.isNotEmpty) {
    await MotoGoSupabase.client.from('booking_extras').insert(toInsert);
  }
}
