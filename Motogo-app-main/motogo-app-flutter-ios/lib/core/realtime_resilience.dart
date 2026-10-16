import 'dart:async';

import 'auth_guard.dart';
import 'friendly_error.dart';

/// Realtime odběr, který přežije výpadek spojení (2026-10-16).
///
/// Dřív providery (Zprávy, SOS) chybu kanálu `rethrow`-ly — nejsou
/// autoDispose, takže po jediném výpadku websocketu / chvíli bez signálu
/// zůstaly v chybě na celou session („Chyba", odznak nepřečtených 0, zmizel
/// banner SOS). Tady: první data už provider má; při chybě kanálu počká
/// (3 s → max 60 s), znovu načte data a znovu se přihlásí k odběru.
/// Chyba přihlášení dál vede na odhlášení (`handleAuthError`).
///
/// [map] = data přímo z události kanálu (bez dalšího dotazu); jinak [fetch].
Stream<T> resilientRealtime<T, E>(
  Stream<E> Function() subscribe,
  Future<T> Function() fetch, {
  T Function(E event)? map,
}) async* {
  var delay = 3;
  while (true) {
    try {
      await for (final event in subscribe()) {
        yield map != null ? map(event) : await fetch();
        delay = 3;
      }
      return; // kanál skončil řádně
    } catch (e) {
      if (await handleAuthError(e)) return;
      FriendlyError.log('realtime_retry', e);
    }
    await Future<void>.delayed(Duration(seconds: delay));
    delay = delay >= 30 ? 60 : delay * 2;
    try {
      yield await fetch();
    } catch (_) {/* pořád offline — další pokus po prodlevě */}
  }
}
