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
  ]
}
