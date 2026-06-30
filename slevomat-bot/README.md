# MotoGo24 — Slevomat bot

Automatické uplatňování Slevomat poukazů na **partner portálu** (login, bez API).
Bere uplatněné poukazy z naší DB (`vouchers`, `source='slevomat'`, `status='redeemed'`)
a postupně je na portálu Slevomatu **ověří → uplatní → potvrdí**. Běží na stroji,
kde se spouští Velín (potřebuje Node + prohlížeč — **ne** edge funkci).

> ⚠️ Automatizované přihlašování může být v rozporu s podmínkami Slevomatu.
> Používáš na vlastní zodpovědnost. Bot je šetrný (sériově, s prodlevami).

## 0) Předpoklad: DB sloupce

Bot potřebuje v tabulce `vouchers` sledovací sloupce (idempotence — neuplatnit 2×).
SQL je v hlavní konverzaci — spusť ho v Supabase **před prvním během**.

## 1) Instalace

```bash
cd slevomat-bot
npm install            # nainstaluje i Chromium (postinstall)
cp .env.example .env   # vyplň SUPABASE_URL + SERVICE_ROLE key
cp config.example.json config.json
```

`config.json` už má **reálné selektory** partner portálu MotoGo24 (partnerHash
`9d78158c40db418a`, ověřovací formulář, marker přihlášení). Měnit ho budeš jen
když Slevomat upraví portál, nebo když podle screenshotů doladíš `outcomes`
(texty hlášek) a `redeemButtonText`.

## 2) Přihlášení (jednorázově — login má reCAPTCHA)

```bash
npm run login
```

Otevře se prohlížeč na partner portálu (nepřihlášeného Slevomat přesměruje na
login). Přihlas se ručně (zvládne i captchu). Po přesměrování zpět na dashboard
se session uloží do `sessions/storageState.json`. Když vyprší, spustíš znovu.

## 3) Běh

```bash
npm run dry-run   # jen vypíše frontu, nic neuplatní
npm run run       # jednorázově uplatní čekající poukazy
npm run watch     # AUTOMATICKY: hlídá DB a uplatňuje nové (běží stále)
npm run status    # souhrn: čeká / vyřízeno / chyby
```

**Automatický provoz „po uplatnění":** nech běžet `npm run watch` na stroji s
Velínem. Jakmile se ve `vouchers` objeví nový Slevomat poukaz se `status='redeemed'`,
bot ho do `POLL_INTERVAL_SEC` sekund sám odešle na Slevomat. Když není co dělat,
jen levně dotáže DB (prohlížeč nespouští). Alternativa bez stálého běhu: naplánuj
`npm run run` přes cron / Plánovač úloh.

## 4) Spouštění z Velínu (volitelné)

```bash
npm run serve     # lokální trigger na http://127.0.0.1:8787
```

Velín spuštěný **lokálně** může volat `POST /run` a `GET /status`. (Velín z Vercelu
přes HTTPS na localhost kvůli mixed-content nedosáhne — pro to by byl potřeba
samostatný server.)

## Flow uplatnění (dvoukrokový, dle reálného portálu)

1. Zadá kód do `input[name=code]` a klikne **Ověřit** (`input[name=check]`).
2. U platného voucheru klikne **Uplatnit** a v potvrzovacím dialogu **Potvrdit**
   (`.js-confirm-dialog-submit`).
3. Přečte výslednou hlášku a vyhodnotí stav.

## Vyhodnocení výsledku

| stav portálu | DB `slevomat_apply_status` | `slevomat_applied_at` | retry |
|---|---|---|---|
| úspěšně uplatněn | `applied` | nastaví | ne |
| už byl uplatněn | `already_redeemed` | nastaví | ne |
| neplatný / neexistuje | `invalid` | — | ne |
| nezaplacen | `not_paid` | — | ne |
| storno / refund | `cancelled` | — | ne |
| neznámá/přechodná chyba | `failed` | — | ano (do `MAX_ATTEMPTS`) |

Při chybě/neznámé hlášce se uloží screenshot do `screenshots/` — podle něj doladíš
`outcomes`/`redeemButtonText` v `config.json`, pokud se reálné texty liší.

## Ladění selektorů

`npm run record` otevře Playwright codegen na partner portálu — proklikáš ověření
i uplatnění jednoho voucheru a uvidíš přesné selektory/texty.

`sessions/`, `screenshots/`, `.env`, `config.json` jsou v `.gitignore`.
