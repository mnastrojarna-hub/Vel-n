import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/net_image.dart' show mgThumbUrl;
import '../../core/v2/flag/v2_scope.dart';
import '../../core/v2/icons/mg_icon.dart';
import '../../core/v2/motion/mg_motion.dart';
import '../../core/v2/tokens/mg_colors.dart';

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
/// Supabase public storage URL (nahrané fotky z mobilů, běžně stovky KB až MB)
/// přepíše na server-side zmenšeninu přes `render/image` endpoint (mgThumbUrl);
/// při nedostupné transformaci RouteImage automaticky spadne na originál.
/// Ostatní URL vrací beze změny.
String mgImageUrl(String rawUrl, {int width = 800}) {
  if (rawUrl.isEmpty) return rawUrl;
  // Katalog míst má adresy fotek přímo z Wikidat, a ty jsou zapsané jako
  // `http://commons.wikimedia.org/…`. Přes http to jde na tři přesměrování
  // (http → https → upload → thumb), což u seznamu s desítkami náhledů znamená
  // desítky zbytečných spojení. Backend je přepisuje migrací
  // 20260920g_poi_photos_https_and_cron.sql, tohle je pojistka pro řádky,
  // které přijdou odjinud (Velín, komunitní body).
  final url = rawUrl.startsWith('http://')
      ? 'https://${rawUrl.substring(7)}'
      : rawUrl;
  final lower = url.toLowerCase();
  final isWiki = lower.contains('wikimedia.org') || lower.contains('wikipedia.org');
  if (isWiki && lower.contains('special:filepath')) {
    if (lower.contains('width=')) return url; // šířka už tam je
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}width=$width';
  }
  return mgThumbUrl(url, width: width);
}

/// Přednačte fotku do cache (disk + paměť) přes STEJNÝ klíč/URL, jaký použije
/// [RouteImage]. Díky tomu ji uživatel při zobrazení uvidí okamžitě a nevidí,
/// „jak se načítá". Best-effort — chyby (403/timeout) tiše ignoruje.
Future<void> precacheRouteImage(BuildContext context, String url,
    {int targetWidth = 500}) {
  if (url.isEmpty) return Future<void>.value();
  final optimized = mgImageUrl(url, width: targetWidth);
  return precacheImage(
    CachedNetworkImageProvider(optimized, headers: kRouteImageHeaders),
    context,
    onError: (_, __) {},
  );
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
    final memW = (targetWidth * dpr).round();
    final optimized = mgImageUrl(url, width: targetWidth);
    // v2 (F-35): fade 150 ms (0 under reduced motion), placeholder / error =
    // the v2 well + image glyph instead of the mint box and the 📍 emoji.
    final v2 = MgV2.on(context);
    final fade = v2 ? MgMotion.of(context, const Duration(milliseconds: 150)) : const Duration(milliseconds: 200);
    Widget v2Box() => ColoredBox(
          color: MgColors.well,
          child: Center(child: MgIcon(MgIcons.image, size: 24, color: MgColors.meta.withValues(alpha: 0.5))),
        );

    Widget errorFallback(BuildContext c) =>
        error?.call(c) ??
        (v2
            ? v2Box()
            : Container(
                color: MotoGoColors.greenPale,
                child: const Center(child: Text('📍', style: TextStyle(fontSize: 28))),
              ));

    // Originál — poslední záchrana, když zmenšenina selže (např. Supabase
    // transformace nedostupná). Uživatel chybu nevidí, jen o chlup delší load.
    Widget original(BuildContext c) => CachedNetworkImage(
          imageUrl: url,
          httpHeaders: kRouteImageHeaders,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: memW,
          fadeInDuration: fade,
          placeholder: (cc, _) =>
              placeholder?.call(cc) ?? (v2 ? v2Box() : Container(color: MotoGoColors.greenPale)),
          errorWidget: (cc, _, __) => errorFallback(cc),
        );

    if (optimized == url) return original(context);
    return CachedNetworkImage(
      imageUrl: optimized,
      httpHeaders: kRouteImageHeaders,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memW,
      fadeInDuration: fade,
      placeholder: (c, _) =>
          placeholder?.call(c) ?? (v2 ? v2Box() : Container(color: MotoGoColors.greenPale)),
      errorWidget: (c, _, __) => original(c),
    );
  }
}
