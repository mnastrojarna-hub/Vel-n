// Texty webu: Postup půjčení + Přistavení
export const PAGE_POSTUP = {
  id: 'postup', label: 'Postup půjčení', icon: '📝', url: '/jak-pujcit/postup',
  description: '8 kroků půjčení motorky krok za krokem + FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 nadpis a úvodní odstavec',
      fields: [
        { key: 'web.postup.h1', label: 'H1 nadpis', default: 'Postup půjčení motorky' },
        { key: 'web.postup.intro', label: 'Úvodní text', type: 'textarea', default: 'V Motogo24 – půjčovna motorek na Vysočině je půjčení jednoduché, rychlé a férové. Bez kauce, s výbavou v ceně a nonstop provozem.' },
      ]
    },
    {
      id: 'steps', label: 'Kroky procesu (8 kroků)', location: 'Sekce „Jak probíhá pronájem krok za krokem" – 8 karet',
      fields: [
        { key: 'web.postup.step.1.title', label: 'Krok 1 nadpis', default: '1. Vyber motorku' },
        { key: 'web.postup.step.1.text', label: 'Krok 1 text', default: 'Prohlédni si naši nabídku cestovních, sportovních, enduro i dětských motorek a vyber si tu pravou.' },
        { key: 'web.postup.step.2.title', label: 'Krok 2 nadpis', default: '2. Počet jezdců' },
        { key: 'web.postup.step.2.text', label: 'Krok 2 text', default: 'Zvol, jestli pojedeš sám, nebo se spolujezdcem. Nabídneme ti vhodné stroje a výbavu.' },
        { key: 'web.postup.step.3.title', label: 'Krok 3 nadpis', default: '3. Rezervace online' },
        { key: 'web.postup.step.3.text', label: 'Krok 3 text', default: 'Jednoduše si zarezervuj motorku podle data. Platbu proveď předem online.' },
        { key: 'web.postup.step.4.title', label: 'Krok 4 nadpis', default: '4. Výbava v ceně' },
        { key: 'web.postup.step.4.text', label: 'Krok 4 text', default: 'Automaticky, jako řidič, dostaneš helmu, bundu, kalhoty a rukavice.' },
        { key: 'web.postup.step.5.title', label: 'Krok 5 nadpis', default: '5. Potvrzení a platba' },
        { key: 'web.postup.step.5.text', label: 'Krok 5 text', default: 'Rezervace je závazná po potvrzení. Platbu provedeš online.' },
        { key: 'web.postup.step.6.title', label: 'Krok 6 nadpis', default: '6. Převzetí motorky' },
        { key: 'web.postup.step.6.text', label: 'Krok 6 text', default: 'Převezmeš motorku osobně v Pelhřimově nebo využiješ přistavení na domluvené místo.' },
        { key: 'web.postup.step.7.title', label: 'Krok 7 nadpis', default: '7. Užij si jízdu' },
        { key: 'web.postup.step.7.text', label: 'Krok 7 text', default: 'Vyraz na cestu – bez kauce, bez stresu, s jasnými podmínkami.' },
        { key: 'web.postup.step.8.title', label: 'Krok 8 nadpis', default: '8. Vrácení motorky' },
        { key: 'web.postup.step.8.text', label: 'Krok 8 text', default: 'Motorku vrátíš kdykoli během posledního dne výpůjčky. Nemusíš tankovat ani mýt.' },
      ]
    },
    {
      id: 'faq', label: 'FAQ (4 otázky)', location: 'Časté dotazy pod kroky',
      fields: [
        { key: 'web.postup.faq.1.q', label: 'Otázka 1', default: 'Je nutná kauce při půjčení?' },
        { key: 'web.postup.faq.1.a', label: 'Odpověď 1', default: 'Ne. Půjčujeme bez kauce – férově a bez zbytečných překážek.' },
        { key: 'web.postup.faq.2.q', label: 'Otázka 2', default: 'Je v ceně půjčovného i výbava?' },
        { key: 'web.postup.faq.2.a', label: 'Odpověď 2', default: 'Ano. Každý řidič dostane helmu, bundu, kalhoty a rukavice zdarma.' },
        { key: 'web.postup.faq.3.q', label: 'Otázka 3', default: 'Kde si mohu motorku převzít?' },
        { key: 'web.postup.faq.3.a', label: 'Odpověď 3', default: 'Vyzvednutí probíhá v Pelhřimově, případně nabízíme přistavení motorky na tebou zvolené místo.' },
        { key: 'web.postup.faq.4.q', label: 'Otázka 4', default: 'Do kdy musím motorku vrátit?' },
        { key: 'web.postup.faq.4.a', label: 'Odpověď 4', default: 'Motorku můžeš vrátit kdykoli během posledního dne výpůjčky – klidně i o půlnoci.' },
      ]
    },
    {
      id: 'cta', label: 'CTA', location: 'Závěrečná výzva k akci',
      fields: [
        { key: 'web.postup.cta.title', label: 'Nadpis', default: 'Připraven na jízdu?' },
        { key: 'web.postup.cta.text', label: 'Text', default: 'Rezervuj si motorku online ještě dnes a užij si svobodu na dvou kolech.' },
      ]
    },
  ]
}

export const PAGE_PRISTAVENI = {
  id: 'pristaveni', label: 'Přistavení', icon: '🚚', url: '/jak-pujcit/pristaveni',
  description: 'Doručení motorky na domluvené místo s ceníkem dle vzdálenosti.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní text',
      fields: [
        { key: 'web.prista.h1', label: 'H1 nadpis', default: 'Přistavení motocyklu – doručení až k tobě' },
        { key: 'web.prista.intro', label: 'Úvodní text', default: 'Chceš vyrazit bez zbytečného přesunu do půjčovny? Zajistíme přistavení motorky na domluvené místo.' },
      ]
    },
    {
      id: 'why', label: 'Proč přistavení (5 boxů)', location: 'Sekce výhod přistavení',
      fields: [
        { key: 'web.prista.why.1', label: 'Box 1', default: 'Pohodlí a čas – motorku přivezeme, kam potřebuješ' },
        { key: 'web.prista.why.2', label: 'Box 2', default: 'Flexibilita – vyzvednutí i vrácení lze řešit mimo provozovnu' },
        { key: 'web.prista.why.3', label: 'Box 3', default: 'Nonstop provoz – přistavení/vrácení v den výpůjčky i večer' },
        { key: 'web.prista.why.4', label: 'Box 4', default: 'Bez kauce – férové a jasné podmínky' },
        { key: 'web.prista.why.5', label: 'Box 5', default: 'Výbava v ceně – pro řidiče' },
      ]
    },
    {
      id: 'pricing', label: 'Ceník přistavení (5 řádků)', location: 'Tabulka s cenami dle vzdálenosti od Pelhřimova',
      fields: [
        { key: 'web.prista.price.1', label: 'Do 10 km', default: '290 Kč – Centrum Pelhřimov, blízké obce' },
        { key: 'web.prista.price.2', label: 'Do 30 km', default: '590 Kč – Humpolec, Kamenice nad Lipou, Pacov' },
        { key: 'web.prista.price.3', label: 'Do 60 km', default: '990 Kč – Jihlava, Třebíč, Tábor' },
        { key: 'web.prista.price.4', label: 'Do 100 km', default: '1 490 Kč – České Budějovice, Kolín, Havlíčkův Brod' },
        { key: 'web.prista.price.5', label: '100+ km', default: 'Individuálně – Praha, Brno, další místa po dohodě' },
      ]
    },
    {
      id: 'cta', label: 'CTA', location: 'Závěrečná výzva',
      fields: [
        { key: 'web.prista.cta.title', label: 'Nadpis', default: 'Přistavení motorky – půjčovna motorek Vysočina' },
        { key: 'web.prista.cta.text', label: 'Text', default: 'Motogo24 nabízí přistavení motocyklu po regionu i mimo něj. Nonstop provoz, bez kauce, výbava v ceně.' },
      ]
    },
  ]
}
