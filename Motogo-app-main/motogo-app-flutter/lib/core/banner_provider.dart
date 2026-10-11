import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'i18n/i18n_provider.dart';
import 'supabase_client.dart';

/// Banner data from app_settings.header_banner.
///
/// `text` je český originál; `translations` drží JEN čerstvé překlady z Velínu
/// (Dashboard → Banner): `translations_src` == SHA-1 (hex) českého `text`
/// přesně tak, jak je uložen. Stejné pravidlo používá web (layout-banner.php)
/// — po změně CZ textu, než Velín dopřeloží, se ukáže čeština.
class BannerData {
  final bool enabled;
  final String text;
  final Color bg;
  final Color color;
  final Map<String, String> translations;

  const BannerData({
    required this.enabled,
    required this.text,
    required this.bg,
    required this.color,
    this.translations = const {},
  });

  /// Banner s textem v jazyce [lang] (čerstvý překlad), jinak česky.
  BannerData forLang(String lang) {
    final t = translations[lang]?.trim() ?? '';
    if (lang == 'cs' || t.isEmpty) return this;
    return BannerData(
      enabled: enabled,
      text: t,
      bg: bg,
      color: color,
      translations: translations,
    );
  }
}

/// SHA-1 (hex, malá písmena) nad UTF-8 bajty — otisk CZ textu banneru.
String bannerFingerprint(String input) {
  final bytes = <int>[...utf8.encode(input), 0x80];
  final bitLen = (bytes.length - 1) * 8;
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    bytes.add((bitLen >> (8 * i)) & 0xff);
  }
  int rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xffffffff;
  final h = <int>[0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0];
  final w = List<int>.filled(80, 0);
  for (var off = 0; off < bytes.length; off += 64) {
    for (var i = 0; i < 16; i++) {
      final j = off + i * 4;
      w[i] = (bytes[j] << 24) | (bytes[j + 1] << 16) | (bytes[j + 2] << 8) | bytes[j + 3];
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (var i = 0; i < 80; i++) {
      final int f;
      final int k;
      if (i < 20) {
        f = (b & c) | (~b & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final tmp = (rotl(a, 5) + (f & 0xffffffff) + e + k + w[i]) & 0xffffffff;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = tmp;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}

/// Čerstvé překlady z hodnoty banneru (jinak prázdná mapa).
Map<String, String> _freshTranslations(Map<String, dynamic> v, String text) {
  final tr = v['translations'];
  final src = v['translations_src'];
  if (tr is! Map || src is! String) return const {};
  if (src.toLowerCase() != bannerFingerprint(text)) return const {};
  final out = <String, String>{};
  tr.forEach((k, val) {
    if (k is String && val is String && val.trim().isNotEmpty) out[k] = val;
  });
  return out;
}

Color _parseHex(String hex) {
  hex = hex.replaceAll('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  return Color(int.parse(hex, radix: 16));
}

/// Banner v jazyce appky (localeProvider): čerstvý překlad, jinak česky.
final bannerProvider = Provider<AsyncValue<BannerData?>>((ref) {
  final lang = ref.watch(localeProvider).languageCode;
  return ref.watch(_rawBannerProvider).whenData((b) => b?.forLang(lang));
});

/// Fetches header_banner from app_settings and subscribes to realtime changes.
/// Uses explicit Supabase Realtime channel (matches router.js in original app)
/// plus a 30-second polling fallback for reliability.
final _rawBannerProvider = StreamProvider<BannerData?>((ref) {
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
    final text = v['text'] as String? ?? '';
    return BannerData(
      enabled: v['enabled'] == true,
      text: text,
      bg: _parseHex(v['bg'] as String? ?? '#1a2e22'),
      color: _parseHex(v['color'] as String? ?? '#74FB71'),
      translations: _freshTranslations(v, text),
    );
  } catch (_) {
    return null;
  }
}
