// Texty webu: FAQ + Header/Footer
export const PAGE_FAQ = {
  id: 'faq', label: 'FAQ', icon: '❓', url: '/jak-pujcit/faq',
  description: 'Často kladené dotazy ve všech kategoriích.',
  sections: [
    {
      id: 'intro', label: 'Úvod', location: 'H1 nadpis',
      fields: [
        { key: 'web.faq.h1', label: 'H1', default: 'Často kladené dotazy – půjčovna motorek Motogo24' },
        { key: 'web.faq.outro', label: 'Text pod FAQ', type: 'textarea', default: 'Naše půjčovna motorek Vysočina je tu pro všechny, kdo chtějí zažít nezapomenutelnou jízdu bez zbytečných komplikací.' },
      ]
    },
    {
      id: 'reservations', label: 'Rezervace (3 otázky)', location: 'Tab „Rezervace"',
      fields: [
        { key: 'web.faq.res.1.q', label: 'Otázka 1', default: 'Jak probíhá rezervace?' },
        { key: 'web.faq.res.1.a', label: 'Odpověď 1', default: 'Motorku si zarezervuješ přes náš online rezervační systém. Vybereš termín, motorku a výbavu. Potvrzení přijde e-mailem.' },
        { key: 'web.faq.res.2.q', label: 'Otázka 2', default: 'Musím mít rezervaci předem?' },
        { key: 'web.faq.res.2.a', label: 'Odpověď 2', default: 'Ano, bez předchozí rezervace neumíme zaručit dostupnost konkrétní motorky.' },
        { key: 'web.faq.res.3.q', label: 'Otázka 3', default: 'Jak zaplatím?' },
        { key: 'web.faq.res.3.a', label: 'Odpověď 3', default: 'Online kartou (Visa/Mastercard, Apple/Google Pay) nebo PayPal.' },
      ]
    },
    {
      id: 'borrowing', label: 'Výpůjčka a vrácení (5 otázek)', location: 'Tab „Výpůjčka a vrácení"',
      fields: [
        { key: 'web.faq.bor.1.q', label: 'Otázka 1', default: 'Kde probíhá vyzvednutí a vrácení?' },
        { key: 'web.faq.bor.1.a', label: 'Odpověď 1', default: 'V Pelhřimově (Mezná 9). Nabízíme i přistavení na domluvené místo.' },
        { key: 'web.faq.bor.2.q', label: 'Otázka 2', default: 'Do kdy musím motorku vrátit?' },
        { key: 'web.faq.bor.2.a', label: 'Odpověď 2', default: 'Kdykoli během posledního dne výpůjčky, klidně i o půlnoci.' },
        { key: 'web.faq.bor.3.q', label: 'Otázka 3', default: 'Musím vracet s plnou nádrží a čistou?' },
        { key: 'web.faq.bor.3.a', label: 'Odpověď 3', default: 'Ne. U nás netankuješ ani nemyješ. Jen prosíme o ohleduplné zacházení.' },
        { key: 'web.faq.bor.4.q', label: 'Otázka 4', default: 'Je možné vyřídit vše bez osobního kontaktu?' },
        { key: 'web.faq.bor.4.a', label: 'Odpověď 4', default: 'Ano, po domluvě zajišťujeme bezkontaktní předání.' },
        { key: 'web.faq.bor.5.q', label: 'Otázka 5', default: 'Co dělat, když nestihnu domluvený čas?' },
        { key: 'web.faq.bor.5.a', label: 'Odpověď 5', default: 'Stačí nám zavolat – společně najdeme náhradní termín.' },
      ]
    },
    {
      id: 'conditions', label: 'Výbava a podmínky (4 otázky)', location: 'Tab „Výbava a podmínky"',
      fields: [
        { key: 'web.faq.con.1.q', label: 'Otázka 1', default: 'Je v ceně půjčovného výbava řidiče?' },
        { key: 'web.faq.con.1.a', label: 'Odpověď 1', default: 'Ano. Helma, bunda, kalhoty, rukavice jsou vždy v ceně pro řidiče.' },
        { key: 'web.faq.con.2.q', label: 'Otázka 2', default: 'Je v ceně zahrnutá i výbava pro spolujezdce?' },
        { key: 'web.faq.con.2.a', label: 'Odpověď 2', default: 'Základní výbava pro řidiče je součástí, výbavu pro spolujezdce si můžeš přiobjednat jako doplňkovou službu.' },
        { key: 'web.faq.con.3.q', label: 'Otázka 3', default: 'Je nutná kauce?' },
        { key: 'web.faq.con.3.a', label: 'Odpověď 3', default: 'Ne. Motorky půjčujeme bez kauce a bez skrytých poplatků.' },
        { key: 'web.faq.con.4.q', label: 'Otázka 4', default: 'Jaké doklady potřebuji?' },
        { key: 'web.faq.con.4.a', label: 'Odpověď 4', default: 'OP/pas a řidičský průkaz odpovídající skupiny (A/A2 dle motorky).' },
      ]
    },
    {
      id: 'delivery', label: 'Přistavení (4 otázky)', location: 'Tab „Přistavení"',
      fields: [
        { key: 'web.faq.del.1.q', label: 'Otázka 1', default: 'Můžete motorku přistavit k hotelu/na nádraží?' },
        { key: 'web.faq.del.1.a', label: 'Odpověď 1', default: 'Ano, zajišťujeme přistavení motorky na domluvené místo. Cena dle vzdálenosti od Pelhřimova.' },
        { key: 'web.faq.del.2.q', label: 'Otázka 2', default: 'Jak přistavení objednám?' },
        { key: 'web.faq.del.2.a', label: 'Odpověď 2', default: 'Při online rezervaci doplň adresu a čas. Potvrdíme přesnou cenu.' },
        { key: 'web.faq.del.3.q', label: 'Otázka 3', default: 'Lze vrátit motorku jinde, než byla převzata?' },
        { key: 'web.faq.del.3.a', label: 'Odpověď 3', default: 'Ano, nabízíme svoz – účtujeme dle ceníku přistavení/svozu.' },
        { key: 'web.faq.del.4.q', label: 'Otázka 4', default: 'Jaká je cena přistavení mimo Vysočinu?' },
        { key: 'web.faq.del.4.a', label: 'Odpověď 4', default: 'Cena se odvíjí od ujeté vzdálenosti – do 100 km dle ceníku, dále individuální kalkulace.' },
      ]
    },
    {
      id: 'travel', label: 'Cesty do zahraničí (2 otázky)', location: 'Tab „Cesty do zahraničí"',
      fields: [
        { key: 'web.faq.tra.1.q', label: 'Otázka 1', default: 'Mohu s motorkou vycestovat do zahraničí?' },
        { key: 'web.faq.tra.1.a', label: 'Odpověď 1', default: 'Ano, ale drž se územní platnosti pojištění (zelená karta). Některé země mohou být vyloučené.' },
        { key: 'web.faq.tra.2.q', label: 'Otázka 2', default: 'Potřebuji něco speciálního do zahraničí?' },
        { key: 'web.faq.tra.2.a', label: 'Odpověď 2', type: 'textarea', default: 'Měj u sebe malý TP, zelenou kartu, kontakty na Motogo24 a kopii nájemní smlouvy. Doporučujeme cestovní pojištění.' },
      ]
    },
    {
      id: 'vouchers', label: 'Poukazy (5 otázek)', location: 'Tab „Poukazy"',
      fields: [
        { key: 'web.faq.vou.1.q', label: 'Otázka 1', default: 'Jaká je platnost dárkového poukazu?' },
        { key: 'web.faq.vou.1.a', label: 'Odpověď 1', default: '3 roky od data vystavení. Termín si obdarovaný volí sám dle dostupnosti.' },
        { key: 'web.faq.vou.2.q', label: 'Otázka 2', default: 'Na jaké motorky lze poukaz uplatnit?' },
        { key: 'web.faq.vou.2.a', label: 'Odpověď 2', default: 'Na cestovní, sportovní, enduro i dětské modely dle hodnoty poukazu a oprávnění.' },
        { key: 'web.faq.vou.3.q', label: 'Otázka 3', default: 'Musí obdarovaný platit kauci?' },
        { key: 'web.faq.vou.3.a', label: 'Odpověď 3', default: 'Ne, žádná kauce se neskládá. Podmínky jsou transparentní a výbava pro řidiče je v ceně.' },
        { key: 'web.faq.vou.4.q', label: 'Otázka 4', default: 'Jak voucher doručíte?' },
        { key: 'web.faq.vou.4.a', label: 'Odpověď 4', default: 'Okamžitě e-mailem po úhradě (PDF/JPG). Na požádání i tištěný voucher.' },
        { key: 'web.faq.vou.5.q', label: 'Otázka 5', default: 'Dá se termín uplatnění změnit?' },
        { key: 'web.faq.vou.5.a', label: 'Odpověď 5', default: 'Ano, po předchozí domluvě je možné termín upravit podle aktuální dostupnosti.' },
      ]
    },
  ]
}

export const PAGE_LAYOUT = {
  id: 'layout', label: 'Header & Footer', icon: '🧩', url: '(celý web)',
  description: 'Globální texty zobrazené na všech stránkách – hlavička a patička.',
  sections: [
    {
      id: 'header', label: 'Header (hlavička)', location: 'Horní lišta s logem, telefonem a menu',
      fields: [
        { key: 'web.layout.phone', label: 'Telefon', default: '+420 774 256 271' },
        { key: 'web.layout.logo.alt', label: 'Logo alt text', default: 'Půjčovna motorek Vysočina Motogo24' },
      ]
    },
    {
      id: 'footer', label: 'Footer (patička)', location: 'Dolní část webu na každé stránce',
      fields: [
        { key: 'web.layout.footer.intro', label: 'Úvodní text', type: 'textarea', default: 'Vítejte u Motogo24, vaší půjčovny motorek v Pelhřimově! Nabízíme pronájem motorek pro místní i turisty. Vyberte si z nabídky sportovních nebo enduro motorek a rezervujte online ve třech krocích.' },
        { key: 'web.layout.footer.help', label: 'Nadpis pomoc', default: 'Potřebujete poradit?' },
        { key: 'web.layout.footer.social', label: 'Nadpis sociální sítě', default: 'Půjčovna motorek na sítích' },
        { key: 'web.layout.footer.hours', label: 'Provozní doba', default: 'PO - NE 00:00 – 24:00 (nonstop)' },
        { key: 'web.layout.footer.copy', label: 'Copyright', default: '© Půjčovna motorek Vysočina Motogo24 - všechna práva vyhrazena' },
      ]
    },
  ]
}
