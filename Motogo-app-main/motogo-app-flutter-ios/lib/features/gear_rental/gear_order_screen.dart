import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/router.dart' show Routes;
import '../../core/v2/flag/v2_scope.dart';
import '../auth/auth_provider.dart';
import 'gear_contract.dart';
import 'gear_offer_provider.dart';
import 'gear_order_state.dart';
import 'gear_order_ui.dart';
import 'v2/gear_order_view_v2.dart';
import 'widgets/gear_order_view.dart';

/// Načtení podkladů objednávky (nastavení, ceník, pobočky, zavření).
final gearOrderDataProvider = FutureProvider.autoDispose<GearOrderData>((ref) async {
  final cfg = await ref.watch(gearRentalSettingsProvider.future);
  final prices = await ref.watch(gearPricesProvider.future);
  final branches = await ref.watch(gearBranchesProvider.future);
  final closures = await ref.watch(gearClosuresProvider.future);
  return GearOrderData(cfg: cfg, prices: prices, branches: branches, closures: closures, today: gearPragueToday());
});

/// `/gear-rental` — půjčení samotné výbavy 1:1 jako web /pujceni-obleceni
/// (pobočka → termín → výbava a velikosti → kontakt, poukaz, souhlasy →
/// souhrn → platba). Starý i nový vzhled sdílí stav [gearOrderProvider].
class GearOrderScreen extends ConsumerStatefulWidget {
  const GearOrderScreen({super.key});

  @override
  ConsumerState<GearOrderScreen> createState() => _GearOrderScreenState();
}

class _GearOrderScreenState extends ConsumerState<GearOrderScreen> {
  final fields = GearOrderFields();
  bool _prefilled = false;

  @override
  void dispose() {
    fields.dispose();
    super.dispose();
  }

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  void _prefill(GearOrderController c) {
    if (_prefilled) return;
    final p = ref.read(profileProvider).valueOrNull;
    if (p == null) return;
    _prefilled = true;
    c.prefill(p);
    fields.fillFrom(ref.read(gearOrderProvider).contact);
  }

  /// Uložená velikost z profilu (`gear_sizes.rider`), když kus nemá velikost.
  String? _savedSize(String key) {
    final gs = ref.read(profileProvider).valueOrNull?['gear_sizes'];
    final rider = gs is Map ? gs['rider'] : null;
    final v = rider is Map ? rider[key] : null;
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  void _toggleItem(GearOrderController c, String key, bool on) {
    c.toggleItem(key, on);
    if (on) c.preselectSize(key, _savedSize(key));
  }

  /// Komplet (web) + bez velikosti předvyplnit uložené velikosti z profilu.
  void _toggleSet(GearOrderController c, String key) {
    c.toggleSet(key);
    for (final k in ref.read(gearOrderProvider).keys) {
      c.preselectSize(k, _savedSize(k));
    }
  }

  Future<void> _submit(GearOrderController c) async {
    FocusScope.of(context).unfocus();
    final lang = Localizations.localeOf(context).languageCode;
    final created = await c.submit(lang);
    if (created == null || !mounted) return;
    payGearBooking(context, ref, bookingId: created.bookingId, amount: created.amount, createdAt: DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dataAsync = ref.watch(gearOrderDataProvider);
    final c = ref.read(gearOrderProvider.notifier);
    final s = ref.watch(gearOrderProvider);
    ref.listen(profileProvider, (_, __) => _prefill(c));
    final data = dataAsync.valueOrNull;
    if (data != null && s.data == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        c.configure(data);
        _prefill(c);
      });
    }
    final v2 = MgV2.on(context);
    final loading = dataAsync.isLoading && data == null;
    final failed = dataAsync.hasError && data == null;
    final unavailable = data != null && !data.available;
    String? message;
    if (failed) message = tr.tr('groLoadFail');
    if (unavailable) message = tr.tr(data.cfg.enabled ? 'groUnavailable' : 'groErrDisabled');
    final actions = GearOrderActions(
      back: _back,
      retry: () => ref.invalidate(gearOrderDataProvider),
      toggleItem: (k, on) => _toggleItem(c, k, on),
      toggleSet: (k) => _toggleSet(c, k),
      submit: () => _submit(c),
    );
    if (v2) {
      return GearOrderViewV2(
          state: s, ctrl: c, fields: fields, actions: actions, loading: loading || (data != null && s.data == null && message == null), message: message);
    }
    return GearOrderView(
        state: s, ctrl: c, fields: fields, actions: actions, loading: loading || (data != null && s.data == null && message == null), message: message);
  }
}
