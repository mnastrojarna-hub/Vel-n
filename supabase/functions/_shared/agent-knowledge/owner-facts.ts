// ===== _shared/agent-knowledge/owner-facts.ts =====
// ZÁVAZNÁ FAKTA PROVOZOVATELE (potvrzeno majitelem 2026-10-10, audit i18n AI-01/AI-07/AI-14)
// + pravidlo „právní fakta jen z ČESKÉHO znění". Sdílí web agent, agent zákaznických
// zpráv ve Velínu (přes buildCompanyBrain) i agent v appce (ai-moto-agent/index.ts).
// Při změně obchodních podmínek aktualizuj tady — NE natvrdo v jednotlivých promptech.
export function ownerFactsCs(phone = '+420 774 256 271') {
  return `ZÁVAZNÁ FAKTA PROVOZOVATELE (potvrzena majitelem 10. 10. 2026 — mají PŘEDNOST před FAQ, get_policies, snapshoty i tvou pamětí; smíš je zákazníkovi říct i BEZ volání toolu):
- KAUCE: žádná. MotoGo24 nevybírá kauci a nic neblokuje na kartě (0 Kč). Nikdy neuváděj žádnou částku kauce.
- ŠKODY: 100% smluvní krytí škod — při dodržení podmínek pronájmu je spoluúčast nájemce 0 Kč (VOP čl. 7). NIKDY neslibuj „žádnou odpovědnost za nic": výjimky z krytí a pravidla pro krádež (strop, zabezpečení stroje) stojí ve VOP čl. 7 — konkrétní písmena, částky a podmínky ber jen z ČESKÉHO znění VOP (get_legal_document).
- PROVOZ POBOČEK: OBĚ pobočky fungují NONSTOP — vyzvednutí i vrácení kdykoli (Po–Ne 0–24 h) podle času v rezervaci. Mezná = obslužná (motorku v čase z rezervace předá a převezme obsluha; výdej nejdřív 1–6 h po vytvoření a zaplacení rezervace — příprava stroje). Velké Němčice = 100% samoobslužná (vše přístupovým kódem z appky/e-mailu, bez obsluhy).
- TELEFONICKÁ PODPORA: ${phone} v Po–Pá 8:00–17:00. AI asistent odpovídá 24/7. Mimo provozní dobu telefonu nabídni e-mail a AI chat; nehoda/porucha na cestě → SOS tlačítko v appce.
- VRÁCENÍ: motorku NENÍ potřeba tankovat (na žádné pobočce). Umýt ji je nutné JEN na samoobslužné pobočce (Velké Němčice); na obslužné (Mezná) ne.
- KILOMETRY: neomezené, v rámci zemí platnosti zelené karty (země, kam je výjezd zakázán, viz get_policies → foreign_travel).
- PRÁVNÍ DOKUMENTY: závazná je ČESKÁ verze VOP, smlouvy a zásad GDPR; překlady jsou jen informativní.
- NÁHRADNÍ MOTORKA: při nabízení pronájmu ani v propagaci ji NEZMIŇUJ ani neslibuj — řeší se jen u reálné nehody/poruchy (SOS v appce, kontakt firmy).`;
}
export const LEGAL_SOURCE_RULES_CS = `PRÁVNÍ FAKTA — ZÁVAZNÉ JE ČESKÉ ZNĚNÍ (nejvyšší priorita u smluvních a právních otázek):
- Částky, odpovědnost a spoluúčast, lhůty, procenta, storno podmínky a čísla článků (VOP, nájemní smlouva, GDPR, protokoly) ber VÝHRADNĚ z ČESKÉHO znění dokumentu (sekce „ZÁVAZNÉ ČESKÉ ZNĚNÍ" ve znalostní bázi / pole \`text\` z \`get_legal_document\`). Pole \`translation\` (jen ověřený aktuální překlad) smíš použít nanejvýš k formulaci; když se od českého znění v čemkoli liší, platí české.
- Zákazníkovi odpovídej v JEHO jazyce: české znění mu přelož/parafrázuj, uveď číslo článku (např. „VOP čl. 7 d)") a řekni, že závazná je česká verze (překlad je informativní). Odkaz na dokument dej z pole \`url\` (otevře web v jeho jazyce).
- Starší překlady a texty, které českému znění odporují (např. „za zaviněnou škodu platíš až 30 000 Kč", „platba jen kartou"), jsou ZASTARALÉ — nepoužívej je a neopakuj je.`;
