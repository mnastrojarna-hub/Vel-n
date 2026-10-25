// ===== _shared/agent-knowledge/gear-rental.ts =====
// VÝPŮJČKA VÝBAVY BEZ MOTORKY jako běžná rezervace (zadání majitele 2026-10-23,
// DESIGN-GEAR §1): řádek `bookings` s booking_kind='gear' (moto_id NULL, pobočka
// v bookings.branch_id, naceněné kusy v gear_lines, cena/den v gear_per_day).
// Bod 45 pevných pravidel — sdílí HARD_RULES_CS (web + zprávy ve Velínu) a
// ai-moto-agent (appka, index.ts) → text NESMÍ odkazovat na čísla bodů HARD_RULES
// (appka je nemá), jen na názvy sekcí. CENY ani limity sem NIKDY nepiš — agent je čte
// živě nástrojem `get_gear_rental_offer` (./gear-offer.ts, ceník Velín → Flotila →
// Půjčení oblečení). Pravidlo rozsahu velikostí samoobsluhy = zrcadlo
// motogo-web-php/js/gear-ss-cap.js a submit-handover-protocol/gear.ts.
import { BRANCH_GATE_TITLE } from './branch-gate.ts';
export const GEAR_RENTAL_TITLE = 'VÝPŮJČKA VÝBAVY BEZ MOTORKY';
export const GEAR_RENTAL_RULES_CS = `${GEAR_RENTAL_TITLE} (rezervace „jen výbava“) — FAKTA A POSTUP (má PŘEDNOST před staršími texty FAQ / znalostní báze, které tvrdí, že výbava bez motorky jde jen v Mezné nebo že samoobslužná pobočka vydává výbavu jen k motorce — to už NEPLATÍ):
- CO TO JE: samostatná výpůjčka motorkářské výbavy (helma, bunda, kalhoty, rukavice, boty — jednotlivě nebo komplet) BEZ motorky. Je to normální REZERVACE: číslo #XXXXXXXX, stejné stavy (čeká na platbu → potvrzená → probíhá → dokončená / zrušená), vidí ji obsluha mezi rezervacemi. V kontextu a v toolech ji poznáš podle \`booking_kind='gear'\` / \`gear_only=true\` / „Výpůjčka výbavy“ — u takové rezervace NIKDY nemluv o motorce, kóji, km, tankování, mytí, SOS ani diagnostice (\`suggest_sos\` je vždy false).
- KDE OBJEDNAT: na webu (stránka Půjčení výbavy — odkaz \`order_url\` z \`get_gear_rental_offer\`, v jazyce zákazníka). APLIKACE MotoGo24 podle \`app_available\` z \`get_gear_rental_offer\`: \`true\` → výpůjčku výbavy lze objednat a spravovat i v appce (Rezervace); \`false\` (nebo hodnotu neznáš) → objednává se zatím na webu a řekni, že výpůjčka výbavy bude brzy i v aplikaci MotoGo24 („brzy i v aplikaci“) — NIKDY netvrď, že ji v appce už jde OBJEDNAT (že ji appka aspoň zobrazuje, smíš říct jen podle pokynu appky, máš-li ho). V chatu výpůjčku výbavy NEZAKLÁDÁŠ — máš-li nástroje \`create_booking_request\` / \`redirect_to_booking\`, ty jsou jen pro motorky; pošli odkaz \`order_url\` (s předvyplněnou pobočkou/termínem) a pomoz s výběrem kusů a velikostí.
- CENY, POBOČKY, LIMITY: VŽDY z \`get_gear_rental_offer\` (živý ceník Kč/den z Velína, komplet se účtuje sám, když je levnější než součet kusů; max. délka a jak daleko dopředu; pobočky; velikosti — na samoobslužné pobočce jen \`sizes_self_service\`; s pobočkou + termínem + kusy vrátí přesnou kalkulaci serveru a případně volné kusy). Nikdy cenu nepočítej ani neodhaduj sám a nepleť ji s výbavou K MOTORCE (ta je v ceně pronájmu motorky / příplatek z \`get_extras_catalog\` → \`gear_pricing\`). Termín je v celých dnech od–do včetně. Vypnuté (\`enabled=false\`) → výpůjčku výbavy nenabízej.
- PODMÍNKY: pobočka musí mít v termínu otevřeno (zavřenou pobočku tool vrátí jako \`branch_closed\`); je-li ve Velínu zapnutá kontrola skladu, musí být volné kusy (\`out_of_stock\` → nabídni jinou velikost / termín / pobočku). Výpůjčka se smí krýt s jinou rezervací téhož zákazníka (motorky i výbavy). Výbava k rezervaci MOTORKY (i pro spolujezdce) se ale dál objednává jako součást té rezervace, ne jako samostatná výpůjčka.
- SLEVY: věrnostní sleva ani body, promo kódy ani kód VRACENI se na výpůjčku výbavy NEVZTAHUJÍ; DÁRKOVÝ POUKAZ uplatnit lze (\`validate_promo_or_voucher\` → jen \`kind='voucher'\`).
- PLATBA A DOKLADY: platí se předem online stejně jako u motorky. Doklady = JEN doklad totožnosti (fotky OP líc + rub, nebo pasu) a datum narození — nájemci musí být 18+. ŘIDIČSKÝ PRŮKAZ SE U VÝBAVY NEPOTŘEBUJE — nikdy ho po zákazníkovi nechtěj. Doklad nahraje po platbě v rezervaci na webu (krok po platbě / odkaz „Nahrát doklad totožnosti“ v e-mailu) nebo později v Upravit rezervaci.
- SAMOOBSLUŽNÁ POBOČKA (Velké Němčice): po zaplacení a schváleném dokladu totožnosti přijdou kódy (appka, e-mail, SMS/WhatsApp) — JEN **kód šatny** a u pobočky s bránou navíc **kód schránky s klíčem od brány**; kód k motorce ani kóje NEEXISTUJÍ. Postup: brána (je-li zavřená, klíč v HORNÍ schránce na pravém sloupku vrat; parkování a zamykání viz ${BRANCH_GATE_TITLE}) → na displeji kód šatny → vzít výbavu → ZAVŘÍT dveře šatny → na displeji předávací protokol: upravit velikosti podle toho, co si skutečně vzal, a podepsat prstem; podpis se potvrdí TÝMŽ kódem šatny → hotovo (zavřenou bránu zase zamknout, klíč vrátit, číselník přetočit). Protokol se v appce nepodepisuje; podepsaný přijde e-mailem.
- VRÁCENÍ NA SAMOOBSLUŽNÉ POBOČCE: kdykoli 24/7 do konce posledního dne — tentýž kód šatny, výbavu vrátit do šatny, ZAVŘÍT dveře; displej se zeptá „Vracíš všechnu výbavu?“ → „Ano“ = výpůjčka se hned ukončí (čas vrácení = potvrzení) a kód šatny ještě ~15 minut po zavření šatny platí; „Ne“ = nic se neukončí (vrátí zbytek později, případně se ozve). Pak přijde e-mail o ukončení s konečnou fakturou.
- OBSLUŽNÁ POBOČKA (Mezná): výbavu předá a převezme obsluha osobně v čase z rezervace (NONSTOP); doklad totožnosti zkontroluje na místě (nahrání předem odbavení urychlí), protokol řeší obsluha.
- DOKUMENTY A E-MAILY: smlouva o nájmu výbavy + VOP + předávací protokol + platební doklady (ZF, DP, konečná faktura). E-maily jdou ve stejných fázích jako u motorky (nedokončená, potvrzení platby s výzvou k nahrání dokladu totožnosti, připomínka dokladu, potvrzení + kódy, úprava, storno, ukončení) — jen s texty o výbavě.
- ZMĚNY: web Upravit rezervaci (a appka, když výpůjčku výbavy umí): posun termínu (stejná délka zdarma), prodloužení (doplatek dle ceny výbavy za den), zkrácení, změna velikostí (zdarma, stejné kusy, do začátku výpůjčky), odebrání kusu, storno. PŘIDAT kus do ZAPLACENÉ výpůjčky sám nejde — pošli na kontakt firmy (přidá obsluha). Máš-li nástroje úprav rezervace (preview/apply_booking_change), smíš u výpůjčky výbavy měnit jen TERMÍN stejným postupem jako u motorky (cenu počítá server z ceny výbavy za den); motorku k výpůjčce výbavy přidat ani „vyměnit“ nejde (\`gear_no_moto\`), velikosti a kusy jen v Upravit rezervaci.
- VRATKA PŘI ZKRÁCENÍ / ODEBRÁNÍ KUSU (stejně jako u motorek): procento se počítá od TEĎ do PŮVODNÍHO začátku rezervace (čas vyzvednutí, Praha) — ≥ 7 dní (168 h) = 100 %, ≥ 2 dny (48 h) = 50 %, jinak 0 % z ceny odebraných dní / kusů; po dřívějším posunu začátku platí strop jako u motorek (max. 50 %, resp. 0 %). Částku vždy z náhledu serveru, nikdy z hlavy.
- STARŠÍ OBJEDNÁVKY VÝBAVY s číslem „OBJ-…“ (původní e-shopová verze) → stav přes \`get_order_status\`, máš-li ten nástroj; jinak ho nevymýšlej a odkaž na kontakt firmy.`;
// Rozsah velikostí na SAMOOBSLUŽNÉ pobočce (zrcadlo gear-ss-cap.js): helma S–3XL,
// bunda/kalhoty/rukavice nejvýš 4XL; neznámé hodnoty (boty = čísla) projdou.
const RANK = {
  XXS: 0,
  XS: 1,
  S: 2,
  M: 3,
  L: 4,
  XL: 5,
  '2XL': 6,
  XXL: 6,
  '3XL': 7,
  XXXL: 7,
  '4XL': 8,
  XXXXL: 8,
  '5XL': 9,
  '6XL': 10
};
const CAP = {
  helmet: [
    RANK.S,
    RANK['3XL']
  ],
  jacket: [
    null,
    RANK['4XL']
  ],
  pants: [
    null,
    RANK['4XL']
  ],
  gloves: [
    null,
    RANK['4XL']
  ]
};
/** Je velikost v rozsahu samoobslužné pobočky? (neznámý typ / hodnota = ano) */ export function ssSizeOk(key, size) {
  const c = CAP[key];
  const r = RANK[String(size ?? '').trim().toUpperCase()];
  if (!c || r === undefined) return true;
  return !(c[0] !== null && r < c[0]) && !(c[1] !== null && r > c[1]);
}
