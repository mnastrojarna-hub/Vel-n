# Podklady pro závěrečnou zprávu majiteli a text PR (2026-11-12)

## SQL balík — hotovo (wf_804742c5-1ae): 65 souborů `supabase/migrations/20261112*.sql`
- a01–a07 platby, b01–b08 jízdy, c01–c04 recenze/zprávy + řádek `feature_flags.app_v2_ui`, t01–t26 texty majitele, u01–u14 QA texty. Funkční (a–c) běží před textovými (t–u).
- Zkouška nasazení na kopii dnešního živého schématu (snapshot e5d5b0f7): 65 souborů 2× bez chyby, se živými texty i na prázdné DB; testy plateb 73/73, recenze 24/24, QA vše OK.
- 3 nezávislé kontroly: 3 závažné nálezy opraveny a znovu ověřeny (CS-1 obnovená rezervace se po obnovení obsluhou znovu rušila; CS-2 cenová pojistka šla obejít přepnutím na „nezaplaceno“; CS-3 pojistka vracela jen část úpravy → smíšený stav), 0 otevřených. Dodatečně: dvojitý mail při odebrání placené výbavy (a04) — oprava běží (agent, 20:05 UTC).
- NEZAŘAZENO (vědomě): barvy ranků d01 (zhoršily by čitelnost ranků 12, 15, 16, 17 ve starém vzhledu / 4.1.3 / level-up; nový vzhled má rampu i bez SQL — soubor připraven v `scratchpad/sqlb/c/`), sql-qa a (RLS zpráv) a g (VOP čl. 5 l + smlouva — bez souhlasu), volitelné soubory recenzí, S3b.
## Co musí majitel vědět (srozumitelně do závěrečné zprávy)
1. **Před mergem** otevřít GitHub → Actions: nesmí běžet „daily-backup“ ani „snapshot-supabase“ (první soubory krátce zamykají tabulky rezervací a jízd; při záloze by zámek čekal a rezervace/kiosk by stály).
2. **Web (ZIP) nahrát zároveň s mergem** — texty stránek a přesměrování blogu `/blog/p` → nový název.
3. **Po mergi** zkontrolovat log „Deploy SQL“ (udělám já, když mi majitel napíše, že mergnul): `[20261112a05] … NEVYTVOŘEN` (duplicitní dobropisy → zrušit ve Velínu a pustit znovu only=20261112a05 force=true), `přepočet jízd … nestihl se celý` (pustit znovu only=20261112b08 force=true), NOTICE u t-souboru e-mailových šablon (které šablony se změnily).
4. **Velín po nasazení:** Dokumenty → „Přeložit chybějící a zastaralé“ (VOP en/es/fr/nl a smlouva de/en/es/fr/nl/pl — staré strojové překlady se mažou, do přeložení se ukazuje závazné české znění); Texty webu → totéž; znovu uložit blogové články; „Uložit banner“; zkontrolovat e-mailové šablony.
5. **Závazné dokumenty:** mění se JEN patička VOP (adresa „Mezná 9, 393 01 Pelhřimov“ = sídlo uvedené ve VOP), verze VOP 14 → 15; český text jinak beze změny. Pravidlo mytí ve VOP/smlouvě NEzměněno (čeká na souhlas).
6. **Cenová pojistka (P4, schváleno 8. 11.) je přísnější a zároveň nerozbíjí appku:** zákazník si sám (mimo platbu) uloží jen úpravu, která nedává víc, než zaplatil (posun termínu zdarma, levnější motorka); víc dní / dražší motorka / přívěs bez platby se neuloží vůbec. Platí i pro nezaplacené potvrzené rezervace založené obsluhou → ty prodlužuje obsluha ve Velínu.
7. **Obnovit a zaplatit** jde jen u rezervace, která nikdy nebyla zaplacená (max. 3×); zaplacenou a vrácenou / zrušenou obsluhou / s vyšším ceníkem obnovuje obsluha ve Velínu. Jen-výbava se v appce obnovit nedá.
8. **Jízdy:** staré jízdy se jednorázově přepočítají (noci a dlouhá stání z „celkového času“ do pauz; km, čas jízdy a max. rychlost se nemění). Appka 4.1.3 nahrává dál.
9. **Hodnocení:** hodnotit jde jen skončenou, nezrušenou jízdu (jinak se tiše ignoruje); „Vyřízeno“ ve Velínu je společné pro všechny adminy; zpráva zákazníka posune vlákno nahoru.
10. Text „telefon 24/7“ v ukrajinštině je věrný překlad češtiny — pokud linka funguje jen Po–Pá 8–17, opravit češtinu ve Velínu a přeložit znovu.
## Známá omezení (neblokují, říct majiteli)
- Záznam jízdy: po SOS výměně motorky BEZ signálu pošle appka body ke staré jízdě (body po výměně se zahodí); převýšení v mírně zvlněném terénu vychází ~82 % (cíl 85 %).
- 3 RPC volané appkou na serveru chybí už v main (appka to snáší).
- `supabase/config.toml`: 6 edge funkcí bez položky verify_jwt (stejné jako main).
## Audit funkcí (wf_62b7e9eb-a99) — 80 nálezů: 63 ponechat, 1 vráceno (klíč stránky záložek ve starém vzhledu), 10 testů (7 oprav skutečných chyb, mj. úklid mezipaměti mazal značku platby a frontu zaplacených změn), 6 otázek pro majitele (app-routes-4 výchozí limity záznamu jízdy; app-core-3 + app-pay-7 předvyplňování i ve starém vzhledu; app-core-12 filtr rezervací čekajících na převod; app-pay-2 appka sama ruší rezervaci po vypršení času; backend-1 odmítnutí částky vyšší o > 1 Kč). Plné znění `scratchpad/funcaudit/decisions.md`.
