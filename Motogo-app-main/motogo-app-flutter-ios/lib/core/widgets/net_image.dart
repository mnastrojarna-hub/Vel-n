import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// URL server-side zmenšeného náhledu ze Supabase Storage (`render/image`
/// endpoint — vrací KB místo MB originálů z mobilů). Ne-Supabase URL (nebo už
/// transformovanou) vrací beze změny.
///
/// **`resize=contain` je POVINNÉ:** bez něj render/image aplikuje výchozí režim
/// `cover`, který obrázek ořízne (přiblíží) na cílový rámeček → fotky motorek se
/// zobrazovaly „zoomnuté", nebylo na nich nic vidět. `contain` zachová poměr
/// stran a nic neořízne — je to čistě zmenšenina originálu. Výřez si dál řeší
/// `BoxFit` ve widgetu, přesně jako u originálu (žádná změna vizuálu).
String mgThumbUrl(String url, {int width = 800, int quality = 75}) {
  const marker = '/storage/v1/object/public/';
  final i = url.indexOf(marker);
  if (i < 0) return url;
  final base = url.substring(0, i);
  var path = url.substring(i + marker.length);
  final q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  if (path.isEmpty) return url;
  return '$base/storage/v1/render/image/public/$path'
      '?width=$width&quality=$quality&resize=contain';
}

/// Rychlé síťové foto pro celou appku:
/// 1. zkusí malý server-side náhled (bleskové načtení i na mobilních datech),
/// 2. při chybě transformace (např. nepodporovaný formát) automaticky stáhne
///    originál — uživatel chybu nikdy nevidí,
/// 3. disk cache přes CachedNetworkImage, `memCacheWidth` omezuje dekódování
///    velkých originálů v paměti (žádné trhání při scrollu).
class MgImage extends StatelessWidget {
  final String url;

  /// Cílová šířka náhledu v px (zvol ~2× logickou šířku widgetu).
  final int thumbWidth;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? error;

  const MgImage(
    this.url, {
    super.key,
    this.thumbWidth = 800,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = mgThumbUrl(url, width: thumbWidth);
    final ph = placeholder ?? Container(color: MotoGoColors.g100);
    final err = error ?? Container(color: MotoGoColors.g200);
    // Strop dekódování v paměti — i fallback originál se dekóduje zmenšený.
    final memW = (thumbWidth * 1.5).round();

    Widget original() => CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: memW,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => ph,
          errorWidget: (_, __, ___) => err,
        );

    if (thumb == url) return original();
    return CachedNetworkImage(
      imageUrl: thumb,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memW,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => ph,
      // Transformace nedostupná/selhala → plynulý fallback na originál.
      errorWidget: (_, __, ___) => original(),
    );
  }
}
