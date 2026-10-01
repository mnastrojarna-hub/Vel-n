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
  'branches.0.gear': 'Výbava pro řidiče v ceně — bundy a kalhoty ve velikostech až do <strong>6XL</strong>.',
  'branches.0.steps_title': 'Jak to probíhá',
  'branches.0.steps': '1. Rezervujete a zaplatíte online (web nebo aplikace).<br>2. Ve zvolený čas přijedete na pobočku, kde vás čekáme.<br>3. Předáme motorku i výbavu a podepíšeme předávací protokol.<br>4. Po jízdě motorku vrátíte na pobočku (nebo si ji vyzvedneme na domluvené adrese).',
  'branches.0.video': '',
  'branches.0.video_title': 'Video: jak to na pobočce probíhá',
  'branches.1.badge': 'Samoobslužná pobočka',
  'branches.1.title': 'Velké Němčice u Brna',
  'branches.1.address': 'Boudky, 691 63 Velké Němčice',
  'branches.1.hours': 'Nonstop 24/7, bez zadávání času — motorku převezmete kdykoliv první den a vrátíte kdykoliv poslední den výpůjčky (ve smlouvě 00:01–24:00, skutečný čas převzetí zapíše předávací protokol).',
  'branches.1.text': 'Moderní <strong>samoobslužná pobočka</strong> jižně od Brna. Na místě není obsluha — vše vyřídíte sami na dotykovém displeji pomocí <strong>kódů z aplikace</strong>, které dostanete po zaplacení a doplnění dokladů. Motorky z této pobočky se přebírají i vracejí jen přímo na pobočce — přistavení ani odvoz u nich nenabízíme. U pobočky můžete po celou dobu výpůjčky <strong>parkovat zdarma</strong>.',
  'branches.1.gear': 'Výbava pro řidiče v ceně — bundy a kalhoty do velikosti <strong>4XL</strong> (větší velikosti až do 6XL nabízíme v Mezné). Výbavu si v šatně vyzkoušíte, a když vám velikost nesedí, vezmete si jinou dostupnou a v předávacím protokolu ji jen označíte.',
  'branches.1.steps_title': 'Jak to probíhá',
  'branches.1.steps': '1. Rezervujete a zaplatíte online, doplníte doklady — kódy najdete v aplikaci i v e-mailu.<br>2. Na pobočce zadáte kód šatny a vezmete si výbavu (s vlastní výbavou šatnu přeskočíte).<br>3. Na displeji podepíšete předávací protokol.<br>4. Kódem motorky otevřete kóji s motorkou a vyrazíte.<br>5. Po jízdě motorku vrátíte do kóje a výbavu do šatny.',
  'branches.1.video': '',
  'branches.1.video_title': 'Video: jak se obsloužit na samoobslužné pobočce',
  'cta.title': 'Vyberte si motorku na své pobočce',
  'cta.text': 'V rezervaci uvidíte u každé motorky, na které pobočce je k dispozici.',
  'cta.button': 'REZERVOVAT ONLINE',
  'detail_button': 'Detail pobočky',
};

/// Cíl navigace pro kartu pobočky (pořadí = `branches.<i>`); mapa jde z kódu
/// stejně jako na webu, CMS řídí jen texty.
const List<String> branchesInfoMapQueries = [
  'Mezná 9, 393 01 Pelhřimov',
  '49.0046725,16.6721528',
];

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
