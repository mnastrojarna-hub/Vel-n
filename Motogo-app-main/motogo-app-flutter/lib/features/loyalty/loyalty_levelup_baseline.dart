import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/supabase_client.dart';
import 'loyalty_provider.dart' show LoyaltyStatus;

/// Co o „už oslaveno" řekl server (`profiles.loyalty_celebrated_level`).
class CelebratedRead {
  /// Hodnota ze serveru (0 = účet ještě nikdy nebyl pozorován), jinak null.
  final int? level;

  /// RPC v databázi vůbec není (pořadí nasazení) → původní lokální režim.
  final bool missing;

  const CelebratedRead.value(int this.level) : missing = false;

  /// Server teď neodpověděl (síť, timeout, chyba) → baseline NEZNÁME.
  const CelebratedRead.unknown()
      : level = null,
        missing = false;
  const CelebratedRead.missing()
      : level = null,
        missing = true;

  bool get known => level != null;
}

enum LevelUpAction {
  /// Není co slavit (level ≤ už oslavený).
  none,

  /// Úplně první pozorování účtu → jen zaznamenat, neslavit.
  seed,

  /// Level je výš než baseline → oslava (`gained` = o kolik).
  celebrate,

  /// Baseline teď nejde zjistit a oslava by mohla být duplicitní i oprávněná
  /// → tuhle kontrolu přeskočit a zkusit to znovu.
  unknown,
}

class LevelUpDecision {
  final LevelUpAction action;
  final int gained;
  const LevelUpDecision(this.action, [this.gained = 0]);
}

/// Rozhodnutí o oslavě — čistá funkce (testy: loyalty_levelup_baseline_test).
///
/// Baseline = max(server, lokální značka [marker]). Značka je level, který
/// TENTO telefon opravdu oslavil (nebo jím účet poprvé zaznamenal), takže:
///  * selže-li po oslavě zápis na server, další kontrola neslaví podruhé;
///  * selže-li zápis prvního pozorování, další povýšení se nespolkne.
/// Když server neodpoví, neslavíme z lokálních dat (level mohl být oslaven na
/// jiném telefonu) ani nic nezapisujeme — kontrola se zopakuje.
/// [legacy] (`mg_loyalty_last_level_*`) platí jen bez RPC v databázi.
LevelUpDecision decideLevelUp({
  required int level,
  required CelebratedRead server,
  required int? marker,
  required int? legacy,
}) {
  final int base;
  if (server.missing) {
    base = math.max(legacy ?? 0, marker ?? 0);
  } else if (!server.known) {
    if (marker != null && level <= marker) {
      return const LevelUpDecision(LevelUpAction.none);
    }
    return const LevelUpDecision(LevelUpAction.unknown);
  } else {
    base = math.max(server.level!, marker ?? 0);
  }
  if (base <= 0) return const LevelUpDecision(LevelUpAction.seed);
  if (level <= base) return const LevelUpDecision(LevelUpAction.none);
  return LevelUpDecision(LevelUpAction.celebrate, level - base);
}

/// Lokální stav oslavy JEDNOHO účtu + čtení / zápis serverového „oslaveno".
///
/// [uid] se zachytí na začátku kontroly: klíče i zápis na server patří jemu.
/// Přihlásí-li se během čekání jiný účet, na server se nic nepošle
/// ([sameUser]) — jinak by level účtu A skončil jako „oslaveno" u účtu B.
class LevelUpBaseline {
  LevelUpBaseline(this._prefs, this.uid);

  final SharedPreferences _prefs;
  final String uid;

  /// Strop pro oba dotazy. Supabase/postgrest sám žádný timeout nemá, takže
  /// na mrtvém-ale-otevřeném socketu by await visel minuty — a protože
  /// hlídač drží latch `_showing`, zablokovalo by to oslavu do restartu appky.
  static const rpcTimeout = Duration(seconds: 5);

  // Prefix `mg_loyalty_` přežije úklid cache (CacheCleanupService).
  String get _markerKey => 'mg_loyalty_celebrated_$uid';
  String get _lvlKey => 'mg_loyalty_last_level_$uid';
  String get _colorKey => 'mg_loyalty_last_color_$uid';

  bool get sameUser => MotoGoSupabase.currentUser?.id == uid;

  /// Level, který tento telefon opravdu oslavil (nebo jím účet seednul).
  int? get marker => _prefs.getInt(_markerKey);

  /// Naposledy viděný level — baseline jen pro režim bez serverového RPC.
  int? get legacyLevel => _prefs.getInt(_lvlKey);

  /// Barva ranku před povýšením (z ní se logo v oslavě přeblikne na novou).
  String? get lastColorHex => _prefs.getString(_colorKey);

  /// Značka jen roste (stejně jako `GREATEST` na serveru).
  Future<void> raiseMarker(int level) async {
    if (level > (marker ?? 0)) await _prefs.setInt(_markerKey, level);
  }

  Future<void> mirror(LoyaltyStatus status) async {
    await _prefs.setInt(_lvlKey, status.level);
    await _prefs.setString(_colorKey, status.colorHex);
  }

  /// „Už oslaveno na level N" — SERVER je zdroj pravdy (`profiles`), takže
  /// povýšení přežije reinstal, nové zařízení i smazaná data.
  Future<CelebratedRead> readServer() async {
    if (!sameUser) return const CelebratedRead.unknown();
    try {
      final Future<dynamic> call =
          MotoGoSupabase.client.rpc('loyalty_get_celebrated');
      final res = await call.timeout(rpcTimeout);
      if (res is num) return CelebratedRead.value(res.toInt());
      // Řádek profilu ještě není (čerstvá registrace) / nečekaná odpověď.
      return const CelebratedRead.unknown();
    } on PostgrestException catch (e) {
      return _rpcMissing(e)
          ? const CelebratedRead.missing()
          : const CelebratedRead.unknown();
    } catch (_) {
      return const CelebratedRead.unknown();
    }
  }

  /// Zapíše „oslaveno" na server (`GREATEST` → napříč zařízeními jen jednou).
  /// false = nezapsáno; hlídač to při další kontrole zkusí znovu.
  Future<bool> advanceServer(int level) async {
    if (!sameUser) return false;
    try {
      final Future<dynamic> call = MotoGoSupabase.client
          .rpc('loyalty_advance_celebrated', params: {'p_level': level});
      await call.timeout(rpcTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Funkce v DB není / není povolená — trvalý stav, ne výpadek sítě.
  static bool _rpcMissing(PostgrestException e) => const {
        'PGRST202', // funkce není v cache schématu
        '42883', // undefined_function
        '42501', // insufficient_privilege
        '404',
      }.contains(e.code);
}
