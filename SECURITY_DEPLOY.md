# Bezpečnostní opravy 2026-06-10 — nasazovací návod

Všechny opravy jsou na větvi `claude/confident-goodall-5sg9fd`. **Nic není živé**,
dokud to vědomě nenasadíš. Pořadí níže je důležité, ať se nic nerozbije.

---

## A) Hotovo bez nasazení (živé hned po SQL)

- **RLS `app_settings`** — veřejné čtení `service_role_key` zablokováno. (Spuštěno.)
- **Rotace `service_role_key`** — DOPORUČENO (klíč byl dřív čitelný). Po rotaci
  aktualizuj na 3 místech naráz: řádek `service_role_key` v `app_settings`,
  Supabase Edge secret, a kdekoli ho drží Velín.

---

## B) Edge funkce (deploy = `supabase functions deploy <name>`)

Tyto získaly auth gate / opravu. Po nasazení fungují stejně (všichni interní
volající posílají service_role, Velín posílá admin session):

```
supabase functions deploy process-refund
supabase functions deploy generate-invoice
supabase functions deploy send-email
supabase functions deploy send-broadcast
supabase functions deploy send-order-email
supabase functions deploy render-pdf
supabase functions deploy receive-invoice      # odstraněn natvrdo FALLBACK_KEY
supabase functions deploy cms-save             # přijímá podepsanou capability
supabase functions deploy cms-admin-auth       # NOVÁ — viz C)
```

> **receive-invoice:** po nasazení MUSÍ být nastavený secret `INVOICE_API_KEY`
> (jinak doc-scanner nenahraje doklad). Doporučeno rotovat na novou hodnotu a
> zadat ji v doc-scanneru (aplikace si o klíč řekne při prvním odeslání).

---

## C) Oprava #5 — cms_admin_token (pořadí KRITICKÉ)

Cíl: token přestane chodit do prohlížeče a smí se skrýt z anon RLS. Princip:
podepsaná capability (RSA). Privátní klíč = Supabase secret (NE hosting),
veřejný klíč je už v kódu (`config.php`, `cms-save`).

**Krok 1 — nastav Supabase secret s privátním klíčem** (klíč ti dal asistent v chatu):
```
supabase secrets set CMS_ADMIN_SIGN_KEY="$(cat cms_priv.pem)"
```
(nebo přes Dashboard → Edge Functions → Manage secrets → `CMS_ADMIN_SIGN_KEY`)

**Krok 2 — deploy edge funkce:**
```
supabase functions deploy cms-admin-auth
supabase functions deploy cms-save
```

**Krok 3 — nasaď PHP web** (motogo-web-php) na hosting (FTP/git jako obvykle).

> Po krocích 1–3 už web posílá do prohlížeče jen podepsanou capability, ne token.
> Stávající admini se jednou znovu přihlásí přes odkaz z Velína (`?cms_admin=…`).

**Krok 4 (volitelné, AŽ po ověření kroků 1–3) — skryj token i z anon RLS:**
```sql
ALTER POLICY app_settings_public_read ON public.app_settings
  USING (key NOT IN ('service_role_key','cms_admin_token'));
```
Po tomto kroku raw token nikdo přes anon nepřečte. Ověření tokenu na serveru
(cms-cache-purge, master-export) jede přes edge `cms-admin-auth` (service_role),
takže nic nepadá. CMS inline editace běží přes capability.

---

## D) Velín (build + deploy jako obvykle)

XSS sanitizace (DOMPurify). `npm install` (přidán `dompurify`) + `npm run build`
+ deploy. Build ověřen, funkčně beze změny.

---

## E) Mobilní aplikace

- **doc-scanner** (Capacitor rebuild): klíč už není v bundlu, escapování XSS,
  `allowMixedContent:false`. Po rebuildu účetní zadá `INVOICE_API_KEY` jednou.
- **Flutter app** (rebuild): PII se neloguje hodnotami. Žádná funkční změna.

---

## Rollback

Vše je v gitu na větvi — návrat = redeploy předchozí verze. Jediná „nevratná"
část je rotace klíčů (běžná operace). RLS změny lze vrátit `DROP POLICY` /
`CREATE POLICY ... USING (true)` (NEDOPORUČENO — vrátí únik).
