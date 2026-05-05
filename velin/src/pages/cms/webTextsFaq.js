// Texty webu: Header / Footer (chrome).
// Klíče zde MUSÍ odpovídat tomu, co PHP `tc('<key>')` v `motogo-web-php/layout.php`
// reálně čte — `tc()` mapuje `web.layout.<key>` v cms_variables zpět na `t('<key>')`
// z `lang/cs.php`. Když uživatel uloží ve Velíně tučnění/HTML, šablona to
// po fix `tc()` 2026-05-05 renderuje raw → formátování funguje.
export const PAGE_LAYOUT = {
  id: 'layout', label: 'Header & Footer', icon: '🧩', url: '(celý web)',
  description: 'Globální texty zobrazené na všech stránkách – hlavička a patička. Editor podporuje tučně/kurzíva/barva.',
  sections: [
    {
      id: 'header', label: 'Header (hlavička)', location: 'Horní lišta s logem, telefonem a menu',
      fields: [
        { key: 'web.layout.header.menuToggle', label: 'Tlačítko MENU', default: 'MENU ☰' },
      ]
    },
    {
      id: 'menu', label: 'Hlavní menu', location: 'Položky horního menu (zobrazují se i v patičce)',
      fields: [
        { key: 'web.layout.menu.rental', label: 'Půjčovna motorek', default: 'Půjčovna motorek' },
        { key: 'web.layout.menu.catalog', label: 'Katalog motorek', default: 'Katalog motorek' },
        { key: 'web.layout.menu.howto', label: 'Jak si půjčit', default: 'Jak si půjčit motorku' },
        { key: 'web.layout.menu.howto.process', label: 'Postup půjčení', default: 'Postup půjčení motorky' },
        { key: 'web.layout.menu.howto.pickup', label: 'Převzetí v půjčovně', default: 'Převzetí v půjčovně' },
        { key: 'web.layout.menu.howto.returnHome', label: 'Vrácení v půjčovně', default: 'Vrácení motocyklu v půjčovně' },
        { key: 'web.layout.menu.howto.returnElsewhere', label: 'Vrácení jinde', default: 'Vrácení motorky jinde' },
        { key: 'web.layout.menu.howto.price', label: 'Co je v ceně', default: 'Co je v ceně nájmu' },
        { key: 'web.layout.menu.howto.delivery', label: 'Přistavení', default: 'Přistavení motocyklu' },
        { key: 'web.layout.menu.howto.documents', label: 'Dokumenty', default: 'Dokumenty a návody' },
        { key: 'web.layout.menu.howto.faq', label: 'FAQ', default: 'Často kladené dotazy' },
        { key: 'web.layout.menu.vouchers', label: 'Poukazy', default: 'Poukazy' },
        { key: 'web.layout.menu.shop', label: 'E-shop', default: 'E-shop' },
        { key: 'web.layout.menu.blog', label: 'Blog', default: 'Blog' },
        { key: 'web.layout.menu.contact', label: 'Kontakt', default: 'Kontakt' },
        { key: 'web.layout.menu.reservation', label: 'REZERVACE (CTA)', default: 'REZERVACE' },
        { key: 'web.layout.menu.editReservation', label: 'Upravit rezervaci', default: 'Upravit rezervaci' },
      ]
    },
    {
      id: 'footer', label: 'Footer (patička)', location: 'Dolní část webu na každé stránce',
      fields: [
        { key: 'web.layout.footer.aboutTitle', label: 'Nadpis "O nás"', default: 'Půjčovna motorek' },
        { key: 'web.layout.footer.aboutText', label: 'Úvodní text patičky (HTML povolen)', type: 'textarea', default: 'Vítejte u Motogo24, vaší <strong>půjčovny motorek v Pelhřimově</strong>! Nabízíme <strong>pronájem motorek</strong> pro místní i turisty. Vyberte si z nabídky sportovních nebo enduro motorek a rezervujte online ve třech krocích.' },
        { key: 'web.layout.footer.socialTitle', label: 'Nadpis sociální sítě', default: 'Půjčovna motorek na sítích' },
        { key: 'web.layout.footer.helpTitle', label: 'Nadpis pomoc', default: 'Potřebujete poradit?' },
        { key: 'web.layout.footer.callUs', label: 'Label "ZAVOLEJTE NÁM"', default: 'ZAVOLEJTE NÁM' },
        { key: 'web.layout.footer.companyLine1', label: 'Název firmy v patičce', default: 'Půjčovna motorek Motogo24' },
        { key: 'web.layout.footer.openHours', label: 'Provozní doba', default: 'PO - NE 00:00 – 24:00 (nonstop)' },
        { key: 'web.layout.footer.copyright', label: 'Copyright', default: '© Půjčovna motorek Vysočina Motogo24 - všechna práva vyhrazena' },
        { key: 'web.layout.footer.sitemap', label: 'Odkaz "Mapa stránek"', default: 'Mapa stránek' },
        { key: 'web.layout.footer.cookies', label: 'Odkaz "Cookies"', default: 'Cookies' },
        { key: 'web.layout.footer.gdpr', label: 'Odkaz "GDPR"', default: 'GDPR' },
        { key: 'web.layout.footer.terms', label: 'Odkaz "Obchodní podmínky"', default: 'Obchodní podmínky' },
        { key: 'web.layout.footer.contract', label: 'Odkaz "Smlouva o pronájmu"', default: 'Smlouva o pronájmu' },
      ]
    },
  ]
}
