# Analýza: prohození kroků 2 a 3 web rezervačního flow (platba PŘED doklady)

> **Stav dokumentu:** ANALÝZA — NIC SE ZATÍM NEMĚNÍ. Podklad pro rozhodnutí + rozfázování.
> **Větev:** `claude/web-booking-flow-analysis-e8l8av`
> **Datum:** 2026-07-05
> **Rozsah:** web (motogo24.cz) — NE aplikace, NE Velín rezervace, NE e-shop/voucher.
> **Pravidlo:** vše dnes funguje, produkční platby jsou LIVE, nic se nesmí rozbít.

---

## 0. Manažerské shrnutí

Zákazník dnes na webu: **krok 1** (formulář) → **krok 2** (doklady + platba na jedné stránce, doklady nepovinné, PŘED platbou) → děkovací stránka. Chceme: **krok 1** (formulář) → **krok 2** (přehled + volba platby + zaplacení) → **krok 3** (naskenování dokladů) → dokončeno.

**Nejdůležitější zjištění (mění rozsah):**

1. **Většina „nových" mailových šablon už existuje** v `email_templates`: `web_booking_abandoned`, `booking_abandoned_full`, `booking_missing_docs`, `invoice_payment_receipt`, `web_booking_completed`, `booking_qr_payment` (nový 2026-07-05). Nejde o stavbu od nuly, ale o **přepojení, kdy a s jakými přílohami se posílají**.

2. **Přílohy „velkého" potvrzovacího mailu `web_booking_reserved` (ZF + DP + Smlouva + VOP) neřídí kód, ale Velín šablona** (`email_templates.attachments`). Trimování příloh je z velké části **konfigurace ve Velíně**, ne přepis edge funkce — ale generování Smlouvy je navázané na tuto přílohu (viz riziko R1).

3. **Hlavní riziko rozbití = Smlouva a přístupové kódy.** Dnes se generují v okamžiku platby. V novém flow v tu chvíli **ještě nejsou čísla dokladů** (plní se až v kroku 3) → Smlouva by vyšla prázdná a přístupové kódy nelze uvolnit. Tyto dvě věci se MUSÍ přesunout až za doklady.

4. **Velín dnes neumí sledovat nový flow.** Web funnel je natvrdo postavený na pořadí „doklady → platba"; stav „zaplaceno bez dokladů" je dnes vykreslen jako **anomálie/varování**, ne jako legitimní krok. Chybí sloupce pro krok nedokončení, zvolenou metodu (u ne-QR) a čas doplnění dokladů.

5. **Potvrzovací mail se ROZDĚLÍ na dva momenty** (upřesněno zadavatelem 2026-07-05):
   - **po platbě (krok 2):** `invoice_payment_receipt` s přílohami **ZF + DP** (metoda platby),
   - **po dokladech (krok 3):** `web_booking_reserved` **BEZ ZF/DP — jen Smlouva + VOP** (+ door codes), vždy s vyplněnými čísly dokladů.
   `web_booking_completed` zůstává beze změny pro *dokončení pronájmu* (KF, po vrácení motorky) — v novém flow se ho netýkáme.

---

## 1. SOUČASNÝ flow — přesně jak funguje

Zdroj: `motogo-web-php/js/pages-rezervace*.js`, `pages/rezervace.php`, `pages/potvrzeni.php`, edge funkce `process-payment`, `webhook-receiver`, `qr-payment`, `send-booking-email`, `generate-invoice`, cron `send_abandoned_booking_emails()`.

### 1.1 Kroky (dnes 2 fáze + děkovací stránka)

```
_rezInit  (rezervace.php → MG._rezInit)
  └─ resume? → get_web_booking_resume → rovnou _rezShowStep2

FÁZE A "form" (MG._rez._step="form"):
  1 Motorka · 2 Termín · 3 Kontakt+DOB+promo · 4 Místo/čas · 5 Výbava · 6 Souhlasy
  └─ MG._submitReservation():
        create_web_booking            → booking status=pending, payment_status=unpaid
        set_web_booking_device(created)
        set_booking_language, set_booking_form_seconds
        → MG._rezShowStep2()

FÁZE B "step2" (MG._rez._step="step2")  ← DOKLADY + PLATBA DOHROMADY:
  · QR karta pro dokončení na mobilu (jen desktop): origin+"/rezervace?resume="+bookingId
  · sekce 1 doklad: typ OP/pas, číslo dokladu, číslo ŘP, skupina ŘP, platnost ŘP, checkbox
  · sekce 2 foto dokladů (NEPOVINNÉ; na mobilu za opt-in) → scan-document + save-verification-document
  · sekce 3 heslo
  · sekce 4 e-shop upsell (volitelné)
  · faktura (rozpis) + volba metody (online / QR)
  └─ MG._rezSubmitPayment():
        _rezPersistDocs (set_web_booking_password, set_web_booking_docs)
        QR   → qr-payment (edge) → _rezRenderQrScreen (konec; tlačítko „Hotovo" = odkaz na /)
        online → set_web_booking_device(completed) → process-payment (edge)
                 → redirect na Stripe checkout_url (URL přepsána na ?resume=<id>, smazán mg_rez_form)

PO Stripe → /potvrzeni?session_id=... (pages-potvrzeni.js poll get_web_booking_confirmation → paid → úspěch)
Desktop paralelně: _rezSubscribeMobileMirror (realtime bookings UPDATE) → paid → /potvrzeni?booking_id=<id>
```

**Důležité:** dedikovaná skenovací obrazovka `_rezShowMindeeStep` (pages-rezervace-scan.js) je **v aktivním flow mrtvý kód** — je definovaná, ale nikde volaná. Doklady se dnes skenují inline v step2 **před** platbou; jsou **nepovinné** (platba vyžaduje jen *čísla* dokladu/ŘP + potvrzení + heslo, ne fotky).

**Po platbě se dnes NEpřechází na skenování.** Jde se na `/potvrzeni`, kde je odkaz na `/upravit-rezervaci?id=<id>` pro pozdější doplnění dokladů.

### 1.2 Kdy vzniká který doklad a mail (SOUČASNÝ stav)

| Okamžik | Doklad | Mail | Přílohy mailu |
|---|---|---|---|
| Klik „Zaplatit" (redirect na Stripe) | **ZF** (proforma), `send_email:false` | — | — |
| Volba QR / převod | **ZF** (advance, s VS + bankou, splatnost 4 h) | `booking_qr_payment` + ops mail na info@ | ZF |
| Web pending+unpaid **15 min** od `created_at` (cron `*/2 min`) | — | `web_booking_abandoned` | ZF |
| Po Stripe platbě (webhook `confirm_payment`) | **DP** (payment_receipt) — generuje se uvnitř mailu | `web_booking_reserved` | **ZF + DP + Smlouva + VOP** (dle `email_templates.attachments`) + door_codes blok |
| Zaplaceno + chybí doklady, **5 min** od `confirmed_at` | — | `booking_missing_docs` | — |
| Dokončení pronájmu (active→completed, DB trigger) | **KF** (final) | `web_booking_completed` | KF |
| Doplatek při úpravě (extension) | rozdílový **DP** (source=edit) | `web_booking_modified` (posílá DB trigger) | rozdílový DP / dobropis + Smlouva + VOP |

Klíčové pravidlo kódu: **ZF vždy PŘED platbou, DP/KF vždy PO platbě; webhook doklady negeneruje sám — deleguje na `send-booking-email` řízené Velín šablonou `email_templates.attachments`.**

### 1.3 Časování a měření (SOUČASNÝ stav)

| Metrika / práh | Zdroj |
|---|---|
| `form_started_at` | sessionStorage `mg_rez_started_at`, uloženo přes `set_booking_form_seconds` |
| `form_fill_seconds` | start → `create_web_booking` (vyplnění formuláře) |
| `payment_fill_seconds` | start → `payment_status='paid'` (celý proces vč. dokladů) — přežije Stripe redirect (start je v DB) |
| `created_device` / `completed_device` | zařízení při vytvoření / při platbě (cross-device „PC → Mobil") |
| Abandoned mail | 15 min od `created_at`, cron každé 2 min, dedup `abandoned_email_sent_at` |
| Missing-docs mail | 5 min od `confirmed_at`, dedup `docs_reminder_sent_at`, přeskakuje delivery/obslužnou pobočku/dětskou moto |
| Auto-cancel nezaplacené | web **4 h** (`auto_cancel_expired_pending`, bez storno mailu), app 10 min |

---

## 2. CÍLOVÝ flow dle zadání

```
KROK 1  (beze změny): formulář → create_web_booking (pending/unpaid)

KROK 2  PŘEHLED + PLATBA (nově BEZ dokladů):
  · rozpis: výbava · motorka po dnech · přistavení · vyzvednutí · sleva · celkem
  · volba platební metody (online Stripe / QR-převod)
  · QR pro dokončení na mobilu (existující mechanismus)
  · zaplacení
      online → Stripe → po platbě „Hotovo"/redirect z brány
      QR     → QR obrazovka → „Hotovo"
  → PO ZAPLACENÍ (Stripe) NEBO po kliknutí „Hotovo" (QR) pokračuje na:

KROK 3  DOKLADY (nově samostatný krok PO platbě):
  · čísla dokladu/ŘP + skupina + platnost + naskenování OP/ŘP/pas (scan-document, save-verification-document)
  · QR pro dokončení na mobilu (existující mechanismus)
  → po vyplnění dokladů (a je-li zaplaceno) = rezervace KOMPLETNÍ
```

### 2.1 Cílová tabulka mailů/dokladů/timingu (NÁVRH — k odsouhlasení)

> Prahy „po X min" jsou převzaté ze současného stavu (15 min / 5 min); u kroku 3 je nový práh na doplnění dokladů — viz Otázka Q4.

| # | Okamžik | Podmínka | Doklad | Mail | Pozn. |
|---|---|---|---|---|---|
| 1 | Vstup na krok 2 (přehled) | — | — | — | jen zobrazení rozpisu |
| 2 | Zaplaceno online (Stripe) | payment=paid, kanál=stripe | **ZF** (už při redirectu) + **DP** | `invoice_payment_receipt` (+ DP, metoda=stripe) | **BEZ Smlouvy, BEZ VOP, BEZ door codes** — ještě nejsou doklady |
| 3 | Volba QR/převod na kroku 2 | kanál=qr | **ZF v2** (advance, VS+banka, 4 h) | `booking_qr_payment` (QR) + ops mail | jako dnes |
| 4 | Nedokončeno na kroku 2 (nezaplaceno) — stripe | pending/unpaid, 15 min | — | `web_booking_abandoned` | jako dnes |
| 4b | Volba QR/převod na kroku 2 | pay_channel=qr | ZF v2 (advance, VS) | `booking_qr_payment` **HNED při volbě** (jako dnes) | Q3 vyřešeno: chodí okamžitě, abandoned potlačen |
| 5 | Přechod na krok 3 (doklady) | po platbě | — | — | jen navigace |
| 6 | Opuštěno na kroku 3 (zaplaceno, chybí doklady) | paid, bez dokladů, **~30–60 min** | — | `booking_missing_docs` (jedna šablona, všechny kanály) | Q2 vyřešeno: prodloužit práh z 5 min |
| 7 | Doklady vyplněny + zaplaceno | paid + docs OK | **Smlouva + VOP** (BEZ ZF/DP) | **`web_booking_reserved`** (potvrzení rezervace) + **door codes** | upřesněno: jen Smlouva+VOP, vždy s čísly dokladů |
| 8 | Dokončení pronájmu (vrácení motorky) | active→completed | **KF** | `web_booking_completed` | beze změny, mimo tento flow |

---

## 3. Co se MŮŽE rozbít (rizika) + mitigace — KRITICKÁ SEKCE

### R1 — Smlouva generovaná s prázdnými čísly dokladů  🔴 vysoké
Dnes `web_booking_reserved` (po platbě) přikládá **Smlouvu**, kterou `generate-document` staví z `profiles.id_number/license_number/…`. V novém flow jsou tato pole při platbě prázdná (plní se až v kroku 3) → **Smlouva by vyšla bez čísel dokladů**.
**Mitigace:** Smlouvu (a VOP) NEgenerovat/NEpřikládat v okamžiku platby. Přesunout je až do mailu po doplnění dokladů (bod 7). Prakticky: v Velín šabloně mailu bodu 2 vyřadit přílohy `rental_contract` + `vop`, ponechat jen ZF + DP; přílohy Smlouva+VOP zapnout v šabloně bodu 7.

### R2 — Přístupové kódy (door codes) uvolněné bez dokladů  🔴 vysoké
Trigger `auto_generate_door_codes` po přechodu na paid vygeneruje kódy, ale **uvolní je jen když jsou nahrané doklady** (jinak `withheld_reason='Chybí doklady'`). V novém flow při platbě doklady nejsou → kódy budou zadržené a mail bodu 2 by (pokud by měl door_codes blok) vykreslil výzvu „nahrajte doklady".
**Mitigace:** V mailu bodu 2 **nemít door_codes blok**. Kódy se uvolní automaticky po naskenování dokladů (trigger `release_withheld_door_codes_on_doc_upload` už existuje) a dorazí buď v mailu bodu 7, nebo samostatným `web_door_codes`. Tuto část lze nechat na existující mechanismus — jen ověřit, že se pošle právě jednou (dedup přes `message_log`).

### R3 — Missing-docs připomínka se stane „normálním" stavem  🟠 střední
Dnes `booking_missing_docs` (5 min od `confirmed_at`) = anomálie (zaplaceno, ale zapomněl doklady). V novém flow **je „zaplaceno bez dokladů" očekávaný mezistav** hned po platbě → cron by odpálil připomínku každému během vyplňování kroku 3.
**Mitigace:** Buď (a) prodloužit práh (např. 30–60 min od `confirmed_at`), nebo (b) posílat připomínku jen když zákazník krok 3 reálně opustil (žádná aktivita), nebo (c) navázat na nový sloupec `docs_started_at`. Nutné rozhodnout (Q4). Také přehodnotit existující výjimky (delivery / obslužná pobočka / dětská moto) — v novém flow je krok 3 pro všechny.

### R4 — `web_booking_reserved` je dnes „potvrzení rezervace"  🟠 střední
Zákazník dnes po platbě dostane jeden mail „rezervace potvrzena" se vším. Když ho rozdělíme (bod 2 = jen platba, bod 7 = kompletní), musí být texty šablon přepsané tak, aby bod 2 nesliboval „vše hotové" a bod 7 dával door codes + smlouvu. Riziko: zákazník dostane 2 maily místo 1 → nutná koordinace textů (copywriterka).
**Mitigace (upřesněno 2026-07-05):** dva maily s jasně oddělenou rolí — **po platbě `invoice_payment_receipt`** (ZF+DP, „zaplaceno"), **po dokladech `web_booking_reserved`** (jen Smlouva+VOP+door codes, „rezervace potvrzena"). Texty obou šablon přepsat tak, aby platební mail nesliboval „vše hotové" a potvrzovací mail dával kódy a smlouvu. Koordinace s copywriterkou.

### R5 — Děkovací stránka `/potvrzeni` je dnes terminál  🟠 střední
Po Stripe redirectu se jde na `/potvrzeni`, což je konec. V novém flow musí `/potvrzeni` (nebo jiný návrat z brány) **přesměrovat na krok 3 (doklady)**.
**Mitigace:** Po `paid` v `pages-potvrzeni.js` místo „úspěch + odkaz na upravit-rezervaci" přesměrovat na `/rezervace?resume=<id>&step=docs` (nový parametr/stav kroku 3). Totéž pro desktop **realtime mirror** (`_rezSubscribeMobileMirror`), který dnes na paid posílá na `/potvrzeni` — musí posílat na krok 3.

### R6 — QR flow nemá „paid" v okamžiku dokladů  🟠 střední
QR/převod se potvrzuje **ručně ve Velíně** (`confirm_payment`, bank_transfer) až po připsání na účet. Zadání: po „Hotovo" u QR zákazník rovnou vyplní doklady, ale kompletní mail (bod 7) přijde „až pokud je platba" i doklady. To znamená **dvoupodmínkový gate** (paid AND docs) — spouštěč musí reagovat na OBOJÍ (a) doplnění dokladů, (b) pozdější ruční potvrzení platby.
**Mitigace:** Kompletní mail (bod 7) spouštět z místa, které vidí obě podmínky — např. trigger na `bookings` (po `payment_status→paid`) i trigger na nahrání dokladů, oba s guardem „paid AND docs OK AND ještě neodesláno". Existující `release_withheld_door_codes_for_user` už podobný dvoucestný pattern má.

### R7 — Měření času `payment_fill_seconds` změní význam  🟡 nízké
Dnes = start → paid (vč. dokladů, protože doklady byly před platbou). Nově doklady jsou PO platbě → `payment_fill_seconds` bude kratší (jen do platby), a chybí metrika „čas doplnění dokladů".
**Mitigace:** Ponechat `payment_fill_seconds` (start→paid) a přidat nový `docs_fill_seconds` / `docs_completed_at`.

### R8 — Vlastní pending draft / „Zpět" / resume  🟡 nízké
`create_web_booking` + `p_existing_booking_id` a resume flow počítají s tím, že krok 2 = doklady+platba. Po reorganizaci musí resume trefit správný krok (2 platba vs 3 doklady) podle `payment_status`.
**Mitigace:** `get_web_booking_resume` už vrací `payment_status` kontext; frontend rozhodne: unpaid → krok 2, paid+bez dokladů → krok 3.

### R9 — Ostatní kanály beze změny  🟢 kontrola
App, Velín rezervace, e-shop, voucher, AI agent (`ai-public-agent` volá `create_web_booking` + resume) — **nesmí se dotknout**. AI agent dnes posílá zákazníka na `/rezervace?resume=<id>` (krok 2 doklady+platba). Po změně se dostane na krok 2 platba — funkčně OK, jen ověřit, že projde i na krok 3.

---

## 4. Velín — co dnes chybí a co přidat

Dnešní web funnel (`WebRezervacniFunnel.jsx`) i detail rezervace jsou postavené na pořadí **doklady → platba**. Pro nový flow je potřeba:

### 4.1 Chybí sloupce (evidence)
- **Krok/fáze nedokončení** — dnes NEEXISTUJE žádný sloupec (`checkout_step` / `abandoned_at_step`). Vše se odvozuje z `payment_status` + `checkout_started_at`. Nový flow potřebuje explicitně rozlišit: nedokončil krok 2 (platba) vs nedokončil krok 3 (doklady).
- **Zvolená platební metoda před zaplacením** — dnes jen `pay_channel='qr'`. Pro ostatní (karta/Apple/Google Pay) Velín volbu nezná. Přidat obecné pole (např. `chosen_payment_method`).
- **Čas doplnění dokladů** — `docs_started_at` / `docs_completed_at` / `docs_fill_seconds`. Dnes jen `form_fill_seconds` + `payment_fill_seconds`.

### 4.2 Web funnel (`WebRezervacniFunnel.jsx`)
- Překreslit `STAGE_ORDER` / koše: dnešní `step2_docs_done` / `step2_no_docs` (doklady před platbou) nahradit logikou nového pořadí: `krok2_nezaplaceno` → `zaplaceno_bez_dokladu` (nově legitimní krok, ne anomálie) → `dokoncено`.
- Stav „zaplaceno bez dokladů" dnes vykreslen jako **varování** (`paidWithoutDocs`) — v novém flow je to normální mezikrok.
- `docsDone` se dnes počítá na úrovni **zákazníka**, ne rezervace (nespolehlivé pro per-rezervační krok) — přejít na per-booking příznak.

### 4.3 Detail rezervace (`BookingSummary.jsx`, `BookingDetail.jsx`, `DetailTabSections.jsx`, `BookingTimeline.jsx`)
- Zobrazit zvolenou metodu i u nezaplacených (nejen QR badge).
- Doplnit „doba doplnění dokladů" vedle „doba do zaplacení".
- `BookingTimeline` dnes začíná až „Vytvořeno → Rezervováno" — zvážit přidání kroků platba/doklady.

---

## 5. Návrh rozfázování implementace (až po odsouhlasení)

> Pořadí je voleno tak, aby se v každé fázi dalo ověřit, že nic není rozbité, a aby platby zůstaly funkční po celou dobu.

- **Fáze 0 — jen dokumentace (TENTO KROK).** Analýza + odsouhlasení otázek Q1–Q5. Nic v kódu.
- **Fáze 1 — evidence ve Velíně (bez změny flow).** Přidat sloupce (`docs_completed_at`, `chosen_payment_method`, příp. `checkout_step`), aktualizovat STATE_*.md. Zatím se jen zapisují, funnel se ještě nemění. Nízké riziko.
- **Fáze 2 — rozdělení potvrzovacího mailu.** Šablona bodu 2 (po platbě) = jen ZF+DP (`invoice_payment_receipt`); Smlouva+VOP+door codes přesunout do mailu bodu 7. Ověřit na testovací rezervaci, že Smlouva má čísla dokladů a door codes dorazí právě jednou. Zatím BEZ přehození pořadí UI — mail bodu 7 se pošle po dodatečném nahrání dokladů přes `/upravit-rezervaci` (což už dnes funguje).
- **Fáze 3 — frontend reorder.** Rozdělit step2 na krok 2 (přehled+platba) a krok 3 (doklady). Přesměrovat `/potvrzeni` + mirror na krok 3. Resume trefí krok podle `payment_status`.
- **Fáze 4 — timing/cron úpravy.** Práh missing_docs, nový práh na doklady, QR dvoupodmínkový gate, `docs_fill_seconds`.
- **Fáze 5 — Velín funnel překreslení.** Nové koše, metriky, timeline.

---

## 6. Otevřené otázky (BLOKUJÍCÍ — nutno rozhodnout před realizací)

- **Q1 — VYŘEŠENO (2026-07-05):** „kompletní" mail po dokladech = `web_booking_reserved`, **bez ZF/DP, jen Smlouva + VOP** (+ door codes), vždy s vyplněnými čísly. `web_booking_completed` zůstává pro konec pronájmu (mimo tento flow).
- **Q5 — POTVRZENO zadavatelem (2026-07-05):** v okamžiku platby (krok 2) NEjde Smlouva, VOP ani door codes; jde jen `invoice_payment_receipt` se ZF+DP. Smlouva+VOP+door codes až po dokladech (krok 3).
- **Q2 — VYŘEŠENO (2026-07-05):** po platbě opuštěné doklady → **jedna šablona `booking_missing_docs` pro všechny kanály** (Stripe i QR), **práh prodloužit z 5 min na ~30–60 min** od `confirmed_at`, aby připomínka nechodila každému během vyplňování kroku 3. `booking_abandoned_full` se v tomto flow nepoužije.
- **Q3 — VYŘEŠENO (2026-07-05):** QR mail (`booking_qr_payment` + ZF s VS) chodí **HNED při volbě QR** (zachovat současné chování z 2026-07-05, abandoned potlačen). „ZF verze 2" = tatáž advance ZF s VS, ne nový typ dokladu.
- **Q4 — VYŘEŠENO (2026-07-05):** doklady v kroku 3 jsou **povinné** pro uvolnění door codes a mail `web_booking_reserved`, ale se **stávajícími výjimkami**: delivery, obslužná pobočka (Mezná) a dětská motorka (`license_required='N'`) doklady nevyžadují (ověří obsluha osobně) — stejné výjimky jako dnešní `booking_missing_docs` / `check_booking_docs_status`.

---

## 7. Reference (soubory/objekty)

- Frontend: `js/pages-rezervace.js` (`_rezInit`, resume), `js/pages-rezervace-steps.js` (`_submitReservation`, `_rezShowStep2`), `js/pages-rezervace-scan.js` (`_rezSubmitPayment`, `_rezStartQrPayment`, `_rezSubscribeMobileMirror`, mrtvý `_rezShowMindeeStep`), `js/pages-potvrzeni.js`, `pages/rezervace.php`, `pages/potvrzeni.php`.
- Edge: `process-payment/payment-flows.ts` (`handleWebBookingCheckout`), `webhook-receiver/payment-confirmers.ts` (`confirmBookingPayment`), `qr-payment/index.ts`, `send-booking-email/index.ts` (`resolveSlug`, `autoGenerateAttachments`), `generate-invoice/index.ts`.
- SQL: `create_web_booking`, `confirm_payment`, `set_booking_qr_payment`, `get_web_booking_resume`, `get_web_booking_confirmation`, `set_web_booking_docs`, `set_web_booking_device`, `set_booking_form_seconds`, cron `send_abandoned_booking_emails()`, `auto_cancel_expired_pending()`, `check_booking_docs_status()`, trigger `auto_generate_door_codes`, `release_withheld_door_codes*`, `generate_final_invoice_on_complete`.
- Velín: `pages/analyza/WebRezervacniFunnel.jsx`, `pages/booking/BookingSummary.jsx`, `pages/BookingDetail.jsx`, `pages/booking/DetailTabSections.jsx`, `pages/booking/BookingTimeline.jsx`, `pages/booking/bookingConstants.js`.
- Šablony: `email_templates` slugy `web_booking_reserved`, `web_booking_abandoned`, `booking_abandoned_full`, `booking_missing_docs`, `invoice_payment_receipt`, `web_booking_completed`, `booking_qr_payment`.
