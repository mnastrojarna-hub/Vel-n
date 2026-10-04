import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

/// Texty obrazovky „Pobočky“ — stejné klíče jako web `/pobocky`
/// (`cms_variables` `web.pobocky.*`, edituje Velín → Web CMS → Texty webu →
/// Pobočky). Defaulty = výchozí znění z `motogo-web-php/data/pobocky.php`
/// (při změně držet shodně i s `velin/src/pages/cms/webTextsPobocky.js`).
/// Cizí jazyk: překlad z `translations` (auto-překlad při uložení ve Velíně),
/// jinak český text.
const Map<String, String> branchesInfoDefaults = {
  'h1': 'Pobočky MotoGo24',
  'intro': 'Motorku si u nás vyzvednete na <strong>dvou místech</strong> — na <strong>obslužné pobočce v Mezné u Pelhřimova</strong>, kde vás přivítáme osobně, nebo na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong>, kde si motorku i výbavu převezmete sami pomocí kódů.',
  'branches.0.badge': 'Obslužná pobočka',
  'branches.0.title': 'Mezná u Pelhřimova',
  'branches.0.address': 'Mezná 9, 393 01 Pelhřimov',
  'branches.0.hours': 'PO – NE nonstop, včetně víkendů a svátků. Čas převzetí a vrácení si zvolíte v rezervaci.',
  'branches.0.text': 'Naše hlavní pobočka na Vysočině. Motorku vám <strong>předáme osobně</strong> — vše vysvětlíme, pomůžeme s nastavením a výběrem výbavy a společně projdeme předávací protokol. Výbava pro řidiče je v ceně. Odtud nabízíme i <strong>přistavení motorky</strong> na vámi zvolenou adresu.',
  'branches.0.gear': 'Výbava pro řidiče v ceně — bundy a kalhoty ve velikostech až do <strong>6XL</strong>. Jen tady si můžete zapůjčit i <strong>nepromoky</strong> a další doplňkovou výbavu.',
  'branches.0.steps_title': 'Jak to probíhá',
  'branches.0.steps': '1. Rezervujete a zaplatíte online (web nebo aplikace) a nahrajete doklady (OP/pas + ŘP) — žádáme o to i na obslužné pobočce; pokud je nenahrajete, zkontrolujeme je při převzetí na místě.<br>2. Ve zvolený čas přijedete na pobočku, kde vás čekáme.<br>3. Předáme motorku i výbavu a podepíšeme předávací protokol.<br>4. Po jízdě motorku vrátíte na pobočku (nebo si ji vyzvedneme na domluvené adrese).',
  'branches.0.video': '',
  'branches.0.video_title': 'Video: jak to na pobočce probíhá',
  'branches.1.badge': 'Samoobslužná pobočka',
  'branches.1.title': 'Velké Němčice u Brna',
  'branches.1.address': 'Boudky, 691 63 Velké Němčice',
  'branches.1.hours': 'Nonstop 24/7 kódem z aplikace. Čas vyzvednutí si zvolíte v rezervaci — při vyzvednutí od 12:00 (výpůjčka 2 a více dní) máte 1. den za polovinu a kiosk vám motorku vydá až od 12:00. Čas vrácení nevolíte: motorku vrátíte kdykoliv poslední den výpůjčky do 24:00.',
  'branches.1.text': 'Moderní <strong>samoobslužná pobočka</strong> jižně od Brna. Na místě není obsluha — vše vyřídíte sami na dotykovém displeji pomocí <strong>kódů z aplikace</strong>, které dostanete po zaplacení a doplnění dokladů. Motorky z této pobočky se přebírají i vracejí jen přímo na pobočce — přistavení ani odvoz u nich nenabízíme. U pobočky můžete po celou dobu výpůjčky <strong>parkovat zdarma</strong>.',
  'branches.1.gear': 'K dispozici je jen <strong>helma, bunda s páteřákem, kalhoty, rukavice, kukla a boty</strong> — výbava pro řidiče je v ceně, motocyklové boty za příplatek. Bundy a kalhoty do velikosti <strong>4XL</strong> (větší velikosti až do 6XL nabízíme v Mezné). <strong>Nepromoky</strong> ani další doplňkovou výbavu na samoobslužné pobočce nepůjčujeme — ty jsou jen na obslužné pobočce v Mezné. Výbavu si v šatně vyzkoušíte, a když vám velikost nesedí, vezmete si jinou dostupnou a v předávacím protokolu ji jen označíte. Reflexní vestu, lékárničku, záznam o nehodě, kotoučový zámek a klíček k držáku telefonu najdete v motorce.',
  'branches.1.steps_title': 'Jak to probíhá',
  'branches.1.steps': '1. Rezervujete a zaplatíte online, zvolíte čas vyzvednutí a nahrajete doklady (OP/pas + ŘP) — na samoobslužné pobočce je to nezbytné: bez ověřených dokladů kódy nedostanete a na pobočku se nedostanete. Po ověření dokladů dostanete v aplikaci, e-mailu a SMS kódy v pořadí, v jakém je budete zadávat: <strong>1) kód schránky s klíčem od brány, 2) kód šatny</strong> (máte-li zapůjčenou výbavu) <strong>a 3) kód motorky</strong>.<br>2. <strong>Je-li vjezdová brána zavřená</strong>, otevřete kódem z aplikace <strong>horní schránku na pravém sloupku vrat</strong> — je v ní klíč od visacího zámku. Bránu odemkněte, vjeďte dovnitř a zaparkujte na kterémkoli místě <strong>1–7 vpravo u plotu</strong> (viz fotka parkoviště). Auto tu může zdarma stát po celou dobu výpůjčky. Je-li brána otevřená, kód schránky nepotřebujete.<br>3. Na displeji zadáte kód šatny — <strong>šatna jsou dveře č. 8</strong>. Vezmete si výbavu, převléknete se a dveře šatny zavřete (s vlastní výbavou šatnu přeskočíte). Máte-li slevu za vyzvednutí od 12:00, kódy platí až od 12:00.<br>4. Na displeji v předávacím protokolu upravíte velikosti, protokol podepíšete a zadáte kód motorky — otevře se kóje s motorkou. Kóji zavřete a vyrazíte.<br>5. <strong>Byla-li brána zavřená, po odjezdu ji zase zavřete, zamkněte visacím zámkem, klíč vraťte do horní schránky a přetočte číselník.</strong> Otevřenou bránu nechte otevřenou — stav brány nikdy neměňte.<br>6. Po jízdě motorku vrátíte do kóje a výbavu do šatny — kdykoliv poslední den výpůjčky do 24:00. Je-li brána zavřená, postupujete stejně: odemknete ji klíčem ze schránky a po odjezdu ji zase zamknete a klíč vrátíte.',
  'branches.1.video': '',
  'branches.1.video_title': 'Video: jak se obsloužit na samoobslužné pobočce',
  'cta.title': 'Vyberte si motorku na své pobočce',
  'cta.text': 'V rezervaci si zvolíte pobočku a nabídnou se vám jen motorky, které na ní jsou.',
  'cta.button': 'REZERVOVAT ONLINE',
  'detail_button': 'Detail pobočky',
};

/// Cíl navigace pro kartu pobočky (pořadí = `branches.<i>`); mapa jde z kódu
/// stejně jako na webu, CMS řídí jen texty.
const List<String> branchesInfoMapQueries = [
  'Mezná 9, 393 01 Pelhřimov',
  '49.0046725,16.6721528',
];

/// `branches.id` pobočky karty (pořadí = `branches.<i>`, shodně s webem
/// `data/pobocky.php`) — „Rezervovat" z detailu pobočky ji předvybere ve
/// filtru motorek. 0 = Mezná (obslužná), 1 = Velké Němčice (samoobslužná).
const List<String> branchesInfoBranchIds = [
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
];

/// Fotogalerie pobočky (pořadí = `branches.<i>`, shodně s webem
/// `data/pobocky.php` `gallery`): soubor bez `.webp` v [branchesGalleryBase]
/// (náhled `-640.webp`, plná velikost `.webp`) + klíč přeloženého popisku.
/// Prázdný seznam = pobočka bez fotek (sekce „Fotky pobočky“ se nezobrazí).
const String branchesGalleryBase = 'https://www.motogo24.cz/gfx/pobocky/';
const List<List<BranchPhoto>> branchesInfoGallery = [
  [],
  [
    BranchPhoto('velke-nemcice/vydejni-box', 'branchPhotoBox'),
    BranchPhoto('velke-nemcice/vydejni-box-2', 'branchPhotoBox2'),
    BranchPhoto('velke-nemcice/displej-kiosk', 'branchPhotoKiosk'),
    BranchPhoto('velke-nemcice/parkoviste', 'branchPhotoParking'),
  ],
];

class BranchPhoto {
  final String file;
  final String captionKey;
  const BranchPhoto(this.file, this.captionKey);

  String get thumbUrl => '$branchesGalleryBase$file-640.webp';
  String get fullUrl => '$branchesGalleryBase$file.webp';
}

final branchesInfoProvider =
    FutureProvider.family<Map<String, String>, String>((ref, lang) async {
  final out = Map<String, String>.from(branchesInfoDefaults);
  const prefix = 'web.pobocky.';
  try {
    final rows = await MotoGoSupabase.client
        .from('cms_variables')
        .select('key, value, translations')
        .like('key', '$prefix%');
    for (final r in (rows as List)) {
      final key = (r['key'] ?? '').toString();
      if (!key.startsWith(prefix)) continue;
      final tail = key.substring(prefix.length);
      String? val = r['value']?.toString();
      if (lang != 'cs') {
        // {lang: {value: '…'}} nebo {lang: '…'}; bez překladu zůstane český text.
        final tr = r['translations'];
        final cand = tr is Map ? tr[lang] : null;
        final s = cand is Map ? cand['value']?.toString() : cand?.toString();
        if (s != null && s.trim().isNotEmpty) val = s;
      }
      if (val != null && val.trim().isNotEmpty) out[tail] = val;
    }
  } catch (_) {
    // Offline / chyba → výchozí texty.
  }
  return out;
});
