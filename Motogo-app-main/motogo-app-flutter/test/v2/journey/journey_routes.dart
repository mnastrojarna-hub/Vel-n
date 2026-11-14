// Journey rig — 20 routes with photos for the 5.0.1 Trasy states (README
// "Routes"). Names, lengths, times, difficulty, type, countries and stops
// are the live `routes` rows (REST GET, 2026-11-14); the stops become the
// route's places (category from the stop name). Photos are
// `shotUrl('route', n)` (real route / place photos with MG_SHOT_IMG_DIR).
// Route 1: cover = its first place's photo, 5 places with photos;
// every 7th route: no photos at all; the rest: own cover + up to 4 place
// photos.
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:motogo_app/features/routes/routes_model.dart';

import '../support/shot_images.dart' show shotUrl;

String _cat(String label) {
  final l = label.toLowerCase();
  if (RegExp('zámek|zámk|hrad|castle|burg').hasMatch(l)) return 'castle';
  if (RegExp('rozhledn|vyhlídk|hora|vrch|sedlo|průsmyk|pass|fóia|pustevny').hasMatch(l)) return 'lookout';
  if (RegExp('restaura|sklep|hospůd|hospod|kavárn|pivovar').hasMatch(l)) return 'food';
  if (RegExp('přehrad|nádrž|soutok|rybník|jezer|lago|vodopád').hasMatch(l)) return 'water';
  return 'sights';
}

int _photo(int k, int j) => ((k * 3 + j) % 14) + 1;

RouteItem _r(int k, String name, double km, int min, String diff, String type, List<String> countries,
    List<(double, double, String)> stops) {
  final none = k % 7 == 0;
  final places = <RoutePoi>[];
  final seen = <String>{};
  for (final s in stops) {
    if (!seen.add(s.$3)) continue;
    final j = places.length;
    final photo = !none && j < (k == 1 ? 5 : 4) ? shotUrl('route', _photo(k, j + 1)) : null;
    places.add(RoutePoi(id: 'jr$k-p$j', name: s.$3, lat: s.$1, lng: s.$2, category: _cat(s.$3), imageUrl: photo));
  }
  final cover = none ? null : (k == 1 ? places.first.imageUrl : shotUrl('route', _photo(k, 0)));
  return RouteItem(
    id: 'jr$k',
    branchId: k.isEven ? 'b1' : 'b2',
    name: name,
    routeType: type,
    distanceKm: km,
    durationMin: min,
    difficulty: diff,
    waypoints: [for (final s in stops) LatLng(s.$1, s.$2)],
    waypointLabels: [for (final s in stops) s.$3],
    coverImage: cover,
    images: cover == null ? const [] : [cover],
    pois: places,
    reviewAvg: k % 3 == 0 ? null : 4.0 + (k % 9) / 10,
    reviewCount: k % 3 == 0 ? 0 : 1 + k % 5,
    countries: countries,
  );
}

/// The 20 routes (live names and stops).
final kJourneyRoutes = <RouteItem>[
  _r(1, 'Beskydy a Valašsko', 190.0, 270, 'medium', 'loop', ['CZ'], const [(49.4614, 18.1492, 'Rožnov pod Radhoštěm (Valašské muzeum v přírodě)'), (49.3898, 18.2434, 'Soláň'), (49.3594, 18.2856, 'Velké Karlovice (kostel Panny Marie Sněžné)'), (49.3613, 18.3150, 'Restaurace: Valašská hospůdka Horal (Velké Karlovice)'), (49.3833, 18.4000, 'Bumbálka'), (49.5458, 18.4475, 'Lysá hora'), (49.4895, 18.2650, 'Pustevny')]),
  _r(2, 'Kutnohorsko a Železné hory', 70.0, 100, 'easy', 'loop', ['CZ'], const [(49.9610, 15.2880, 'Kutná Hora – Sedlec'), (49.9720, 15.2900, 'Kaňk'), (49.8910, 15.4890, 'Zámek Žleby'), (49.8310, 15.5560, 'Přehrada Pařížov'), (49.9480, 15.2670, 'Vlašský dvůr'), (49.9610, 15.2880, 'Kutná Hora')]),
  _r(3, 'Mikulčice a soutok Moravy', 70.0, 100, 'easy', 'poi', ['CZ'], const [(48.8064, 17.0500, 'Mikulčice'), (48.7450, 16.9550, 'Kostice – vinné sklepy'), (48.7230, 16.8850, 'Pohansko'), (48.6167, 16.9403, 'Soutok Moravy a Dyje'), (48.6800, 16.9400, 'Soutok Moravy a Dyje'), (48.7246, 16.9667, 'Lanžhot'), (48.8064, 17.0500, 'Mikulčice')]),
  _r(4, 'Mohelenská hadcová step a údolí Oslavy', 215.0, 285, 'medium', 'loop', ['CZ'], const [(49.3464, 15.2119, 'Mezná u Pelhřimova'), (49.3131, 15.5236, 'V Klučí'), (49.2169, 15.8736, 'Bazilika svatého Prokopa'), (49.1985, 16.2015, 'Památník Bible kralické'), (49.1650, 16.2350, 'Údolí Oslavy a Chvojnice'), (49.1585, 16.2646, 'Zřícenina Levnov (Ketkovický hrad)'), (49.0946, 16.2477, 'Zřícenina Templštejn')]),
  _r(5, 'Novohradské hory a Terčino údolí', 160.0, 255, 'medium', 'loop', ['CZ'], const [(48.9745, 14.4743, 'České Budějovice'), (48.8985, 14.6419, 'zámek Borovany'), (48.7896, 14.7786, 'Hrad Nové Hrady'), (48.7830, 14.7560, 'Terčino údolí – umělý vodopád'), (48.7770, 14.7620, 'Tvrz Cuknštejn'), (48.7423, 14.7290, 'Dobrá Voda u Nových Hradů'), (48.7280, 14.7220, 'Rozhledna Kraví hora')]),
  _r(6, 'Renesanční Kratochvíle a Zlatá stezka', 120.0, 195, 'medium', 'loop', ['CZ'], const [(48.9745, 14.4743, 'České Budějovice'), (49.0069, 14.2981, 'Dehtář'), (49.0637, 14.1701, 'Zámek Kratochvíle'), (49.0119, 13.9975, 'Prachatice – Velké náměstí'), (49.1367, 14.0064, 'Zřícenina hradu Helfenburk u Bavorova'), (49.1220, 14.0787, 'Bavorov – zámek a kostel'), (49.1010, 14.2078, 'Poutní kostel Lomec')]),
  _r(7, 'Rozhledny a zámek Přibyslav', 195.0, 260, 'medium', 'loop', ['CZ'], const [(49.3464, 15.2119, 'Mezná u Pelhřimova'), (49.5286, 15.2142, 'Želivský klášter'), (49.7770, 15.2170, 'Rozhledna Bohdanka'), (49.6140, 15.4133, 'hrad Lipnice nad Sázavou'), (49.5770, 15.5230, 'Rozhledna Vysoká'), (49.5992, 15.7169, 'Žižkova mohyla'), (49.5769, 15.7387, 'Zámek Přibyslav')]),
  _r(8, 'Slavkovské bojiště a zámky', 80.0, 115, 'easy', 'loop', ['CZ'], const [(49.1533, 16.8764, 'Slavkov u Brna'), (49.1634, 16.8827, 'Rozhledna Urbanov'), (49.1497, 17.0000, 'Zámek Bučovice'), (49.0507, 17.0945, 'Ždánický les'), (49.1281, 16.7614, 'Mohyla míru'), (49.1533, 16.8764, 'Slavkov u Brna')]),
  _r(9, 'Velehrad, Modrá a Buchlovské kopce', 55.0, 80, 'easy', 'loop', ['CZ'], const [(49.1064, 17.3939, 'Velehrad'), (49.1031, 17.4071, 'Archeoskanzen Modrá'), (49.0697, 17.4600, 'Uherské Hradiště'), (49.1400, 17.3800, 'Salaš'), (49.0970, 17.2280, 'Chřiby – Kazatelna'), (49.1100, 17.3600, 'Modrá'), (49.1064, 17.3939, 'Velehrad')]),
  _r(10, 'Vírská přehrada a horní Svratka', 220.0, 290, 'medium', 'loop', ['CZ'], const [(49.3464, 15.2119, 'Mezná u Pelhřimova'), (49.4131, 15.5350, 'Zaječí skok'), (49.4563, 15.8653, 'Baba – V Bukách'), (49.5545, 16.2960, 'Zřícenina hradu Aueršperk'), (49.5486, 16.3115, 'Zřícenina hradu Pyšolec'), (49.5697, 16.3226, 'Vírská přehrada'), (49.5901, 16.2542, 'Zřícenina hradu Dalečín')]),
  _r(11, 'Údolí Doubravy a Stvořidla', 155.0, 210, 'easy', 'loop', ['CZ'], const [(49.3464, 15.2119, 'Mezná u Pelhřimova'), (49.5139, 15.2694, 'Vodní nádrž Sedlice'), (49.6486, 15.3103, 'Melechov'), (49.6650, 15.3500, 'Stvořidla'), (49.7107, 15.3454, 'Vilémovický tis'), (49.7200, 15.6740, 'Zámek Chotěboř'), (49.6880, 15.6950, 'Údolí Doubravy')]),
  _r(12, 'Český ráj – skály a hrady', 55.0, 80, 'medium', 'loop', ['CZ'], const [(50.5870, 15.1600, 'Turnov'), (50.5880, 15.1760, 'Hrad Valdštejn'), (50.5420, 15.1960, 'Hrubá Skála'), (50.5140, 15.2290, 'Hrad Trosky'), (50.4820, 15.3150, 'Prachovské skály'), (50.5140, 15.0980, 'Hrad Kost'), (50.5870, 15.1600, 'Turnov')]),
  _r(13, 'Algarve – hory Monchique a Silves', 80.0, 115, 'medium', 'loop', ['PT'], const [(37.3186, -8.5556, 'Monchique'), (37.2894, -8.5581, 'Caldas de Monchique'), (37.1897, -8.4389, 'Hrad Silves'), (37.2015, -8.6988, 'Barragem da Bravura'), (37.3147, -8.5992, 'Fóia – nejvyšší vrchol Algarve'), (37.3186, -8.5556, 'Monchique')]),
  _r(14, 'Alsaská vinná stezka – Riquewihr a Haut-Kœnigsbourg', 65.0, 95, 'easy', 'loop', ['FR'], const [(48.0778, 7.3556, 'Colmar'), (48.0733, 7.3585, 'Colmar – Petite Venise'), (48.0428, 7.3062, 'Eguisheim'), (48.1392, 7.2617, 'Kaysersberg'), (48.1667, 7.2986, 'Riquewihr'), (48.1953, 7.3196, 'Ribeauvillé'), (48.2494, 7.3444, 'Château du Haut-Kœnigsbourg')]),
  _r(15, 'Aurlandsfjellet – Snøvegen a vyhlídka Stegastein', 90.0, 150, 'medium', 'poi', ['NO'], const [(60.8630, 7.1130, 'Flåm'), (60.9047, 7.2110, 'Stegastein'), (60.9180, 7.2309, 'Aurlandsfjellet – Snøvegen'), (60.9600, 7.3600, 'Aurlandsfjellet – plató'), (61.0996, 7.4810, 'Lærdalsøyri'), (61.0470, 7.8122, 'Borgund stavkirke')]),
  _r(16, 'Coimbra a Serra da Lousã', 85.0, 120, 'medium', 'loop', ['PT'], const [(40.2056, -8.4194, 'Coimbra'), (40.2076, -8.4256, 'Univerzita Coimbra'), (40.0986, -8.4950, 'Conímbriga'), (40.0312, -8.3903, 'Penela – hrad'), (40.0810, -8.2380, 'Talasnal'), (40.0958, -8.2242, 'Hrad Lousã'), (40.2056, -8.4194, 'Coimbra')]),
  _r(17, 'Dobrudža – hory Măcin, Enisala a antická Histria', 280.0, 360, 'easy', 'loop', ['RO'], const [(45.1786, 28.8047, 'Tulcea'), (44.8828, 28.8367, 'Pevnost Enisala'), (44.5486, 28.7756, 'Antická Histria'), (44.8931, 28.7128, 'Mešita Gazi Ali Paši (Babadag)'), (45.0333, 28.4667, 'Horia'), (45.1892, 28.2286, 'Munții Măcinului'), (45.2117, 28.4156, 'Cocoș Monastery')]),
  _r(18, 'Eger, Bükk a Tokaj', 438.0, 626, 'medium', 'loop', ['HU'], const [(47.9039, 20.3794, 'Egerský hrad'), (47.8925, 20.3544, 'Údolí krásných paní (Szépasszony-völgy)'), (47.9953, 19.5881, 'Hollókő — vesnice UNESCO'), (48.1714, 19.8569, 'Šomoška'), (48.4719, 20.4954, 'Jeskyně Baradla, Aggtelek'), (48.1962, 21.2775, 'Synagogue Mád'), (48.1313, 21.3499, 'Restaurace: Bobajka (Tarcal)')]),
  _r(19, 'Helgeland – pobřežní cesta Fv17 za polární kruh', 350.0, 500, 'medium', 'poi', ['NO'], const [(65.4740, 12.2120, 'Brønnøysund'), (65.3970, 12.0930, 'Torghatten'), (66.0217, 12.6316, 'De syv søstre – Sedm sester'), (66.3969, 13.4083, 'Helgåvatnet'), (66.6790, 13.8500, 'Svartisen – ledovec Engabreen'), (66.8906, 14.1480, 'Langvatnet'), (67.1433, 14.4431, 'Valnesvatnet')]),
  _r(20, 'Historické vesnice středního Portugalska', 425.0, 605, 'medium', 'poi', ['PT'], const [(39.3606, -9.1572, 'Óbidos'), (39.5056, -8.6158, 'Cave of Aroeira'), (39.6039, -8.4189, 'Templářský klášter v Tomaru'), (39.5428, -8.3197, 'Castelo do Bode Dam'), (39.4798, -7.9980, 'Belver Dam'), (39.4147, -7.4553, 'Castelo de Vide'), (39.3936, -7.3778, 'Marvão')]),
];
