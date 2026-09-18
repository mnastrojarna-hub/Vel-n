import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_image.dart';
import 'poi_categories.dart';
import 'poi_rating.dart';
import 'poi_reviews.dart';
import '../../core/i18n/i18n_provider.dart';

/// Nadpis sekce v detailu bodu zájmu — výrazný, prominentní.
Widget _poiSectionTitle(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        s,
        style: const TextStyle(
          fontSize: MotoGoTypo.sizeH3,
          fontWeight: MotoGoTypo.w900,
          color: MotoGoColors.black,
          decoration: TextDecoration.none,
        ),
      ),
    );

/// Velký, obsáhlý detail bodu zájmu — otevírá se jako vysoký, scrollovatelný
/// panel (rozbalitelný na skoro celou výšku). Pořadí sekcí: titulní fotka +
/// galerie → název + kategorie → popis → Okolí → hvězdy → recenze/komentáře.
/// Fotky lze zvětšit přes celou obrazovku s přibližováním.
/// [siblings] = místa, mezi kterými jde v detailu listovat swipem do stran
/// (u trasy její body v pořadí, jinak právě vyfiltrovaný seznam). Když je
/// prázdné nebo jednoprvkové, detail se chová jako dřív.
/// [isSelected]/[onToggleSelect] zapnou v detailu spodní tlačítko „Přidat do
/// mé cesty" (resp. „Odebrat"). Volající je předá tam, kde se z míst skládá
/// vyjížďka (seznam Míst, mapa míst) — jinde se tlačítko nevykreslí.
void showRoutePoiSheet(
  BuildContext context,
  RoutePoi poi,
  String lang, {
  int? index,
  List<RoutePoi> siblings = const [],
  void Function(int index)? onIndexChanged,
  bool Function(RoutePoi poi)? isSelected,
  void Function(RoutePoi poi)? onToggleSelect,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (c, scrollController) => _PoiPager(
        poi: poi,
        lang: lang,
        index: index,
        siblings: siblings,
        onIndexChanged: onIndexChanged,
        controller: scrollController,
        isSelected: isSelected,
        onToggleSelect: onToggleSelect,
      ),
    ),
  );
}

/// Listování mezi detaily míst swipem do stran.
///
/// Záměrně NEpoužívá PageView: `DraggableScrollableSheet` potřebuje svůj
/// scroll controller připojený k právě zobrazenému obsahu, a s několika
/// stránkami najednou by se rozbilo tažení panelu za obsah. Místo toho se
/// překresluje jeden detail a přechod obstará posuvná animace.
class _PoiPager extends StatefulWidget {
  final RoutePoi poi;
  final String lang;
  final int? index;
  final List<RoutePoi> siblings;
  final void Function(int index)? onIndexChanged;
  final ScrollController controller;
  final bool Function(RoutePoi poi)? isSelected;
  final void Function(RoutePoi poi)? onToggleSelect;
  const _PoiPager({
    required this.poi,
    required this.lang,
    required this.index,
    required this.siblings,
    required this.onIndexChanged,
    required this.controller,
    this.isSelected,
    this.onToggleSelect,
  });

  @override
  State<_PoiPager> createState() => _PoiPagerState();
}

class _PoiPagerState extends State<_PoiPager> {
  late List<RoutePoi> _items = widget.siblings.length > 1
      ? widget.siblings
      : <RoutePoi>[widget.poi];
  late int _at = () {
    final i = _items.indexWhere((e) => e.id == widget.poi.id);
    return i < 0 ? 0 : i;
  }();
  int _dir = 1; // směr poslední změny — kvůli animaci
  double _dx = 0; // ušlá vzdálenost tažení

  void _go(int delta) {
    final next = _at + delta;
    if (next < 0 || next >= _items.length) return;
    setState(() {
      _dir = delta;
      _at = next;
    });
    // Skok na začátek až po překreslení — v okamžiku setState je na
    // controlleru panelu připojený ještě starý seznam a ten by uskočil.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.hasClients) {
        widget.controller.jumpTo(0);
      }
    });
    widget.onIndexChanged?.call(_at);
  }

  @override
  Widget build(BuildContext context) {
    final poi = _items[_at];
    final many = _items.length > 1;
    return GestureDetector(
      // Swipe doleva = další, doprava = předchozí. Vodorovný PageView
      // galerie uvnitř si gesto vezme dřív, takže listování fotek zůstává.
      onHorizontalDragStart: !many ? null : (_) => _dx = 0,
      onHorizontalDragUpdate: !many ? null : (d) => _dx += d.delta.dx,
      onHorizontalDragEnd: !many
          ? null
          : (d) {
              // Projde švihnutí i pomalé přetažení přes třetinu obrazovky —
              // jen na rychlost reagovat nestačí, pomalý tah nic neudělal.
              final v = d.primaryVelocity ?? 0;
              final far = _dx.abs() > 60;
              if (v.abs() < 120 && !far) return;
              _go((v.abs() >= 120 ? v < 0 : _dx < 0) ? 1 : -1);
            },
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween<Offset>(
                begin: Offset(_dir > 0 ? 0.25 : -0.25, 0),
                end: Offset.zero,
              ).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _PoiSheetContent(
              key: ValueKey(poi.id),
              poi: poi,
              lang: widget.lang,
              bottomInset: widget.onToggleSelect == null ? 0 : 72,
              // Číslo zastávky patří jen bodům NA TRASE — volající ho
              // pošle jen odtud. V katalogu míst by z pozice v seznamu
              // vzniklo nesmyslné pořadí („4238").
              index: widget.index == null ? null : (many ? _at : widget.index),
              controller: widget.controller,
            ),
          ),
          // Přidat do vyjížďky přímo z detailu — hledaná akce, kvůli které
          // se detail nejčastěji otevírá.
          if (widget.onToggleSelect != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: _AddToTripButton(
                selected: widget.isSelected?.call(poi) ?? false,
                onTap: () {
                  widget.onToggleSelect!(poi);
                  setState(() {});
                },
              ),
            ),
          if (many)
            Positioned(
              // Mimo osu — uprostřed nahoře sedí táhlo panelu.
              top: 8,
              left: 12,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius:
                          BorderRadius.circular(MotoGoRadius.pill),
                    ),
                    child: Text(
                      '${_at + 1} / ${_items.length}',
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeSm,
                        fontWeight: MotoGoTypo.w800,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Obsah detailu bodu. Katalogové body se do seznamu načítají odlehčené (bez
/// popisu / okolí / galerie / překladů popisů kvůli velikosti payloadu) — tady
/// se jejich plný detail dotáhne per-bod přes `get_poi_detail`. Trasové a
/// komunitní body už mají vše načtené, takže se nedotahují a vykreslí se hned.
class _PoiSheetContent extends StatefulWidget {
  final RoutePoi poi;
  final String lang;
  final int? index;
  final ScrollController controller;
  /// Rezerva dole na plovoucí tlačítko „Přidat do mé cesty".
  final double bottomInset;
  const _PoiSheetContent({
    super.key,
    required this.poi,
    required this.lang,
    required this.index,
    required this.controller,
    this.bottomInset = 0,
  });

  @override
  State<_PoiSheetContent> createState() => _PoiSheetContentState();
}

class _PoiSheetContentState extends State<_PoiSheetContent> {
  late RoutePoi _poi = widget.poi;
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    final p = widget.poi;
    // Odlehčený bod (katalogový i trasový) = bez popisu/okolí/galerie →
    // dotáhni plný detail příslušnou RPC.
    if (p.description == null && p.surroundings == null && p.images.isEmpty) {
      Future<RoutePoi?>? load;
      if (p.isCatalogPoi) {
        load = fetchCatalogPoiDetail(p.id);
      } else if (!p.isUserPoi) {
        load = fetchRoutePoiDetail(p.id);
      }
      if (load != null) {
        _loadingDetail = true;
        load.then((full) {
          if (!mounted) return;
          setState(() {
            if (full != null) _poi = full;
            _loadingDetail = false;
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final poi = _poi;
    final lang = widget.lang;
    final index = widget.index;
    final scrollController = widget.controller;
    final desc = poi.descFor(lang);
    final surr = poi.surroundingsFor(lang);
    // Všechny fotky bodu (titulní + galerie), bez duplicit, v pořadí.
    final imgs = <String>{
      if (poi.imageUrl != null && poi.imageUrl!.isNotEmpty) poi.imageUrl!,
      ...poi.images.where((e) => e.isNotEmpty),
    }.toList();
    // Kategorie bodu (emoji + lokalizovaný popisek) do štítku pod názvem.
    final catKey = poiCategoryOf(poi);
    final cat = kPoiCats.firstWhere((c) => c.key == catKey, orElse: () => kPoiCats.last);

    return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: [
            // ── Velká titulní fotka (klik = fullscreen) ──
            if (imgs.isNotEmpty)
              GestureDetector(
                onTap: () => openPoiImageViewer(context, imgs, 0, lang),
                child: Stack(
                  children: [
                    RouteImage(
                      url: imgs.first,
                      height: 250,
                      width: double.infinity,
                      targetWidth: 1200,
                      placeholder: (_) => Container(height: 250, color: MotoGoColors.greenPale),
                      error: (_) => Container(
                        height: 250,
                        color: MotoGoColors.greenPale,
                        child: Center(child: Text(poiCatEmoji(poi), style: const TextStyle(fontSize: 48))),
                      ),
                    ),
                    // Táhlo panelu (přes fotku)
                    Positioned(
                      top: 10, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    // Náznak „klikni pro zvětšení"
                    Positioned(
                      right: 12, top: 12,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.zoom_out_map, size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),

            // ── Galerie miniatur (od druhé fotky) ──
            if (imgs.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: imgs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => openPoiImageViewer(context, imgs, i, lang),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: RouteImage(
                          url: imgs[i],
                          width: 96, height: 66,
                          targetWidth: 300,
                          placeholder: (_) => Container(width: 96, color: MotoGoColors.greenPale),
                          error: (_) => Container(
                            width: 96, color: MotoGoColors.greenPale,
                            child: const Center(child: Text('📍')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20,
                  MediaQuery.of(context).padding.bottom + 28 + widget.bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Název + pořadové číslo ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (index != null) ...[
                        Container(
                          width: 30, height: 30,
                          decoration: const BoxDecoration(color: MotoGoColors.greenDarker, shape: BoxShape.circle),
                          child: Center(
                            child: Text('${index + 1}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          poi.nameFor(lang),
                          style: const TextStyle(
                            fontSize: MotoGoTypo.sizeH1,
                            fontWeight: MotoGoTypo.w900,
                            color: MotoGoColors.black,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Štítek kategorie ──
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: MotoGoColors.greenPale,
                      borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          t(context).tr(cat.i18nKey),
                          style: const TextStyle(
                            fontSize: MotoGoTypo.sizeMd,
                            fontWeight: MotoGoTypo.w800,
                            color: MotoGoColors.greenDarker,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Donačítání plného detailu katalogového bodu (popis/okolí/
                  // galerie) — jemný indikátor, ať karta nepůsobí prázdně.
                  if (_loadingDetail) ...[
                    const SizedBox(height: 20),
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: MotoGoColors.greenDark),
                        ),
                      ),
                    ),
                  ],

                  // ── Popis (celý text, čitelný) ──
                  if (desc != null && desc.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        height: 1.6,
                        color: MotoGoColors.g600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],

                  // ── Okolí ──
                  if (surr != null && surr.trim().isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _poiSectionTitle(t(context).tr('poiSurroundings')),
                    Text(
                      surr,
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        height: 1.6,
                        color: MotoGoColors.g600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],

                  // ── Hvězdy (rychlé hodnocení) ──
                  const SizedBox(height: 22),
                  const Divider(height: 1, color: MotoGoColors.g200),
                  const SizedBox(height: 16),
                  PoiRatingBar(poi: poi),

                  // ── Recenze / komentáře bodu ──
                  const SizedBox(height: 22),
                  PoiReviewsSection(target: poiReviewTarget(poi)),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

/// Spodní tlačítko detailu: přidat místo do skládané vyjížďky / odebrat ho.
class _AddToTripButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _AddToTripButton({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: selected ? Colors.white : MotoGoColors.green,
          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
          border: Border.all(
              color: selected ? MotoGoColors.greenDark : MotoGoColors.green,
              width: 1.6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? Icons.check_circle : Icons.add_location_alt,
                  size: 19,
                  color: selected ? MotoGoColors.greenDark : MotoGoColors.black),
              const SizedBox(width: 8),
              Text(
                t(context).tr(selected ? 'poiRemoveFromTrip' : 'poiAddToTrip'),
                style: TextStyle(
                  fontSize: MotoGoTypo.sizeXl,
                  fontWeight: MotoGoTypo.w800,
                  color: selected ? MotoGoColors.greenDark : MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fullscreen prohlížeč fotek s kreditem — sdílený: POI sheet i galerie
/// v detailu trasy.
void openPoiImageViewer(BuildContext context, List<String> imgs, int start, String lang) {
  showDialog(
    context: context,
    barrierColor: Colors.black,
    builder: (dctx) {
      final controller = PageController(initialPage: start);
      var current = start; // aktuální fotka — kvůli odkazu na zdroj (kredit)
      return StatefulBuilder(
        builder: (dctx, setSt) => Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: imgs.length,
            onPageChanged: (i) => setSt(() => current = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: RouteImage(
                  url: imgs[i],
                  fit: BoxFit.contain,
                  targetWidth: 1600,
                  placeholder: (_) => const SizedBox.shrink(),
                  error: (_) =>
                      const Center(child: Text('📍', style: TextStyle(fontSize: 48))),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(dctx).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(dctx).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
          if (imgs.length > 1)
            Positioned(
              bottom: MediaQuery.of(dctx).padding.bottom + 16,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${imgs.length} ${AppTranslations.of(lang).tr('poiPhotoSuffix')}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          // Kredit fotky (licence Wikimedia Commons) — záměrně skoro neviditelná
          // mini ikonka v rohu; detail (autor/licence/zdroj) až po kliknutí.
          Positioned(
            left: 10,
            bottom: MediaQuery.of(dctx).padding.bottom + 14,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showPhotoCredit(dctx, imgs[current], lang),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.copyright, size: 14,
                    color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          ),
        ],
        ),
      );
    },
  );
}

/// Ze zdrojové URL fotky odvodí stránku souboru na Wikimedia Commons
/// (`Special:FilePath/<název>` → `File:<název>` s autorem a licencí).
/// Pro jiné zdroje (vlastní fotky, zrcadlo v bucketu) vrátí null.
String? _commonsFilePage(String url) {
  final m = RegExp(r'wik(?:imedia|ipedia)\.org/wiki/Special:FilePath/(.+)$')
      .firstMatch(url);
  if (m == null) return null;
  return 'https://commons.wikimedia.org/wiki/File:${m.group(1)}';
}

/// Malý panel s kreditem fotky: obecná věta (autoři a licence na zdrojové
/// stránce) + tlačítko na otevření zdroje, pokud je fotka z Commons.
void _showPhotoCredit(BuildContext context, String url, String lang) {
  final source = _commonsFilePage(url);
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (c) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.copyright, size: 18, color: MotoGoColors.g500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppTranslations.of(lang).tr('poiPhotoCredit'),
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeBase,
                      fontWeight: MotoGoTypo.w600,
                      color: MotoGoColors.g600,
                      height: 1.4,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
            if (source != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(source),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(AppTranslations.of(lang).tr('poiPhotoCreditOpen')),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
