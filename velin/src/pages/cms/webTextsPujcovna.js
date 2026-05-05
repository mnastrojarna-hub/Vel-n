// Texty webu: Půjčovna motorek + Jak si půjčit (overview)
export const PAGE_PUJCOVNA = {
  id: 'pujcovna', label: 'Půjčovna motorek', icon: '🏍️', url: '/pujcovna-motorek',
  description: 'Hlavní prezentační stránka půjčovny s výhodami, kroky a FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'Hlavní nadpis a úvodní odstavec',
      fields: [
        { key: 'web.pujcovna.h1', label: 'H1 nadpis', default: 'Půjčovna motorek Vysočina Motogo24' },
        { key: 'web.pujcovna.intro', label: 'Úvodní text', type: 'textarea', default: 'Naše půjčovna motorek Vysočina v Pelhřimově nabízí pronájem motorek bez zbytečných překážek – bez kauce, s online rezervací a výbavou v ceně. Vyberete si z cestovních, sportovních, enduro i dětských motorek, a vyrazíte kdykoli: máme otevřeno nonstop.' },
      ]
    },
    {
      id: 'benefits', label: 'Výhody (6 boxů)', location: 'Sekce „Proč si půjčit motorku u nás" – 6 ikon',
      fields: [
        { key: 'web.pujcovna.ben.title', label: 'Nadpis sekce', default: 'Proč si půjčit motorku u nás' },
        { key: 'web.pujcovna.ben.1', label: 'Box 1', default: 'Bez kauce – a bez skrytých poplatků' },
        { key: 'web.pujcovna.ben.2', label: 'Box 2', default: 'Online rezervace – na pár kliknutí' },
        { key: 'web.pujcovna.ben.3', label: 'Box 3', default: 'Výbava v ceně – pro řidiče' },
        { key: 'web.pujcovna.ben.4', label: 'Box 4', default: 'Nonstop provoz – vyzvednutí i vrácení kdykoli' },
        { key: 'web.pujcovna.ben.5', label: 'Box 5', default: 'Jsme v tom společně – když se něco přihodí' },
        { key: 'web.pujcovna.ben.6', label: 'Box 6', default: 'Možnost přistavení motorky – na domluvené místo' },
        { key: 'web.pujcovna.ben.bottom', label: 'Text pod výhodami', type: 'textarea', default: 'Hledáte půjčovnu motorek na Vysočině? Motogo24 nabízí férové podmínky, jasný postup a špičkově udržované stroje.' },
      ]
    },
    {
      id: 'steps', label: 'Kroky půjčení (8 kroků)', location: 'Sekce „Jak probíhá půjčení" – 8 karet s ikonami',
      fields: [
        { key: 'web.pujcovna.steps.title', label: 'Nadpis sekce', default: 'Jak probíhá půjčení motorky na Vysočině' },
        { key: 'web.pujcovna.step.1', label: 'Krok 1', default: '1. Vyber motorku – Prohlédni si naši nabídku, vyber si typ, který ti vyhovuje.' },
        { key: 'web.pujcovna.step.2', label: 'Krok 2', default: '2. Zvol jezdce – Jednoduše zaškrtni, kolik vás pojede.' },
        { key: 'web.pujcovna.step.3', label: 'Krok 3', default: '3. Rezervuj online – Uskutečni rezervaci podle data nebo motorky.' },
        { key: 'web.pujcovna.step.4', label: 'Krok 4', default: '4. Vyber výbavu – K zapůjčení automaticky nabízíme helmu, bundu, kalhoty a rukavice.' },
        { key: 'web.pujcovna.step.5', label: 'Krok 5', default: '5. Zaplať – Zaplať online nebo osobně na místě.' },
        { key: 'web.pujcovna.step.6', label: 'Krok 6', default: '6. Převezmi motorku – Přijď si motorku vyzvednout osobně.' },
        { key: 'web.pujcovna.step.7', label: 'Krok 7', default: '7. Užij si jízdu – Vyraz na cestu, objevuj nové zážitky.' },
        { key: 'web.pujcovna.step.8', label: 'Krok 8', default: '8. Vrať motorku včas – Jednoduše vrať ve sjednaný den.' },
      ]
    },
    {
      id: 'cta', label: 'CTA sekce', location: 'Závěrečná výzva k akci',
      fields: [
        { key: 'web.pujcovna.cta.title', label: 'Nadpis', default: 'Rezervuj svou motorku online' },
        { key: 'web.pujcovna.cta.text', label: 'Text', default: 'Naše půjčovna motorek Vysočina je otevřená nonstop. Stačí pár kliků a tvoje jízda začíná.' },
      ]
    },
  ]
}

export const PAGE_JAK_OVERVIEW = {
  id: 'jak-pujcit', label: 'Jak si půjčit', icon: '📋', url: '/jak-pujcit',
  description: 'Rozcestník s odkazy na podstránky: postup, přistavení, vyzvednutí, co v ceně, dokumenty, FAQ.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'Hlavní nadpis a úvodní text',
      fields: [
        { key: 'web.jak_pujcit.h1', label: 'H1 nadpis', default: 'Jak si půjčit motorku' },
        { key: 'web.jak_pujcit.intro', label: 'Úvodní text', type: 'textarea', default: 'V Motogo24 – půjčovna motorek na Vysočině je půjčení jednoduché, rychlé a férové.' },
      ]
    },
    {
      id: 'links', label: 'Navigační karty (8 odkazů)', location: '8 karet odkazujících na podstránky',
      fields: [
        { key: 'web.jak_pujcit.links.0.label', label: 'Odkaz 1', default: 'Postup půjčení motorky' },
        { key: 'web.jak_pujcit.links.1.label', label: 'Odkaz 2', default: 'Převzetí v půjčovně' },
        { key: 'web.jak_pujcit.links.2.label', label: 'Odkaz 3', default: 'Vrácení motocyklu v půjčovně' },
        { key: 'web.jak_pujcit.links.3.label', label: 'Odkaz 4', default: 'Vrácení motorky jinde' },
        { key: 'web.jak_pujcit.links.4.label', label: 'Odkaz 5', default: 'Co je v ceně nájmu' },
        { key: 'web.jak_pujcit.links.5.label', label: 'Odkaz 6', default: 'Přistavení motocyklu' },
        { key: 'web.jak_pujcit.links.6.label', label: 'Odkaz 7', default: 'Dokumenty a návody' },
        { key: 'web.jak_pujcit.links.7.label', label: 'Odkaz 8', default: 'Často kladené dotazy' },
      ]
    },
  ]
}
