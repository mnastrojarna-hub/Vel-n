// Texty webu: Vyzvednutí + Co v ceně + Dokumenty
export const PAGE_VYZVEDNUTI = {
  id: 'vyzvednuti', label: 'Vyzvednutí', icon: '🔑', url: '/jak-pujcit/vyzvednuti',
  description: 'Jak probíhá vyzvednutí motorky, kde, provozní doba, co si vzít.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a úvodní odstavec',
      fields: [
        { key: 'web.vyzved.h1', label: 'H1', default: 'Vyzvednutí motocyklu – rychle, jednoduše a nonstop' },
        { key: 'web.vyzved.intro', label: 'Úvodní text', type: 'textarea', default: 'V Motogo24 – půjčovna motorek Vysočina je vyzvednutí motorky otázkou pár minut. Půjčujeme bez kauce, s výbavou v ceně a nonstop provozem.' },
      ]
    },
    {
      id: 'where', label: 'Kde probíhá vyzvednutí', location: 'Sekce s adresou, provozní dobou a mapou',
      fields: [
        { key: 'web.vyzved.address', label: 'Adresa', default: 'Mezná 9, 393 01 Pelhřimov (Vysočina)' },
        { key: 'web.vyzved.hours', label: 'Provozní doba', default: 'nonstop' },
        { key: 'web.vyzved.phone', label: 'Telefon', default: '+420 774 256 271' },
        { key: 'web.vyzved.return', label: 'Vrácení text', default: 'Motorku můžeš vrátit kdykoli během posledního dne výpůjčky. Nevyžadujeme vrácení s plnou nádrží ani mytí.' },
      ]
    },
    {
      id: 'steps', label: 'Kroky vyzvednutí (5)', location: '5 karet s ikonami',
      fields: [
        { key: 'web.vyzved.step.1', label: 'Krok 1', default: 'Přijď v domluvený čas – na naši adresu nebo vyčkej na přistavení' },
        { key: 'web.vyzved.step.2', label: 'Krok 2', default: 'Ověříme doklady – OP/pas + řidičský průkaz odpovídající skupiny' },
        { key: 'web.vyzved.step.3', label: 'Krok 3', default: 'Předáme motorku a výbavu – helma, bunda, kalhoty, rukavice' },
        { key: 'web.vyzved.step.4', label: 'Krok 4', default: 'Krátké seznámení se strojem – ovládání, tipy, doporučení k trase' },
        { key: 'web.vyzved.step.5', label: 'Krok 5', default: 'Podepíšeme předávací protokol – a můžeš vyrazit' },
      ]
    },
    {
      id: 'checklist', label: 'Co si vzít s sebou', location: 'Seznam potřebných věcí',
      fields: [
        { key: 'web.vyzved.need.1', label: 'Položka 1', default: 'Občanský průkaz / pas' },
        { key: 'web.vyzved.need.2', label: 'Položka 2', default: 'Řidičský průkaz odpovídající skupiny (A/A2 podle motorky)' },
        { key: 'web.vyzved.need.3', label: 'Položka 3', default: 'Vhodnou obuv (moto boty lze půjčit jako nadstandard)' },
      ]
    },
  ]
}

export const PAGE_CO_V_CENE = {
  id: 'co-v-cene', label: 'Co je v ceně', icon: '💎', url: '/jak-pujcit/co-v-cene',
  description: 'Přehled co je v ceně pronájmu: základní a nadstandardní výbava.',
  sections: [
    {
      id: 'intro', label: 'Úvod stránky', location: 'H1 a intro',
      fields: [
        { key: 'web.cena.h1', label: 'H1', default: 'Co je v ceně pronájmu motorky' },
        { key: 'web.cena.intro', label: 'Intro', default: 'V Motogo24 – půjčovna motorek na Vysočině dostaneš férové podmínky. Bez kauce, s výbavou v ceně a nonstop provozem.' },
      ]
    },
    {
      id: 'basic', label: 'Základní výbava zdarma', location: 'Levý sloupec – seznam výbavy pro řidiče',
      fields: [
        { key: 'web.cena.basic.1', label: 'Položka 1', default: 'Helma – vždy čistá a bezpečná' },
        { key: 'web.cena.basic.2', label: 'Položka 2', default: 'Motorkářská bunda s chrániči' },
        { key: 'web.cena.basic.3', label: 'Položka 3', default: 'Moto kalhoty pro maximální komfort' },
        { key: 'web.cena.basic.4', label: 'Položka 4', default: 'Rukavice ve správné velikosti' },
      ]
    },
    {
      id: 'premium', label: 'Nadstandardní výbava', location: 'Pravý sloupec – příplatky',
      fields: [
        { key: 'web.cena.prem.1', label: 'Položka 1', default: 'Výbava pro spolujezdce' },
        { key: 'web.cena.prem.2', label: 'Položka 2', default: 'Páteřák pro maximální ochranu' },
        { key: 'web.cena.prem.3', label: 'Položka 3', default: 'Chrániče hrudi (pro enduro/cross)' },
        { key: 'web.cena.prem.4', label: 'Položka 4', default: 'Motorkářské boty' },
        { key: 'web.cena.prem.5', label: 'Položka 5', default: 'Bluetooth komunikátor' },
        { key: 'web.cena.prem.6', label: 'Položka 6', default: 'Kufry a zavazadlový systém' },
      ]
    },
    {
      id: 'benefits', label: 'Další výhody (5 boxů)', location: 'Ikonové boxy pod výbavou',
      fields: [
        { key: 'web.cena.ben.1', label: 'Box 1', default: 'Nonstop provoz – vyzvednutí i vrácení kdykoli' },
        { key: 'web.cena.ben.2', label: 'Box 2', default: 'Bez kauce – žádná záloha při půjčení' },
        { key: 'web.cena.ben.3', label: 'Box 3', default: 'Pojištění – součástí pronájmu' },
        { key: 'web.cena.ben.4', label: 'Box 4', default: 'Bezkontaktní předání – na vyžádání' },
        { key: 'web.cena.ben.5', label: 'Box 5', default: 'Jasné podmínky – bez skrytých poplatků' },
      ]
    },
  ]
}

export const PAGE_DOKUMENTY = {
  id: 'dokumenty', label: 'Dokumenty', icon: '📑', url: '/jak-pujcit/dokumenty',
  description: 'Nájemní smlouva, podmínky, platby, užívání a předání/vrácení motorky.',
  sections: [
    {
      id: 'intro', label: 'Úvod', location: 'H1 a úvodní odstavec',
      fields: [
        { key: 'web.docs.h1', label: 'H1', default: 'Nájemní smlouva a kauce – férové podmínky bez zálohy' },
        { key: 'web.docs.intro', label: 'Intro', type: 'textarea', default: 'V Motogo24 klademe důraz na jednoduchost a férovost. Půjčujeme bez kauce, s jasnou nájemní smlouvou, pojištěním v ceně a výbavou pro řidiče.' },
      ]
    },
    {
      id: 'summary', label: 'Shrnutí (6 boxů)', location: '6 ikon s hlavními body',
      fields: [
        { key: 'web.docs.sum.1', label: 'Box 1', default: 'Bez kauce / zálohy – motorku půjčujeme bez blokace peněz' },
        { key: 'web.docs.sum.2', label: 'Box 2', default: 'Pojištění – v ceně (povinné ručení)' },
        { key: 'web.docs.sum.3', label: 'Box 3', default: 'Výbava pro řidiče – v ceně (helma, bunda, kalhoty, rukavice)' },
        { key: 'web.docs.sum.4', label: 'Box 4', default: 'Nonstop provoz – převzetí a vrácení kdykoli' },
        { key: 'web.docs.sum.5', label: 'Box 5', default: 'Jasná pravidla užívání – doma i v zahraničí' },
        { key: 'web.docs.sum.6', label: 'Box 6', default: 'Žádné skryté poplatky – vše ve smlouvě' },
      ]
    },
    {
      id: 'required', label: 'Co potřebujete', location: 'Seznam dokumentů pro uzavření smlouvy',
      fields: [
        { key: 'web.docs.req.1', label: 'Položka 1', default: 'Občanský průkaz / pas' },
        { key: 'web.docs.req.2', label: 'Položka 2', default: 'Řidičský průkaz odpovídající skupiny' },
        { key: 'web.docs.req.3', label: 'Položka 3', default: 'Věk min. 18 let' },
        { key: 'web.docs.req.4', label: 'Položka 4', default: 'Kontakty (telefon, e-mail)' },
      ]
    },
    {
      id: 'payments', label: 'Platby a storno (5 řádků)', location: 'Tabulka plateb a storna',
      fields: [
        { key: 'web.docs.pay.1', label: 'Platba nájemného', default: 'Online předem.' },
        { key: 'web.docs.pay.2', label: 'Storno rezervace', default: 'Lze bezplatně do předem domluveného času.' },
        { key: 'web.docs.pay.3', label: 'Palivo & čištění', default: 'Vrácení bez povinnosti dotankovat a mýt.' },
        { key: 'web.docs.pay.4', label: 'Přistavení / svoz', default: 'Dle ceníku přistavení.' },
        { key: 'web.docs.pay.5', label: 'Pozdní vrácení', default: 'Při zpoždění účtujeme dle domluvy.' },
      ]
    },
  ]
}
