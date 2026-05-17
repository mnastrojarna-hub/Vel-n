// Texty webu: Katalog motorek (/katalog)
// Klíče mapují strukturu siteContent('katalog') v motogo-web-php/pages/katalog.php.
// Editace ve Velínu = okamžitý dopad na hlavičku /katalog.
// Pozn.: SEO description/keywords jsou taženy z lang/cs.php (filters.*) — nejsou součástí
// CMS overlay. Texty filtrů (kategorie, řidičák, výkon, řazení) zůstávají v překladech.
export const PAGE_KATALOG = {
  id: 'katalog', label: 'Katalog motorek', icon: '🏍️', url: '/katalog',
  description: 'Hlavička stránky /katalog — H1 nadpis a úvodní odstavec nad filtry.',
  sections: [
    {
      id: 'header', label: 'Hlavička katalogu', location: 'Horní část stránky /katalog — nad filtry a výpisem motorek',
      fields: [
        { key: 'web.katalog.h1', label: 'H1 nadpis', default: 'Katalog motorek' },
        { key: 'web.katalog.intro', label: 'Úvodní odstavec (HTML povolený)', type: 'textarea', default: 'Vyberte si z naší nabídky <strong>cestovních, sportovních, enduro i dětských motorek</strong>. Můžete filtrovat podle kategorie, řidičského průkazu, výkonu, ceny a dalších parametrů.' },
      ]
    },
    {
      id: 'outro', label: 'Sekce pod gridem', location: 'Pod výpisem motorek — H2 + 2 odstavce. Slouží pro SEO obsah a vysvětlení katalogu.',
      fields: [
        { key: 'web.katalog.outro.title', label: 'H2 nadpis', default: 'Jak si vybrat motorku v našem katalogu' },
        { key: 'web.katalog.outro.body1', label: '1. odstavec (HTML povolený)', type: 'textarea', default: 'V katalogu motorek MotoGo24 najdete pečlivě udržované stroje pro každý typ jízdy — od pohodlných <strong>cestovních motorek</strong> na dlouhé túry přes hbité <strong>naked stroje</strong> do města, ostré <strong>supermoto</strong> pro zábavu na zatáčkách až po bezpečné <strong>dětské elektromotorky</strong>. Filtrovat můžete podle kategorie, řidičského oprávnění, výkonu v kW, maximální ceny za den i podle toho, jestli má motorka <strong>ABS</strong> nebo místo pro spolujezdce.' },
        { key: 'web.katalog.outro.body2', label: '2. odstavec (HTML povolený)', type: 'textarea', default: 'Každá motorka v naší flotile má v detailu uvedené kompletní technické parametry, fotky i ceník po dnech. Půjčení probíhá <strong>bez kauce</strong>, výbava pro řidiče (helma, bunda, kalhoty, rukavice) je <strong>v ceně nájmu</strong> a vyzvednutí si můžete domluvit i mimo otevírací dobu díky <strong>nonstop provozu</strong>. Pokud si nejste jistí výběrem, ozvěte se nám telefonicky nebo e-mailem — rádi vám poradíme, která motorka je pro vás ta pravá.' },
      ]
    },
  ]
}
