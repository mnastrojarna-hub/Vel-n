import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../payment/payment_provider.dart';

/// Výpůjčka jen výbavy — sdílený kontrakt objednávky (vlastní ho objednávka,
/// zobrazení rezervací ho jen importuje). Web: /pujceni-obleceni.

/// Trasa objednávky výbavy (uvnitř shellu, vyžaduje přihlášení).
const String kGearRentalRoute = '/gear-rental';

/// `app_settings.gear_rental` (veřejné čtení).
class GearRentalSettings {
  final bool enabled;
  final bool appVisible;
  final bool selfServiceEnabled;
  final int maxDays;
  final int maxAheadDays;

  const GearRentalSettings({
    this.enabled = true,
    this.appVisible = false,
    this.selfServiceEnabled = false,
    this.maxDays = 30,
    this.maxAheadDays = 400,
  });

  /// Jako web (pujceni-obleceni.php): max_days 1..366, max_ahead 1..800.
  factory GearRentalSettings.fromJson(Map<String, dynamic> j) {
    int clampInt(Object? v, int def, int max) {
      final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? def;
      return n < 1 ? 1 : (n > max ? max : n);
    }

    return GearRentalSettings(
      enabled: j['enabled'] != false,
      appVisible: j['app_visible'] == true,
      selfServiceEnabled: j['self_service_enabled'] == true,
      maxDays: clampInt(j['max_days'], 30, 366),
      maxAheadDays: clampInt(j['max_ahead_days'], 400, 800),
    );
  }
}

final gearRentalSettingsProvider =
    FutureProvider<GearRentalSettings>((ref) async {
  // Velín přepne „Zobrazit v aplikaci“ → po návratu do appky platí i bez
  // obnovení Domů / restartu (vstup výbavy na Domů hlídá tento stav).
  try {
    final l = AppLifecycleListener(onResume: ref.invalidateSelf);
    ref.onDispose(l.dispose);
  } catch (_) {}
  try {
    final row = await MotoGoSupabase.client
        .from('app_settings')
        .select('value')
        .eq('key', 'gear_rental')
        .maybeSingle();
    final v = row?['value'];
    if (v is Map) return GearRentalSettings.fromJson(Map<String, dynamic>.from(v));
  } catch (_) {}
  return const GearRentalSettings();
});

/// Řádek ceníku `gear_rental_prices` (kind `set` = komplet, `item` = kus).
class GearPrice {
  final String key;
  final String kind;
  final String label;
  final String desc;
  final List<String> includes;
  final List<String> sizes;
  final double perDay;

  const GearPrice({
    required this.key,
    required this.kind,
    required this.label,
    this.desc = '',
    this.includes = const [],
    this.sizes = const [],
    required this.perDay,
  });

  bool get isSet => kind == 'set';

  /// label/desc z `translations[lang]`, jinak základní hodnota (jako web).
  factory GearPrice.fromJson(Map<String, dynamic> r, String lang) {
    Map<String, dynamic> tr = const {};
    final t = r['translations'];
    if (t is Map && t[lang] is Map) tr = Map<String, dynamic>.from(t[lang] as Map);
    String pick(Object? a, Object? b) {
      final s = (a ?? '').toString().trim();
      return s.isNotEmpty ? s : (b ?? '').toString().trim();
    }

    List<String> list(Object? v) =>
        v is List ? v.map((e) => '$e').toList() : const <String>[];
    final p = r['price_per_day'];
    return GearPrice(
      key: '${r['key']}',
      kind: r['kind'] == 'set' ? 'set' : 'item',
      label: pick(tr['label'], r['label']),
      desc: pick(tr['description'], r['description']),
      includes: list(r['includes']),
      sizes: list(r['sizes']),
      perDay: p is num ? p.toDouble() : double.tryParse('${p ?? ''}') ?? 0,
    );
  }
}

final gearPricesProvider = FutureProvider<List<GearPrice>>((ref) async {
  final lang = ref.watch(localeProvider).languageCode;
  try {
    final rows = await MotoGoSupabase.client
        .from('gear_rental_prices')
        .select(
            'key,kind,label,description,includes,sizes,price_per_day,sort_order,translations')
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    return [
      for (final r in rows)
        if ((r['key'] ?? '').toString().isNotEmpty) GearPrice.fromJson(r, lang),
    ];
  } catch (_) {
    return const [];
  }
});

/// Id rezervací výbavy, které se právě platí — děkovací stránka (/success)
/// podle nich vykreslí potvrzení výbavy místo motorky.
final gearPaymentIdsProvider = StateProvider<Set<String>>((ref) => const {});

/// Zaplatit výpůjčku výbavy stávající platební obrazovkou (PaymentContext).
void payGearBooking(
  BuildContext context,
  WidgetRef ref, {
  required String bookingId,
  required double amount,
  DateTime? createdAt,
}) {
  ref.read(paymentContextProvider.notifier).state = PaymentContext(
    flowType: PaymentFlowType.booking,
    bookingId: bookingId,
    amount: amount,
    label: t(context).tr('groPayLabel'),
    bookingCreatedAt: createdAt,
    gear: true,
  );
  final ids = ref.read(gearPaymentIdsProvider);
  ref.read(gearPaymentIdsProvider.notifier).state = {...ids, bookingId};
  context.push('/payment'); // Routes.payment (bez importu routeru — lehký kontrakt)
}
