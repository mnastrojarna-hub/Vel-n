// ===== _shared/agent-knowledge/customer-language.ts =====
// Jazyk ZÁKAZNÍKA = jazyk, kterým PÍŠE (audit i18n 2026-10-10, AI-06/AI-11). UI jazyk webu
// (html lang) / appky je jen záložní nápověda: Němec na motogo24.cz má hint 'cs', Čech na
// anglické stránce hint 'en'. Podle výsledku se řídí odkazy, jazyk rezervace (smlouva, VOP,
// e-maily), FAQ ve znalostní bázi a záložní hlášky. Jazyk SAMOTNÉ odpovědi určuje model
// (pravidlo v promptu) — tahle levná heuristika (písmo + diakritika + běžná slova) slouží
// jen serveru; při nejistotě vrací null → použije se hint.
import { normLang } from './site-url.ts';
/** Názvy jazyků pro prompt (česky) a nativně. */ export const LANG_NAME_CS = {
  cs: 'čeština',
  en: 'angličtina',
  de: 'němčina',
  es: 'španělština',
  fr: 'francouzština',
  nl: 'nizozemština',
  pl: 'polština',
  uk: 'ukrajinština'
};
const W = (s)=>new Set(s.split(' '));
const WORDS = {
  cs: W('je jsem jsi jak co máte mate chci chtěl chtela chtěla prosím prosim děkuji dekuji díky diky dobrý dobry den můžu muzu motorku motorka půjčit pujcit půjčení kolik kde kdy bych by se si že ze není neni ahoj zítra zitra termín termin rezervaci cena stojí stoji víkend vikend potřebuju potrebuju taky také nebo jestli řidičák ridicak mám mam to'),
  en: W('the and is are you what how can for with rent bike hello hi please thanks thank do does have my want would like price book booking motorcycle when where much available tomorrow need i\'m it\'s there this that to of your any'),
  de: W('und ich nicht ist der die das mit für fur ein eine einen haben bitte wie motorrad hallo danke kann möchte mochte gibt was wo wann mieten preis buchen morgen wochenende sie du auf zu habe wir viel kostet noch auch es'),
  es: W('el la los las que para con una hola gracias quiero puedo cuánto cuanto precio reservar alquilar dónde donde cuándo cuando mañana manana fin semana por favor tienen hay mi un es está esta necesito moto motos de del'),
  fr: W('je vous est les des une pour avec bonjour merci louer prix réserver reserver où quand demain combien pouvez voudrais et le du au il mon ma suis c\'est est-ce qu\'il moto pas la un de'),
  nl: W('het een ik niet voor met wat hoe kan graag bedankt dank huren prijs boeken waar wanneer morgen hallo van mijn jullie zijn hebben heb wil hoeveel kost dit deze motor ook nog is de'),
  pl: W('jest nie się sie czy jak co chcę chce dzień dzien dobry dziękuję dziekuje motocykl wypożyczyć wypozyczyc ile kosztuje gdzie kiedy jutro proszę prosze mam mogę moge w z to jaki jaka można mozna')
};
// Silné znaky (diakritika typická jen pro daný jazyk z našich osmi)
const STRONG = [
  [
    'cs',
    /[ěřůťď]/g
  ],
  [
    'cs',
    /[šžč]/g
  ],
  [
    'pl',
    /[ąęłśźżń]/g
  ],
  [
    'de',
    /[äöüß]/g
  ],
  [
    'es',
    /[ñ¿¡]/g
  ],
  [
    'fr',
    /[çœàâêîôûè]/g
  ]
];
/** Odhad jazyka jednoho textu; null = nejisté (krátké „ok", emoji, číslo, jméno…). */ export function detectTextLanguage(text, hint) {
  const t = String(text ?? '').toLowerCase().slice(0, 2000);
  if (!t.trim()) return null;
  // Cyrilice: ukrajinská písmena → uk; ruská specifika bez ukrajinských → nejisté (ruštinu
  // nepodporujeme — jazyk dokumentů pak určí hint); jinak cyrilice = uk.
  const cyr = (t.match(/[а-яёіїєґ]/g) || []).length;
  if (cyr >= 3) {
    if (/[іїєґ]/.test(t)) return 'uk';
    if (/[ыэъё]/.test(t)) return null;
    return 'uk';
  }
  const score = {
    cs: 0,
    en: 0,
    de: 0,
    es: 0,
    fr: 0,
    nl: 0,
    pl: 0
  };
  for (const [lang, re] of STRONG)score[lang] += 3 * Math.min(2, (t.match(re) || []).length);
  for (const w of t.split(/[^\p{L}'-]+/u)){
    if (!w) continue;
    for (const lang of Object.keys(WORDS))if (WORDS[lang].has(w)) score[lang] += 1;
  }
  const ranked = Object.entries(score).sort((a, b)=>b[1] - a[1]);
  const [best, second] = ranked;
  if (!best || best[1] < 1) return null;
  if (best[1] === second[1]) {
    const h = hint ? normLang(hint) : null;
    return h && score[h] === best[1] ? h : null;
  }
  return best[0];
}
/**
 * Jazyk zákazníka pro tento request: poslední (až 3) zprávy zákazníka od nejnovější;
 * první rozpoznaný jazyk vyhrává, jinak hint (UI jazyk webu / appky).
 */ export function customerLanguage(messages, hint) {
  const h = normLang(hint);
  const userMsgs = (messages || []).filter((m)=>m?.role === 'user' && typeof m.content === 'string');
  for (const m of userMsgs.slice(-3).reverse()){
    const d = detectTextLanguage(m.content, h);
    if (d) return d;
  }
  return h;
}
/** Pravidlo jazyka odpovědi pro prompt (app agent; web agent má vlastní blok). */ export function replyLanguageRule(lang, uiLang, uiLabel = 'aplikace') {
  const L = normLang(lang);
  const U = normLang(uiLang, L);
  return `## JAZYK ODPOVĚDI — NEJVYŠŠÍ PRIORITA
- Odpovídej VÝHRADNĚ v jazyce POSLEDNÍ zprávy zákazníka (prompt je česky jen kvůli interní konfiguraci — na jazyk odpovědi nemá vliv). Celou odpověď piš v jednom jazyce, nikdy dvojjazyčně.
- Jazyk zákazníka podle jeho dosavadních zpráv je ${LANG_NAME_CS[L]} (${L}); jazyk ${uiLabel} je ${LANG_NAME_CS[U]} (${U}). Když z poslední zprávy jazyk nejde poznat („ok", „?", číslo, emoji, jméno), odpovídej ${LANG_NAME_CS[L]} — NE česky, pokud zákazník česky nepíše.
- Ukrajinsky piš čistou cyrilicí (žádná latinská slova uprostřed), odpověz na VŠECHNY části dotazu.
- Výsledky nástrojů a pravidla jsou česky — zákazníkovi je vždy přelož do jeho jazyka.`;
}
