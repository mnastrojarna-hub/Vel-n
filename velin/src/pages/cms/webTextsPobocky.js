// Texty webu: Pobočky — přehled /pobocky + vlastní stránka každé pobočky
// (/pobocky/mezna, /pobocky/velke-nemcice). Defaulty PŘESNĚ z
// motogo-web-php/data/pobocky.php a appky (features/branches/branches_info_provider.dart)
// — změna textu se projeví na webu i v appce (Profil → Pobočky). Video pobočky
// (pole typu 'video') se nahrává do bucketu `media` nebo se vloží odkaz na YouTube.
// Fotky poboček se doplní v kódu.
// Viditelnost e-shopu v menu řídí feature flag `eshop_visible` (záložka Feature flags).
const branchPage = (i, id, label, url, d) => ({
  id, label, icon: i === 0 ? '🏍️' : '🔑', url,
  description: `Vlastní stránka pobočky ${url} (na přehledu /pobocky jen karta s odkazem) + detail v appce.`,
  sections: [
    { id: 'info', label: 'Pobočka — texty', location: 'Karta pobočky (přehled + detail)', fields: [
    { key: `web.pobocky.branches.${i}.badge`, label: 'Štítek (typ pobočky)', default: d.badge },
    { key: `web.pobocky.branches.${i}.title`, label: 'Název', default: d.title },
    { key: `web.pobocky.branches.${i}.address`, label: 'Adresa', default: d.address },
    { key: `web.pobocky.branches.${i}.hours`, label: 'Provozní doba', type: 'textarea', default: d.hours },
    { key: `web.pobocky.branches.${i}.text`, label: 'Popis pobočky', type: 'textarea', default: d.text },
    { key: `web.pobocky.branches.${i}.gear`, label: 'Výbava a velikosti', type: 'textarea', default: d.gear },
    { key: `web.pobocky.branches.${i}.steps_title`, label: 'Nadpis postupu', default: d.steps_title },
    { key: `web.pobocky.branches.${i}.steps`, label: 'Postup (každý krok na nový řádek)', type: 'textarea', default: d.steps },
    ] },
    { id: 'video', label: 'Video', location: 'Na stránce pobočky pod postupem (bez videa se sekce nezobrazí)', fields: [
      { key: `web.pobocky.branches.${i}.video`, label: 'Video (nahrát MP4 / odkaz YouTube)', type: 'video', storagePrefix: `branches/${url.split('/').pop()}/`, default: '' },
      { key: `web.pobocky.branches.${i}.video_title`, label: 'Nadpis nad videem', default: d.video_title },
    ] },
    { id: 'seo', label: 'SEO (meta v hlavičce – Google)', location: 'Neviditelné — titulek a popisek stránky pobočky', fields: [
      { key: `web.pobocky.branches.${i}.seo_title`, label: 'Meta title', default: d.seo_title },
      { key: `web.pobocky.branches.${i}.seo_description`, label: 'Meta description', type: 'textarea', default: d.seo_description },
    ] },
  ],
})

export const PAGE_POBOCKY = {
  id: 'pobocky', label: 'Pobočky – přehled', icon: '📍', url: '/pobocky',
  description: 'Přehled poboček — web /pobocky (v menu místo e-shopu) a appka Profil → Pobočky. Texty jednotlivých poboček mají vlastní stránky „Pobočka Mezná“ / „Pobočka Velké Němčice“.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní text',
      fields: [
        { key: 'web.pobocky.h1', label: 'H1', default: 'Pobočky MotoGo24' },
        { key: 'web.pobocky.intro', label: 'Úvodní text', type: 'textarea', default: 'Motorku si u nás vyzvednete na <strong>dvou místech</strong> — na <strong>obslužné pobočce v Mezné u Pelhřimova</strong>, kde vás přivítáme osobně, nebo na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong>, kde si motorku i výbavu převezmete sami pomocí kódů.' },
      ]
    },
    {
      id: 'links', label: 'Odkazy', location: 'Tlačítko na kartě pobočky (přehled) a odkaz zpět (detail)',
      fields: [
        { key: 'web.pobocky.detail_button', label: 'Tlačítko na kartě', default: 'Detail pobočky' },
        { key: 'web.pobocky.back_link', label: 'Odkaz zpět na přehled', default: '← Všechny pobočky' },
      ]
    },
    {
      id: 'cta', label: 'Zelený box s tlačítkem', location: 'Dole na přehledu i na stránce pobočky',
      fields: [
        { key: 'web.pobocky.cta.title', label: 'Nadpis', default: 'Vyberte si motorku na své pobočce' },
        { key: 'web.pobocky.cta.text', label: 'Text', type: 'textarea', default: 'V rezervaci uvidíte u každé motorky, na které pobočce je k dispozici.' },
        { key: 'web.pobocky.cta.button', label: 'Tlačítko — text', default: 'REZERVOVAT ONLINE' },
      ]
    },
    {
      id: 'seo_meta', label: 'SEO (meta v hlavičce – Google)', location: 'Neviditelné — titulek a popisek ve výsledcích vyhledávání',
      fields: [
        { key: 'web.pobocky.seo.title', label: 'Meta title', default: 'Pobočky | MotoGo24 – půjčovna motorek Pelhřimov a Brno' },
        { key: 'web.pobocky.seo.description', label: 'Meta description', type: 'textarea', default: 'Pobočky půjčovny motorek MotoGo24: obslužná pobočka Mezná u Pelhřimova (Vysočina) a samoobslužná pobočka Velké Němčice u Brna — převzetí motorky nonstop.' },
        { key: 'web.pobocky.seo.keywords', label: 'Meta keywords', default: 'pobočky MotoGo24, půjčovna motorek Pelhřimov, půjčovna motorek Brno, samoobslužná půjčovna motorek, Velké Němčice, Mezná' },
      ]
    },
  ],
}

export const PAGE_POBOCKA_MEZNA = branchPage(0, 'pobocka-mezna', 'Pobočka Mezná', '/pobocky/mezna', {
      badge: 'Obslužná pobočka',
      title: 'Mezná u Pelhřimova',
      address: 'Mezná 9, 393 01 Pelhřimov',
      hours: 'PO – NE nonstop, včetně víkendů a svátků. Čas převzetí a vrácení si zvolíte v rezervaci.',
      text: 'Naše hlavní pobočka na Vysočině. Motorku vám <strong>předáme osobně</strong> — vše vysvětlíme, pomůžeme s nastavením a výběrem výbavy a společně projdeme předávací protokol. Výbava pro řidiče je v ceně. Odtud nabízíme i <strong>přistavení motorky</strong> na vámi zvolenou adresu.',
      gear: 'Výbava pro řidiče v ceně — bundy a kalhoty ve velikostech až do <strong>6XL</strong>.',
      steps_title: 'Jak to probíhá',
      video_title: 'Video: jak to na pobočce probíhá',
      seo_title: 'Pobočka Mezná u Pelhřimova | MotoGo24 – obslužná půjčovna motorek',
      seo_description: 'Obslužná pobočka půjčovny motorek MotoGo24 v Mezné u Pelhřimova (Vysočina): osobní předání motorky nonstop, výbava v ceně, přistavení na adresu.',
      steps: '1. Rezervujete a zaplatíte online (web nebo aplikace).<br>2. Ve zvolený čas přijedete na pobočku, kde vás čekáme.<br>3. Předáme motorku i výbavu a podepíšeme předávací protokol.<br>4. Po jízdě motorku vrátíte na pobočku (nebo si ji vyzvedneme na domluvené adrese).',
})
export const PAGE_POBOCKA_NEMCICE = branchPage(1, 'pobocka-velke-nemcice', 'Pobočka Velké Němčice', '/pobocky/velke-nemcice', {
      badge: 'Samoobslužná pobočka',
      title: 'Velké Němčice u Brna',
      address: 'Boudky, 691 63 Velké Němčice',
      hours: 'Nonstop 24/7, bez zadávání času — motorku převezmete kdykoliv první den a vrátíte kdykoliv poslední den výpůjčky (ve smlouvě 00:01–24:00, skutečný čas převzetí zapíše předávací protokol).',
      text: 'Moderní <strong>samoobslužná pobočka</strong> jižně od Brna. Na místě není obsluha — vše vyřídíte sami na dotykovém displeji pomocí <strong>kódů z aplikace</strong>, které dostanete po zaplacení a doplnění dokladů. Motorky z této pobočky se přebírají i vracejí jen přímo na pobočce — přistavení ani odvoz u nich nenabízíme. U pobočky můžete po celou dobu výpůjčky <strong>parkovat zdarma</strong>.',
      gear: 'Výbava pro řidiče v ceně — bundy a kalhoty do velikosti <strong>4XL</strong> (větší velikosti až do 6XL nabízíme v Mezné). Výbavu si v šatně vyzkoušíte, a když vám velikost nesedí, vezmete si jinou dostupnou a v předávacím protokolu ji jen označíte.',
      steps_title: 'Jak to probíhá',
      video_title: 'Video: jak se obsloužit na samoobslužné pobočce',
      seo_title: 'Samoobslužná pobočka Velké Němčice u Brna | MotoGo24',
      seo_description: 'Samoobslužná pobočka půjčovny motorek MotoGo24 ve Velkých Němčicích u Brna: převzetí i vrácení 24/7 kódem z aplikace, bez zadávání času, parkování zdarma.',
      steps: '1. Rezervujete a zaplatíte online, doplníte doklady — kódy najdete v aplikaci i v e-mailu.<br>2. Na pobočce zadáte kód šatny a vezmete si výbavu (s vlastní výbavou šatnu přeskočíte).<br>3. Na displeji podepíšete předávací protokol.<br>4. Kódem motorky otevřete kóji s motorkou a vyrazíte.<br>5. Po jízdě motorku vrátíte do kóje a výbavu do šatny.',
})
