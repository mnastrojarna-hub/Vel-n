import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'supabase_client.dart';

/// Banner data from app_settings.header_banner.
class BannerData {
  final bool enabled;
  final String text;
  final Color bg;
  final Color color;

  const BannerData({
    required this.enabled,
    required this.text,
    required this.bg,
    required this.color,
  });
}

Color _parseHex(String hex) {
  hex = hex.replaceAll('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  return Color(int.parse(hex, radix: 16));
}

/// Fetches header_banner from app_settings and subscribes to realtime changes.
final bannerProvider = StreamProvider<BannerData?>((ref) async* {
  // Initial fetch
  yield await _fetchBanner();

  // Realtime subscription — mirrors the supabase channel in router.js
  await for (final _ in MotoGoSupabase.client
      .from('app_settings')
      .stream(primaryKey: ['key'])
      .eq('key', 'header_banner')) {
    yield await _fetchBanner();
  }
});

Future<BannerData?> _fetchBanner() async {
  try {
    final res = await MotoGoSupabase.client
        .from('app_settings')
        .select('value')
        .eq('key', 'header_banner')
        .maybeSingle();

    if (res == null || res['value'] == null) return null;

    final v = res['value'] as Map<String, dynamic>;
    return BannerData(
      enabled: v['enabled'] == true,
      text: v['text'] as String? ?? '',
      bg: _parseHex(v['bg'] as String? ?? '#1a2e22'),
      color: _parseHex(v['color'] as String? ?? '#74FB71'),
    );
  } catch (_) {
    return null;
  }
}
