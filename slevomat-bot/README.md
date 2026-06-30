# MotoGo24 — Slevomat bot

Automatické uplatňování Slevomat poukazů na **partner portálu** (login, bez API).
Bere uplatněné poukazy z naší DB (`vouchers`, `source='slevomat'`, `status='redeemed'`)
a postupně je „odklikává" na portálu Slevomatu přes Playwright. Běží na stroji,
kde se spouští Velín (potřebuje Node + prohlížeč — **ne** edge funkci).

> ⚠️ Automatizované přihlašování může být v rozporu s podmínkami Slevomatu.
> Používáš na vlastní zodpovědnost. Bot je šetrný (sériově, s prodlevami).

## 0) Předpoklad: DB sloupce

Bot potřebuje v tabulce `vouchers` sledovací sloupce (idempotence — neuplatnit 2×).
SQL je v hlavní konverzaci / `docs` — spusť ho v Supabase **před prvním během**.

## 1) Instalace

```bash
cd slevomat-bot
npm install            # nainstaluje i Chromium (postinstall)
cp .env.example .env   # vyplň SUPABASE_URL + SERVICE_ROLE key
cp config.example.json config.json
```

## 2) Zjištění selektorů portálu

Selektory v `config.json` musí sedět na skutečný portál. Dvě cesty:

- **Codegen (doporučeno):** `npm run record` otevře portál + nahrávač. Proklikej
  přihlášení a uplatnění jednoho poukazu — Playwright ti vygeneruje selektory,
  které přepíšeš do `config.json` (`usernameInput`, `passwordInput`, `loginSubmit`,
  `loggedInMarker`, `codeInput`, `redeemSubmit`, `resultMarker`).
- **DevTools:** pravý klik na pole → Prozkoumat → zkopíruj `name`/`id`.

Do `outcomes` doplň úryvky **skutečných hlášek** portálu (úspěch, „již uplatněn",
„neexistuje" …) — podle nich bot vyhodnocuje výsledek.

## 3) Přihlášení (jednorázově, zvládne 2FA)

```bash
npm run login
```

Otevře se prohlížeč — přihlas se ručně (i s 2FA/captchou). Session se uloží do
`sessions/storageState.json` a běhy ji pak používají bez hesla. Když vyprší,
spustíš `npm run login` znovu.

## 4) Běh

```bash
npm run dry-run   # jen vypíše frontu, nic neuplatní
npm run run       # uplatní čekající poukazy a zapíše výsledek do DB
npm run status    # souhrn: čeká / vyřízeno / chyby
```

## 5) Spouštění z Velínu (volitelné)

```bash
npm run serve     # lokální trigger na http://127.0.0.1:8787
```

Velín spuštěný **lokálně** může volat `POST /run` a `GET /status`. (Velín z Vercelu
přes HTTPS na localhost kvůli mixed-content nedosáhne — pro to by byl potřeba
samostatný server; řešíme později, až poběží základ.)

Automatický běh bez dohledu: naplánuj `npm run run` přes cron / Plánovač úloh.

## Jak to vyhodnocuje výsledek

| stav portálu | DB `slevomat_apply_status` | `slevomat_applied_at` | retry |
|---|---|---|---|
| úspěšně uplatněn | `applied` | nastaví | ne |
| již byl uplatněn | `already_redeemed` | nastaví | ne |
| neplatný / neexistuje | `invalid` | — | ne |
| nezaplacen | `not_paid` | — | ne |
| storno / refund | `cancelled` | — | ne |
| neznámá/přechodná chyba | `failed` | — | ano (do `MAX_ATTEMPTS`) |

Při chybě/neznámé hlášce se uloží screenshot do `screenshots/` pro dohledání.
`sessions/`, `screenshots/`, `.env`, `config.json` jsou v `.gitignore`.
