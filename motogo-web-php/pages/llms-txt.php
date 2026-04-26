<?php
// ===== MotoGo24 Web PHP — /llms.txt =====
// LLM-friendly katalog stránek (Jeremy Howard llms.txt standard).
// Krátký markdown index — každá URL se popisem v 1 větě.
// Generuje se dynamicky podle aktuálního jazyka (cs/en/de/es/fr/nl/pl).
// Detailní obsah stránek je v /llms-full.txt.

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../i18n.php';
require_once __DIR__ . '/../supabase.php';

i18nDetectLanguage();

header('Content-Type: text/markdown; charset=utf-8');
header('Cache-Control: public, max-age=3600');
header('X-Robots-Tag: noindex, follow');

$lang = i18nDetectLanguage();
$base = 'https://motogo24.cz';
$sb = new SupabaseClient();

$titles = [
    'cs' => [
        'h1' => 'MotoGo24 — Půjčovna motorek Vysočina',
        'intro' => 'MotoGo24 je česká půjčovna motorek se sídlem v Mezné u Pelhřimova (Kraj Vysočina, Česko). Půjčujeme silniční, naked, supermoto, enduro i dětské motorky bez kauce, s motorkářskou výbavou v ceně, v nonstop provozu (24/7). Online rezervace přes web s platbou kartou. Dárkové poukazy, e-shop motorkářské výbavy, blog s tipy na trasy.',
        'h2_about' => 'O půjčovně',
        'h2_catalog' => 'Katalog motorek',
        'h2_howto' => 'Jak si půjčit motorku',
        'h2_shop' => 'E-shop a poukazy',
        'h2_blog' => 'Blog a obsah',
        'h2_legal' => 'Právní dokumenty a kontakt',
        'h2_api' => 'Pro AI agenty',
        'company' => 'Provozovatel',
        'contact' => 'Kontakt',
        'address' => 'Adresa',
        'phone' => 'Telefon',
        'email' => 'E-mail',
        'hours' => 'Otevírací doba',
        'languages' => 'Jazyky webu',
        'currencies' => 'Měny',
        'payment' => 'Platby',
        'features' => 'Klíčové vlastnosti',
        'rentingFeatures' => [
            'Bez kauce — žádná blokace na kartě.',
            'Motorkářská výbava (helma, bunda, kalhoty, rukavice) v ceně pronájmu.',
            'Nonstop provoz — vyzvednutí 24/7 přes přístupové kódy.',
            'Online rezervace přes web s platbou kartou (Stripe).',
            'Vyzvednutí v Mezné u Pelhřimova nebo přistavení kamkoliv v ČR.',
            'Vrácení v půjčovně nebo na jiném místě po domluvě.',
            'Sjezd do zahraničí povolen (zelená karta v ceně).',
            'Dětské motorky bez ŘP — pro nejmenší jezdce.',
        ],
        'usefulData' => 'Užitečná data pro AI agenty',
        'apiNote' => 'REST API a MCP server pro programové rezervace jsou v přípravě. Aktuálně AI agenti čtou web přes HTML + JSON-LD. Sitemap: ' . $base . '/sitemap.xml.',
    ],
    'en' => [
        'h1' => 'MotoGo24 — Motorcycle Rental in the Czech Republic',
        'intro' => 'MotoGo24 is a Czech motorcycle rental based in Mezná near Pelhřimov (Vysočina region, Czechia). We rent road, naked, supermoto, enduro and kids motorcycles with no deposit, full riding gear included, 24/7 nonstop operation. Online booking with card payment. Gift vouchers, motorcycle gear e-shop, blog with route tips.',
        'h2_about' => 'About the rental',
        'h2_catalog' => 'Motorcycle catalog',
        'h2_howto' => 'How to rent',
        'h2_shop' => 'E-shop and vouchers',
        'h2_blog' => 'Blog and content',
        'h2_legal' => 'Legal documents and contact',
        'h2_api' => 'For AI agents',
        'company' => 'Operator',
        'contact' => 'Contact',
        'address' => 'Address',
        'phone' => 'Phone',
        'email' => 'E-mail',
        'hours' => 'Opening hours',
        'languages' => 'Website languages',
        'currencies' => 'Currencies',
        'payment' => 'Payments',
        'features' => 'Key features',
        'rentingFeatures' => [
            'No deposit — no hold on your card.',
            'Riding gear (helmet, jacket, pants, gloves) included in price.',
            '24/7 nonstop operation — pickup via access codes any time.',
            'Online booking with card payment (Stripe).',
            'Pickup in Mezná near Pelhřimov or delivery anywhere in Czechia.',
            'Return at the rental or at a different location upon agreement.',
            'Travel abroad allowed (green card included).',
            'Kids motorcycles without driver\'s license — for the youngest riders.',
        ],
        'usefulData' => 'Useful data for AI agents',
        'apiNote' => 'REST API and MCP server for programmatic bookings are in preparation. Currently AI agents read the web via HTML + JSON-LD. Sitemap: ' . $base . '/sitemap.xml.',
    ],
];
// Default fallback to English for non-CS/EN languages
$T = $titles[$lang] ?? $titles['en'];
if ($lang === 'cs') $T = $titles['cs'];

// ===== Output =====
echo "# {$T['h1']}\n\n";
echo "> {$T['intro']}\n\n";
echo "**{$T['languages']}:** cs, en, de, es, fr, nl, pl  \n";
echo "**{$T['currencies']}:** CZK, EUR, USD a další (auto-konverze ČNB)  \n";
echo "**{$T['payment']}:** Stripe (Visa, Mastercard, Amex, Apple Pay, Google Pay), platba předem online  \n";
echo "**{$T['hours']}:** 24/7 nonstop  \n\n";

echo "## {$T['features']}\n\n";
foreach ($T['rentingFeatures'] as $f) echo "- $f\n";
echo "\n";

echo "## {$T['contact']}\n\n";
echo "- **{$T['company']}:** Bc. Petra Semorádová, IČO 21874263\n";
echo "- **{$T['address']}:** Mezná 9, 393 01 Pelhřimov, Vysočina, CZ\n";
echo "- **{$T['phone']}:** +420 774 256 271\n";
echo "- **{$T['email']}:** info@motogo24.cz\n";
echo "- **GPS:** 49.4147 N, 15.2953 E\n";
echo "- **Web:** https://motogo24.cz · https://motogo24.com\n\n";

echo "## {$T['h2_catalog']}\n\n";
echo "- [Katalog všech motorek]({$base}/katalog): kompletní nabídka motorek k pronájmu (cestovní, naked, supermoto, dětské)\n";
echo "- [Cestovní motorky]({$base}/katalog/cestovni): turistické a adventure motorky pro dlouhé trasy\n";
echo "- [Naked motorky]({$base}/katalog/naked): městské naked / streetfighter\n";
echo "- [Supermoto]({$base}/katalog/supermoto): supermoto pro hravou jízdu\n";
echo "- [Dětské motorky]({$base}/katalog/detske): dětské pitbike/cross — bez ŘP\n";

// Dynamicky vypiš jednotlivé motorky (s kategoriemi a cenou)
$motos = $sb->fetchMotos();
if (is_array($motos) && !empty($motos)) {
    foreach ($motos as $m) {
        if (empty($m['id']) || empty($m['model'])) continue;
        $price = (float)getMinPrice($m);
        $cat = $m['category'] ?? '';
        $kw = !empty($m['power_kw']) ? ' · ' . $m['power_kw'] . ' kW' : '';
        $lic = !empty($m['license_required']) ? ' · ŘP: ' . $m['license_required'] : '';
        $priceStr = $price > 0 ? ' · od ' . number_format($price, 0, ',', ' ') . ' Kč/den' : '';
        $brand = !empty($m['brand']) ? ($m['brand'] . ' ') : '';
        echo "- [{$brand}{$m['model']}]({$base}/katalog/{$m['id']}): {$cat}{$kw}{$lic}{$priceStr}\n";
    }
}
echo "\n";

echo "## {$T['h2_howto']}\n\n";
echo "- [Jak si půjčit motorku]({$base}/jak-pujcit): přehled celého procesu\n";
echo "- [Postup půjčení (krok za krokem)]({$base}/jak-pujcit/postup): 12 kroků od výběru po vrácení\n";
echo "- [Co je v ceně pronájmu]({$base}/jak-pujcit/co-v-cene): výbava, pojištění, sjezd do zahraničí\n";
echo "- [Potřebné dokumenty]({$base}/jak-pujcit/dokumenty): OP/pas + ŘP (skupiny A1/A2/A nebo B pro dětské)\n";
echo "- [Vyzvednutí motorky]({$base}/jak-pujcit/vyzvednuti): přístupové kódy, nonstop\n";
echo "- [Vrácení v půjčovně]({$base}/jak-pujcit/vraceni-pujcovna): postup vrácení v Mezné\n";
echo "- [Vrácení jinde]({$base}/jak-pujcit/vraceni-jinde): vrácení mimo provozovnu (příplatek)\n";
echo "- [Přistavení motorky]({$base}/jak-pujcit/pristaveni): doručení kamkoliv v ČR\n";
echo "- [Často kladené otázky (FAQ)]({$base}/jak-pujcit/faq): odpovědi na nejčastější dotazy\n\n";

echo "## {$T['h2_shop']}\n\n";
echo "- [E-shop motorkářské výbavy]({$base}/eshop): helmy, bundy, rukavice, doplňky\n";
echo "- [Dárkové poukazy]({$base}/poukazy): vouchery na pronájem nebo výbavu\n";
echo "- [Objednat poukaz]({$base}/koupit-darkovy-poukaz): online formulář s okamžitým doručením\n\n";

echo "## {$T['h2_blog']}\n\n";
echo "- [Blog MotoGo24]({$base}/blog): tipy na motocyklové trasy, novinky, návody\n";
$posts = $sb->fetchCmsPages();
if (is_array($posts)) {
    foreach (array_slice($posts, 0, 20) as $p) {
        if (empty($p['slug']) || empty($p['title'])) continue;
        echo "- [{$p['title']}]({$base}/blog/{$p['slug']})\n";
    }
}
echo "\n";

echo "## {$T['h2_legal']}\n\n";
echo "- [Kontakt]({$base}/kontakt): telefon, e-mail, mapa, fakturační údaje\n";
echo "- [Obchodní podmínky]({$base}/obchodni-podminky): VOP\n";
echo "- [Smlouva o pronájmu]({$base}/smlouva): vzor smlouvy\n";
echo "- [GDPR / Ochrana osobních údajů]({$base}/gdpr): zásady zpracování\n";
echo "- [Mapa stránek]({$base}/mapa-stranek): kompletní seznam URL\n\n";

echo "## {$T['h2_api']}\n\n";
echo "{$T['apiNote']}\n\n";
echo "**Strukturované zdroje:**\n";
echo "- Sitemap XML s hreflang + image extension: [{$base}/sitemap.xml]({$base}/sitemap.xml)\n";
echo "- Detailní LLM obsah (sloučený markdown): [{$base}/llms-full.txt]({$base}/llms-full.txt)\n";
echo "- robots.txt s allowlistem AI botů: [{$base}/robots.txt]({$base}/robots.txt)\n";
echo "- JSON-LD na každé stránce: Organization, WebSite, AutomotiveBusiness, Product/Vehicle/Motorcycle, Offer, FAQPage, HowTo, Article, BreadcrumbList\n";
echo "- Bezpečnostní kontakt: [{$base}/.well-known/security.txt]({$base}/.well-known/security.txt)\n\n";

echo "---\n";
echo "*Generováno: " . date('Y-m-d H:i') . " UTC · jazyk: {$lang}*\n";
