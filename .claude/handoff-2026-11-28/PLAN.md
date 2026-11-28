# Pokračování po resetu limitu (3. 12. 2026) — plán

Stav k 28. 11. 2026 ráno, větev `claude/moto-go-mobile-conversion-gqg5qo`. Tato složka je dočasná (předávka) — po dokončení smazat.

## Stav nasazení 28. 11. 2026 ráno
- Majitel sloučil větev (PR #2237 v 08:34, #2238 v 08:47 CET). SQL deploy zelený → naostro: skútry na ŘP B (`20261128f`), SEO úvodní stránka (`20261128g`), nový provozovatel (`20261129a–f`).
- Deploy edge funkcí z #2237 SPADL (GitHub rate limit při stahování Supabase CLI, ne chyba kódu) → 28. 11. spuštěn znovu ručně (workflow_dispatch na main). Ověřit, že doběhl zeleně; kdyby padal opakovaně, zvážit pevnou verzi CLI v `deploy-functions.yml` místo `latest`.
- Majitel nahrál 3 nová PDF e-shopu (28. 11.). Zbývá od něj: Ctrl+F5 Velín, přeložit VOP/smlouvu/GDPR/protokoly + dotčené texty/FAQ, nahrát web podle seznamu (poslán 28. 11.), Search Console „Požádat o indexování“ + „Ověřit opravu“.

## Hotovo a čeká jen na majitele
- **Merge větve do main** (majitel): nasadí schválená SQL `20261128f` (skútry na ŘP B), `20261128g` (SEO úvodní stránka), `20261129a–f` (nový provozovatel MotoGo24 s.r.o.) + edge/Velín změny provozovatele. Po merge: Ctrl+F5 Velín, nahrát 3 PDF e-shopu (Dokumenty → Vlastní dokumenty) a přeložit, přeložit VOP/smlouvu/GDPR/protokoly a texty.
- **Web nahrát** (ručně, Hosting90) — seznam souborů dostal majitel 28. 11. (porovnání s 9255ba70); po nahrání smazat `.cache/pages`. Web je hotový kromě QR plateb (níže).
- Po merge zkontrolovat Actions (deploy-sql, deploy-functions) a issues `sql-deploy-failed`.

## Rozpracováno (priorita v tomto pořadí)

### 1. Appka 5.0.3 — dokončit a předat „k buildu“
- Nový provozovatel v appce: kód hotový (`lib/core/operator_info.dart`, faktury ze `issuer_snapshot`, karta SOS), analyze 141 / 0 chyb; celá Android sada 28. 11. zelená (7589 prošlo, 0 chyb, vč. rozpracované kalkulačky). Zbývá iOS kopie mimo repo.
- Kalkulačka s přistavením (Motorky → Spočítat cenu → krok ④): rozpracováno (`lib/features/catalog/v2/calc/calc_step_handover_v2.dart`, `core/booking_address_carry.dart`, `booking_quote.dart`, `booking_entry.dart`, `booking/v2/booking_carry_v2.dart`, `translations_ext_68_calc_delivery.dart`, test `test/v2/screens/calc_delivery_widget_test.dart`). Zadání: `calc/design.md` (APP sekce) + `calc/delivery_rules.md`. Rozhodnutí: pravidla 1:1 s rezervačním formulářem appky, ne na detailu motorky, při <6 h jen upozornění, přenos do rezervace přes `startBookingFromSelection`.
- Pak: plná sada testů Android + iOS kopie, `diff -rq` = 20, snímky, DESIGN_V22.md 5.0.3 řádek ke kalkulačce, majiteli „k buildu“. Po vydání v obou obchodech zvednout povinnou verzi (starší verze ukazují starého provozovatele na nových fakturách).
- Otázky majiteli k 5.0.3 (nezodpovězeno, výchozí = nechat): Rezervovat i na Domů; „Nová rezervace“ místo CTA v prázdném stavu; fotky e-shopu celé vs ořez; starý vzhled kalendáře. Úvodní animace při každém startu → jen poprvé? (`mg_intro_shown` do keep-listu v `cache_cleanup_service.dart`).

### 2. QR platby + dokončení Fio (majitel 27. 11.)
- Návrh: `fioqr/design.md`, stav: `fioqr/current_state.md`, rozhraní: `fioqr/CONTRACT.md`, SQL návrhy: `fioqr/sql_drafts/` (+ `sql_final/` pokud existuje).
- Rozhodnutí majitele: interval synchronizace 1 min (s lease, tichými prázdnými běhy); platby bez/se špatným VS = jen NÁVRH ve Velínu + potvrzení 1 klikem (žádná automatika); 9 pravidel: doplatek úpravy QR čeká 60 min; nový termín se neblokuje (při obsazení vrátit peníze ručně); nezaplacený poukaz čeká 7 dní, pozdní platba se uzná; slevový kód jak naceněn, poukaz až po připsání; QR u zboží e-shopu později; nepoužitelné platby vrací obsluha ručně; pozdní QR rezervace se potvrdí, je-li motorka volná; 4h lhůta od zvolení QR + e-mail při vypršení; QR bez ohledu na čas převzetí.
- Hotové na větvi (NEZAPOJENÉ, nic je nevolá): `supabase/functions/fio-sync/{run,suggest,dispatch,confirm-*,fio-api,ops-mail,partials,util}.ts`, `process-payment/{bank-change,bank-shop,voucher-order}.ts`, `qr-payment/{handler,request-actions,gear-texts}.ts`, testy `_tests/bank_*`, `fio_sync_flow_test.ts`, `qr_bank_flow_test.ts`, `pp_bank_modules_flow_test.ts`. Velín: `velin/src/pages/accounting/bank/` (NEREGISTROVÁNO ve Finance.jsx).
- Zbývá: dokončit moduly + testy (inertní režim = dnešní chování bez SQL), zapojit do vstupů (`fio-sync/index.ts`, `qr-payment/index.ts`, `process-payment`) — VŽDY tak, aby větev byla v každém commitu bezpečná k nasazení; dokončit a zaregistrovat Velín „Banka“; web W1 poukaz, W2 výbava, W3 doplatek úpravy (stránky `poukazy-objednat.php`, `pujceni-obleceni` js, `upravit-rezervaci` js); SQL `20261130*` dotestovat na rigu → majiteli ke schválení; STATE.

### 3. Drobnosti
- Majiteli: otázky k textům webu (`otazky/texty_webu.md`) a FAQ (`otazky/faq.md`); seznam nesrovnalostí z auditu FAQ (AI asistent: faktura na firmu, zakázané země; velikosti výbavy; kukla; mytí na samoobsluze vs VOP).
- Velín výchozí kopie textů `velin/src/pages/cms/webTexts*.js` + `motogo-web-php/scripts/build_pages_cs.php` zarovnat s novými výchozími texty webu (SEO, provozovatel).
- Text `rez.alert.minTimeDelivery` (končí „: + 6 hodin“) opravit ve Velínu/SQL.
- `datova-schranka` edge: `btoa` na ne-Latin1 XML (API cesta vždy padá na ruční nahrání) — oprava.
- Slevomat workflow padá (26. i 27. 11.) — prověřit.
