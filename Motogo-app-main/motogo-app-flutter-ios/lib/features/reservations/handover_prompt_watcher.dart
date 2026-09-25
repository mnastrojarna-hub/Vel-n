import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../../main.dart' show rootNavigatorKey;
import 'protocol_screen.dart' show ProtocolScreen;
import 'reservation_models.dart';
import 'reservation_provider.dart';

/// Vynucený předávací protokol (samoobslužná pobočka, 2026-09-25).
///
/// Kiosk při zavření šatny / zadání kódu motorky zapíše
/// `bookings.handover_protocol_prompted_at`; appka to dostane real-time přes
/// stream rezervací (`reservationsProvider`) a KAŽDOU novou hodnotu — dokud
/// protokol není podepsaný — otevře jako [ProtocolScreen] přes celou obrazovku
/// (top-level route bez spodní lišty, zavřít lze). Naposledy zobrazená výzva
/// se pamatuje v SharedPreferences (`protocol_prompt_<bookingId>`), takže se
/// stejná výzva po restartu neopakuje. Na pozadí se nic neotevírá — dožene se
/// při návratu appky do popředí. Sedí NAD celou navigací (main.dart Stack),
/// proto funguje z libovolné obrazovky a drží stream naživu.
class HandoverPromptWatcher extends ConsumerStatefulWidget {
  const HandoverPromptWatcher({super.key});

  @override
  ConsumerState<HandoverPromptWatcher> createState() => _HandoverPromptWatcherState();
}

class _HandoverPromptWatcherState extends ConsumerState<HandoverPromptWatcher>
    with WidgetsBindingObserver {
  bool _opening = false; // protokol právě otevřený z výzvy → neotvírat podruhé

  static String _prefKey(String bookingId) => 'protocol_prompt_$bookingId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Výzva přišla, když byla appka na pozadí → otevřít hned po návratu.
    if (state == AppLifecycleState.resumed) {
      _check(ref.read(reservationsProvider).valueOrNull);
    }
  }

  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  /// Rezervace s NOVOU výzvou k protokolu (nepodepsáno, samoobsluha).
  static bool _needsPrompt(Reservation r) =>
      r.isSelfService &&
      (r.status == 'reserved' || r.status == 'active') &&
      r.handoverProtocolPromptedAt != null &&
      !r.protocolSigned;

  Future<void> _check(List<Reservation>? list) async {
    if (list == null || _opening || !_foreground) return;
    if (MotoGoSupabase.currentSession == null) return;
    final candidates = list.where(_needsPrompt).toList();
    if (candidates.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _opening) return;
    for (final r in candidates) {
      final stamp = r.handoverProtocolPromptedAt!.toUtc().toIso8601String();
      if (prefs.getString(_prefKey(r.id)) == stamp) continue;
      if (ProtocolScreen.openFor.contains(r.id)) {
        // Zákazník má protokol téže rezervace už otevřený (banner/tlačítko)
        // → výzva je splněná, druhou kopii obrazovky nad ni nevnucovat.
        await prefs.setString(_prefKey(r.id), stamp);
        continue;
      }
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      // Zapsat PŘED otevřením — i kdyby zákazník obrazovku hned zavřel,
      // tatáž výzva se znovu nevnucuje (další přijde s novým prompted_at).
      await prefs.setString(_prefKey(r.id), stamp);
      _opening = true;
      try {
        await ctx.push(Routes.protocol, extra: r);
      } finally {
        _opening = false;
      }
      return; // jedna výzva najednou; další případně po dalším tiku streamu
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(reservationsProvider, (prev, next) {
      if (!next.hasValue) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check(next.valueOrNull);
      });
    });
    return const SizedBox.shrink();
  }
}
