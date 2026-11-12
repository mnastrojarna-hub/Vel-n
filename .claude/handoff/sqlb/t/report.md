# Group t - owner texts: report (2026-11-12)

## Sources and method

- Drafts: `/home/user/Vel-n/.claude/handoff/sql-final/*.sql` (32 files). Final files: `/home/user/Vel-n/supabase/migrations/20261112t01_…` to `20261112t32_…`, same order (LC_ALL=C order of the old names a, b, c, d, da, e … z, za, zb, zc, zd), descriptive part of each name kept.
- Older variants `/home/user/Vel-n/.claude/handoff/sql/{m3a_owner_texts,owner_return_rule_email_templates,owner_return_rule_pobocky_steps}.sql` are superseded (their topics are covered by t01-t30, t32 and t23 respectively; they still say "NÁVRH, NEAPLIKOVÁNO" / "DRAFT") and were ignored.
- Live rows fetched today 2026-11-12 18:12 UTC with `rest_get.sh` (anon, GET only) into `t/live/`: cms_variables 1,232, faq_items 110 (anon sees published only), app_settings 86 (all but `service_role_key`, `cms_admin_token`; the bundle touches neither), cms_pages 13 (published only). `email_templates`: not readable (HTTP 200, 0 rows).
- Test databases: `sqlb_t` (seeded live rows + 5 synthetic e-mail templates), `sqlb_t_empty`, `sqlb_t_adv`, `sqlb_t_neg`. `seed.sh`, `test.sh`, `check_leaves.sql`, `adversarial.sql`, `neg_edits.sql` in this directory.

## Per file (run 1 on live data of today; run 2 = 0 changes for every file)

"Changed" = text leaves updated in run 1. "Skipped" = leaves left alone because live changed since 2026-10-15.

| File | Table | Changed | Skipped | Notes |
|---|---|---|---|---|
| t01 cms_return_1 | cms_variables | 19 | 0 | |
| t02 cms_return_2 | cms_variables | 12 | 0 | |
| t03 cms_pickup_1 | cms_variables | 22 | 0 | |
| t04 cms_pickup_2 | cms_variables | 14 | 0 | |
| t05 cms_pickup_3 | cms_variables | 1 | 0 | |
| t06 cms_home_app | cms_variables | 29 | 0 | |
| t07 faq_fuel | faq_items | 17 | 0 | Draft as written: 15 changed, 2 skipped (FAQ 77557a0b fr+uk "tankvak" fix). Cause: Czech answer changed by live migration 20261023f, not by a person; verified byte for byte; gate rebased to accept the post-20261023f fingerprint as well. |
| t08 faq_branches_1 | faq_items | 17 | 0 | |
| t09 faq_branches_2 | faq_items | 15 | 0 | |
| t10 faq_branches_3 | faq_items | 14 | 0 | |
| t11 faq_app | faq_items | 14 | 0 | |
| t12 overlay_dokumenty | app_settings | 18 | 0 | |
| t13 overlay_vraceni_pujcovna | app_settings | 18 | 0 | |
| t14 overlay_vraceni_jinde | app_settings | 12 | 0 | |
| t15 overlay_postup | app_settings | 24 | 0 | |
| t16 overlay_pristaveni_vyzvednuti | app_settings | 18 | 0 | |
| t17 overlay_home_pujcovna | app_settings | 24 | 0 | |
| t18 layout_1 | cms_variables | 27 | 0 | |
| t19 layout_2 | cms_variables | 1 | 0 | |
| t20 blog_app | cms_pages | 22 | 0 | |
| t21 ai_policies | app_settings | 3 | 0 | Velín default (WebAgentSettingsPanel.jsx step 5) already equals the new text on this branch. |
| t22 banner | app_settings | 1 row (7 translations + fingerprint) | 0 | live banner text "V zimním období od 1.11.2026 do 25.3.2027 zavřeno." unchanged since 2026-08-22, translations still missing |
| t23 pobocky_steps | cms_variables | 2 | 0 | |
| t24-t30 pobocky_preklady_1-7 | cms_variables | 33+42+11+3+13+55+4 = 161 | 0 | |
| t31 gate_procedure | function | 1 function | 0 | live body = 20261004 body (md5 7bbb079d…), so it is replaced; one sentence added |
| t32 email_templates | email_templates | not verifiable | - | table not readable with the anon key; see below |

Total: 504 text updates (t01-t30 without t22; PREHLED: 504 updates on 500 texts in 112 rows) + the banner row (7 translations + fingerprint) + 1 function, exactly the numbers PREHLED.md recorded on 2026-10-15 - nothing is lost today. A leaf-by-leaf check (`check_leaves.sql`, 440 expectation rows generated from the final files) gives 440 new / 0 still old / 0 missing.

## Skipped keys

None on today's live data after the t07 rebase. No text was edited in Velín after 2026-10-15 for any key these files touch (every md5/phrase gate still matched). The banner was last saved 2026-08-22.

## Consistency with the PHP texts on this branch

Every new text in the files was searched among all PHP string literals of `motogo-web-php` at HEAD and at 2a959ded (the commit the drafts were generated from; PHP is identical at 8bdf4860): 339 exact matches and 4 substring matches at HEAD, each in the same PHP files as at 2a959ded (four more copies were added to `lang/fr.php`/`lang/uk.php`, same text). 99 texts have no PHP counterpart by design (FAQ, blog, AI prompt, Velín-only tykání variants of home step 3 and the contact card, cs `nextBookingPickup`, es/fr step-3 titles that live only in the DB). No text that matched PHP on 2026-10-15 has diverged from PHP since. So the PHP changes made on this branch after 2026-10-15 do not create an inconsistency with these migrations.

## Robustness (no file may abort on live data)

- Empty tables (`sqlb_t_empty`, schema only): 32/32 files, twice, no error.
- Broken shapes (`sqlb_t_adv`): values as number/object/JSON null, translations as array/JSON null/language as string/value as number, deleted rows and keys, overlay as array/string/empty object, AI config JSON null, banner without text, blog content/excerpt NULL, translations null on other pages, empty e-mail body, hand-edited `_gate_procedure_msg`: twice, no error, 267 NOTICE skips, second run no data change, hand-edited function untouched.
- Owner-edit simulation (`sqlb_t_neg`): 11 edited texts (cs step 12, en CTA, de footer, en overlay, cs FAQ + its translations, uk FAQ, cs blog perex + translations, banner text) all byte-identical after the bundle; dependent translations skipped with "česká hodnota není v očekávaném znění".
- All columns touched are NOT NULL text/jsonb except `cms_pages.content/excerpt` (guarded by strpos → NULL → no match). No casts on data, no unique indexes, no constraints, tables are small (largest 1,232 rows), no locks beyond row locks of the updated rows.
- `email_templates` (not readable): reviewed by reading; tested on 5 synthetic templates (old paragraph with &nbsp;/&mdash;, informal variant with line break and U+00A0 twice in one body, 2026-10-11 variant with &ndash;, unrelated template, Google-Play-only template, empty body). Replaced where matched, the app line inserted before `<h3>Vrácení motorky</h3>` only in booking_reserved/web_booking_reserved without any app mention, `body_translations` reset only on changed rows, others untouched, second run 0 changes. On live, the deploy log will show which templates changed and the two NOTICE lists for manual review.

## Apply twice / deploy simulation

`deploy_sim.sh sqlb_t` (MIG_GLOB `20261112t*.sql`): 32 processed, 0 errors; `--again`: schema signature identical, every table's content hash identical. Against the pristine template the only schema difference is the body md5 of `_gate_procedure_msg`; data differences only in app_settings, cms_pages, cms_variables, email_templates (synthetic), faq_items.
