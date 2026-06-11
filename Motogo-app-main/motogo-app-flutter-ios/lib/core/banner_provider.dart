import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
/// Uses explicit Supabase Realtime channel (matches router.js in original app)
/// plus a 30-second polling fallback for reliability.
final bannerProvider = StreamProvider<BannerData?>((ref) {
  final controller = StreamController<BannerData?>();

  // Emit the latest banner value.
  Future<void> refresh() async {
    final data = await _fetchBanner();
    if (!controller.isClosed) controller.add(data);
  }

  // Initial fetch.
  refresh();

  // Realtime channel — mirrors the JS channel in router.js:
  //   supabase.channel('header-banner-changes')
  //     .on('postgres_changes', { event: '*', table: 'app_settings',
  //          filter: 'key=eq.header_banner' }, ...)
  RealtimeChannel? channel;
  try {
    channel = MotoGoSupabase.client.channel('header-banner-changes');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'app_settings',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'key',
        value: 'header_banner',
      ),
      callback: (_) => refresh(),
    );
    channel.subscribe();
  } catch (_) {
    // Non-critical — polling below will still work.
  }

  // Polling fallback every 30s — guarantees update even if realtime
  // connection drops silently.
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    refresh();
  });

  ref.onDispose(() {
    timer.cancel();
    if (channel != null) {
      MotoGoSupabase.client.removeChannel(channel);
    }
    controller.close();
  });

  return controller.stream;
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
