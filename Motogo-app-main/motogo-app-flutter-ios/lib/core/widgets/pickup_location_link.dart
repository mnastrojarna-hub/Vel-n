import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../booking_rules.dart';
import '../i18n/i18n_provider.dart';
import '../supabase_client.dart';
import '../theme.dart';

/// „K vyzvednutí“ (zadání 2026-09-23): pobočka, kde motorka stojí — název,
/// adresa a odkaz na mapu podle GPS. Ukazuje se po zaplacení rezervace i po
/// úpravě / výměně motorky (appka i web mají stejné pravidlo).
class PickupInfo {
  final String? branchId;
  final String? name;
  final String? address;
  final double? lat;
  final double? lng;
  const PickupInfo({this.branchId, this.name, this.address, this.lat, this.lng});

  bool get isEmpty => (name ?? '').isEmpty && (address ?? '').isEmpty;

  /// Z řádku `branches` (id, name, address, zip, city, gps_lat, gps_lng).
  factory PickupInfo.fromBranch(Map<String, dynamic>? br) {
    String? s(Object? v) {
      final t = (v is String) ? v.trim() : null;
      return (t == null || t.isEmpty) ? null : t;
    }

    final zipCity = [s(br?['zip']), s(br?['city'])].whereType<String>().join(' ');
    final addr = [s(br?['address']), zipCity.isEmpty ? null : zipCity]
        .whereType<String>()
        .join(', ');
    return PickupInfo(
      branchId: s(br?['id']),
      name: s(br?['name']),
      address: addr.isEmpty ? null : addr,
      lat: (br?['gps_lat'] as num?)?.toDouble(),
      lng: (br?['gps_lng'] as num?)?.toDouble(),
    );
  }
}

const _branchCols = 'id, name, address, zip, city, gps_lat, gps_lng';

/// Má pobočka bránu se schránkou na klíč? (RPC `branch_has_gate` — jen
/// příznak, nikdy kód; Velké Němčice 2026-10-04.) Chyba / starý backend → ne.
final branchHasGateProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, branchId) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('branch_has_gate', params: {'p_branch_id': branchId});
    return res == true;
  } catch (_) {
    return false;
  }
});

/// Pobočka motorky rezervace po uložení (čte se znovu — po změně motorky je
/// jiná). Null u převzaté / ukončené / zrušené rezervace a u přistavení.
Future<PickupInfo?> loadBookingPickupInfo(String? bookingId) async {
  if (bookingId == null) return null;
  try {
    final r = await MotoGoSupabase.client
        .from('bookings')
        .select('status, pickup_method, pickup_address, '
            'motorcycles!moto_id(branches($_branchCols))')
        .eq('id', bookingId)
        .maybeSingle();
    if (r == null) return null;
    final st = r['status'] as String?;
    if (st == 'active' || st == 'completed' || st == 'cancelled') return null;
    if (bookingMethodWithAddress(r['pickup_method'] as String?,
            r['pickup_address'] as String?) ==
        'delivery') {
      return null;
    }
    final info = PickupInfo.fromBranch((r['motorcycles']
        as Map<String, dynamic>?)?['branches'] as Map<String, dynamic>?);
    return info.isEmpty ? null : info;
  } catch (e) {
    debugPrint('[pickup] booking load err: $e');
    return null;
  }
}

/// Pobočka konkrétní motorky (výměna motorky — nová motorka může stát jinde).
Future<PickupInfo?> loadMotoPickupInfo(String? motoId) async {
  if (motoId == null || motoId.isEmpty) return null;
  try {
    final r = await MotoGoSupabase.client
        .from('motorcycles')
        .select('branches($_branchCols)')
        .eq('id', motoId)
        .maybeSingle();
    final info =
        PickupInfo.fromBranch(r?['branches'] as Map<String, dynamic>?);
    return info.isEmpty ? null : info;
  } catch (e) {
    debugPrint('[pickup] moto load err: $e');
    return null;
  }
}

/// Otevře mapu: geo: (Android nabídne mapovou appku), jinak Google Maps podle
/// GPS; bez GPS hledá podle názvu a adresy.
Future<void> openPickupMap(PickupInfo p) async {
  final lat = p.lat, lng = p.lng;
  if (lat != null && lng != null) {
    try {
      if (await launchUrl(Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
  }
  final q = (lat != null && lng != null)
      ? '$lat,$lng'
      : [p.name, p.address].whereType<String>().join(', ');
  if (q.isEmpty) return;
  try {
    await launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query='
            '${Uri.encodeComponent(q)}'),
        mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Blok „📍 K vyzvednutí: název / adresa“ + „🗺️ Otevřít v mapě“; pobočka
/// s bránou navíc upozornění na schránku s klíčem (brána → šatna → motorka).
/// [dark] = bílý text na tmavém pozadí (děkovací obrazovky).
class PickupLocationLink extends ConsumerWidget {
  const PickupLocationLink({
    super.key,
    required this.info,
    this.dark = true,
    this.center = false,
  });

  final PickupInfo info;
  final bool dark;
  final bool center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final branchId = info.branchId;
    final hasGate = branchId != null &&
        (ref.watch(branchHasGateProvider(branchId)).valueOrNull ?? false);
    final lines = [info.name, info.address]
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join('\n');
    final textColor =
        dark ? Colors.white.withValues(alpha: 0.85) : MotoGoColors.g600;
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          '📍 ${tr.tr('confirmPickupTitle')}:\n$lines',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => openPickupMap(info),
          child: Text(
            '🗺️ ${tr.tr('openInMap')}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: dark ? MotoGoColors.green : MotoGoColors.greenDarker,
              decoration: TextDecoration.underline,
              decorationColor:
                  dark ? MotoGoColors.green : MotoGoColors.greenDarker,
            ),
          ),
        ),
        if (hasGate) ...[
          const SizedBox(height: 10),
          _GateNotice(dark: dark, center: center),
        ],
      ],
    );
  }
}

/// „Příjezd na pobočku …“ — brána zavřená → klíč v horní schránce, parkování,
/// po odjezdu bránu zamknout a klíč vrátit (texty shodné s e-mailem/webem).
class _GateNotice extends StatelessWidget {
  const _GateNotice({required this.dark, required this.center});
  final bool dark;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final fg = dark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF92400E);
    final align = center ? TextAlign.center : TextAlign.start;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.08) : MotoGoColors.amberBg,
        border: Border.all(color: dark ? MotoGoColors.green.withValues(alpha: 0.4) : MotoGoColors.amberBorder),
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text('🔐 ${tr.tr('gateNoticeTitle')}',
              textAlign: align,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: dark ? Colors.white : fg)),
          const SizedBox(height: 4),
          Text(tr.tr('gateNotice'),
              textAlign: align,
              style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w500, color: fg)),
        ],
      ),
    );
  }
}
