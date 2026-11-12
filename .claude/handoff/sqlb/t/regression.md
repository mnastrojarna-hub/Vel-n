# Group t (owner texts) - live regression check

Live reference: snapshot origin/supabase-live-snapshot e5d5b0f7 (2026-11-12 11:01 UTC), loaded in the rig as database `base`.

## Objects the 32 files replace or re-create

| Object | Kind | Files | Result |
|---|---|---|---|
| `public._gate_procedure_msg(text, integer, boolean)` | SQL function (CREATE OR REPLACE inside a guarded DO block) | t31 | see below |
| triggers, policies, views, indexes, constraints | - | none | none of the 32 files re-creates any of them |
| tables `cms_variables`, `faq_items`, `app_settings`, `cms_pages`, `email_templates` | data only (UPDATE) | t01-t30, t32 | no DDL; triggers that fire on them are unchanged (see "Triggers that fire") |

## `_gate_procedure_msg` - evidence

- Live body today: `defn.sh base _gate_procedure_msg`; `md5(prosrc)` = `7bbb079dedee0cf53a0e851fb6ccef01` (identical with and without CR removal, i.e. the live body has LF line endings). This is exactly the 20261004 body the draft was written against; no migration after 20261004 changed it (20261023c only calls it; its header says the function is left untouched, and the gear-only flow uses its own `_gear_procedure_msg`).
- Live ACL: `postgres=X/postgres, service_role=X/postgres`, owner postgres, LANGUAGE sql IMMUTABLE, not SECURITY DEFINER.
- `fndiff.sh base sqlb_t` after the bundle - the only difference in all public functions and views:
  ```
  -    ') DŮLEŽITÉ: ... Otevřenou bránu nechte otevřenou. Stejně postupujte i při vrácení motorky.'
  +    ') DŮLEŽITÉ: ... Otevřenou bránu nechte otevřenou. Stejně postupujte i při vrácení motorky. Motorku vracejte umytou a tak, aby nesvítila kontrolka rezervy (tankovat do plna nemusíte).'
  ```
  One line, exactly the intended sentence (owner rule 2026-10-11: self-service branch = washed + reserve light off). New md5 `1972a4a83ca2587adc616a1964441d05`.
- `sig.sh` before/after: the only changed line in the whole signature is this function's body md5; arguments, return type, language, volatility, owner and ACL are identical (the draft's REVOKE FROM PUBLIC, anon, authenticated is a no-op on live and keeps service_role).
- Guard: the replacement runs only when the live md5 equals the 20261004 md5; any other body is left alone with a NOTICE (tested: a hand-edited body survived both runs).
- Verdict: no rebase needed; draft body = live body + exactly the intended sentence.

## Triggers that fire on the updated tables (unchanged, checked for side effects)

- `cms_variables`: `trg_sync_cms_flat_to_nested` (AFTER INSERT/UPDATE, WHEN key is one of 16 `web.pujcovna.*` / `web.kontakt.*` keys). The bundle updates none of those 16 keys (its only `web.pujcovna.*` key is `web.pujcovna.faq.items.0.a`, not in the list), so the trigger does not fire.
- `faq_items`: `faq_items_set_updated_at`; `cms_pages`: `cms_pages_updated_at`; `app_settings`: `trg_app_settings_updated`; `email_templates`: `trg_email_templates_updated` - all only set `updated_at`.

## Data that changed since the drafts were written (2026-10-15)

- All gated texts except one still have the verified 2026-10-15 fingerprint on live today (REST fetch 2026-11-12 18:12 UTC).
- FAQ `77557a0b` ("Můžu si u vás půjčit jen výbavu…"): the Czech answer was changed by the live migration `20261023f_faq_gear_rental.sql` (gear-only rental sentence). Verified: undoing exactly that migration's replacement on today's live text gives the 2026-10-15 md5 `a8f0728b…`. Its fr/uk translations still contain the wrong "fuel tank" wording for "tankvak". t07 was rebased: the gate for this one FAQ accepts both fingerprints (`a8f0728b…` = before 20261023f, `88113339…` = after 20261023f); any other Czech text still skips. This is not a widening over owner edits: the accepted second state is the output of a git migration, verified byte for byte.
