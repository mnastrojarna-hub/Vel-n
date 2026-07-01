import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// HTTP hlavičky pro načítání fotek tras / bodů zájmu.
///
/// Většina seedovaných fotek pochází z **Wikimedia Commons**, jejíž politika
/// vyžaduje popisný `User-Agent` — prázdný nebo generický UA vrací **HTTP 403**.
/// Prohlížeč (Velín) posílá vlastní UA a fotky zobrazí, mobilní klient ale bez
/// těchto hlaviček často dostane 403 → v appce se fotka nenačte. Ostatním
/// hostům (Supabase `media` bucket) hlavičky neuškodí.
const Map<String, String> kRouteImageHeaders = {
  'User-Agent': 'MotoGo24App/1.0 (+https://motogo24.cz; info@motogo24.cz)',
  'Referer': 'https://motogo24.cz/',
};

/// Vrátí URL fotky optimalizovanou na cílovou šířku [width] (v px).
///
/// Fotky bodů zájmu / tras jsou typicky z Wikimedia Commons ve tvaru
/// `.../Special:FilePath/<soubor>`. Bez parametru vrací tato URL **ORIGINÁL
/// v plném rozlišení** (běžně 5–15 MB) — na mobilu se pak načítá extrémně
/// pomalu nebo spadne na timeout, případně sežere tolik paměti, že se galerie
/// „zasekne". Přidáním `?width=` vrátí Wikimedia zmenšený thumbnail (řádově
/// menší) → rychlé a spolehlivé načtení.
///
/// Pro ostatní URL (Supabase apod.) vrací původní URL beze změny.
String mgImageUrl(String url, {int width = 800}) {
  if (url.isEmpty) return url;
  final lower = url.toLowerCase();
  final isWiki = lower.contains('wikimedia.org') || lower.contains('wikipedia.org');
  if (isWiki && lower.contains('special:filepath')) {
    if (lower.contains('width=')) return url; // šířka už tam je
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}width=$width';
  }
  return url;
}

/// Síťová fotka trasy / bodu zájmu s optimalizací velikosti a Wikimedia
/// hlavičkami. Sjednocuje `CachedNetworkImage` napříč obrazovkami tras:
/// - přepíše Wikimedia URL na thumbnail dané šířky ([targetWidth]),
/// - pošle povinné hlavičky ([kRouteImageHeaders]),
/// - dekóduje do paměti jen v potřebném rozlišení ([memCacheWidth]), takže
///   se galerie nenačítá „celá naráz" ve full-res.
class RouteImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Cílová šířka pro thumbnail i dekódování (px). Volí se dle velikosti místa,
  /// kde se fotka zobrazuje (náhled 300, karta 500, hero 1000, fullscreen 1600).
  final int targetWidth;
  final Widget Function(BuildContext context)? placeholder;
  final Widget Function(BuildContext context)? error;

  const RouteImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.targetWidth = 800,
    this.placeholder,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return CachedNetworkImage(
      imageUrl: mgImageUrl(url, width: targetWidth),
      httpHeaders: kRouteImageHeaders,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: (targetWidth * dpr).round(),
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (c, _) =>
          placeholder?.call(c) ?? Container(color: MotoGoColors.greenPale),
      errorWidget: (c, _, __) =>
          error?.call(c) ??
          Container(
            color: MotoGoColors.greenPale,
            child: const Center(child: Text('📍', style: TextStyle(fontSize: 28))),
          ),
    );
  }
}
