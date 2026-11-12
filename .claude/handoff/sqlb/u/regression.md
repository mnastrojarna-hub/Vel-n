# Group u (QA text and translation fixes) — live regression check

## 1. Objects replaced or re-created

None. All 14 files are data-only `DO $$ … $$` blocks that run UPDATE statements on existing rows.
No file contains CREATE, DROP, ALTER, GRANT, REVOKE, CREATE TRIGGER or CREATE POLICY (checked with grep
on the drafts and on the final files). There is therefore no function, trigger, view, policy, index or
constraint body that could be reverted to an older version.

Proof on the rig (database `sqlb_u`, seeded with live rows, whole bundle a+b+c+t+u applied by
`deploy_sim.sh`):

* A database with only the t drafts (handoff/sql-final) + the 14 u files applied differs from `base` in
  `sig.sh` in exactly one line, `FUNCTION _gate_procedure_msg` (changed by the t gate-procedure file, not
  by group u). The empty-database run of all u files leaves `sig.sh` identical to `base`.
* `sig.sh` after the u files run 1 and run 2: identical. `datasig.sh` run 1 and run 2: identical
  (no row is touched by a second run).
* `fndiff.sh` is not applicable (no function changed by u).

## 2. Existing live triggers that fire on the updated tables (side effects checked)

Live trigger definitions taken from `base` (= snapshot e5d5b0f7):

| Table | Trigger | Fires on our UPDATE? | Effect / verdict |
|---|---|---|---|
| cms_variables | `trg_sync_cms_flat_to_nested` (AFTER INSERT OR UPDATE, WHEN key in 16 flat keys) | yes, if a flat key is updated | **Found a real regression in draft 20261016c:** its wildcard replacements updated the translations of the legacy flat keys `web.pujcovna.intro` (nl, pl) and `web.pujcovna.ben.bottom` (pl). The trigger then copies the flat key's Czech `value` over the nested key the website reads, so live Czech texts edited later in Velín would have been reverted: `web.pujcovna.intro.body` (owner text "Naše půjčovna motorek na Vysočině…" replaced by the older "MotoGo24 - půjčovna motorek v Pelhřimově…") and `web.pujcovna.benefits.closing` ("Hledáš…" → "Hledáte…"). **Fixed in 20261112u02:** the 16 keys of the trigger's WHEN list are excluded from every cms_variables update (`c.key <> ALL (c_sync_keys)`). The website reads only the nested keys (`pages/pujcovna.php`, `pages/pujcovna-v2.php`), so nothing visible is lost. Verified: after the whole bundle both nested values are byte-identical to live (md5 in test.sh). No other u file and no t file updates a flat key (checked on the change lists). |
| cms_variables | (no updated_at trigger) | — | Files set `updated_at = now()` themselves, as the drafts did. |
| faq_items | `faq_items_set_updated_at` | yes | updated_at only. |
| cms_pages | `cms_pages_updated_at` | yes | updated_at only. |
| app_settings | `trg_app_settings_updated` | yes | updated_at only. |
| document_templates | `trg_document_templates_updated` | yes | updated_at only. |
| custom_documents | `trg_custom_documents_updated_at` | yes | updated_at only (FK `updated_by` → admin_users is unchanged). |
| products | `trg_products_updated` | yes | updated_at only. |
| motorcycles | `motorcycles_updated_at` | yes | updated_at only. |
| motorcycles | `trg_sync_moto_to_assets` (AFTER UPDATE, every column) | yes | Re-writes `acc_long_term_assets.name/status` from the bike (same as every Velín save of a bike; wrapped in EXCEPTION WHEN OTHERS). Not a regression; noted. |
| motorcycles | branch/box/cache triggers (`trg_guard_moto_branch_type_move`, `trg_moto_branch_move_free_box`, `_booking_branch_follow_moto`, `trg_regen_codes_on_moto_relocation`, `trg_web_cache_purge_motorcycles`, `trg_moto_purchase_mileage_floor`) | no | Column lists / WHEN clauses do not include `translations`. |

## 3. Draft versus final, file by file

| Final file | Draft | Difference | Verdict |
|---|---|---|---|
| 20261112u01_qa_faq_review_google_only | 20261016b | new header; guard `jsonb_typeof(translations)='object'` and same for `translations->lang` | robustness only (a JSON-null translations would raise "cannot set path in scalar") |
| 20261112u02_qa_translation_fixes | 20261016c | new header; flat sync keys excluded (see §2) | fixes a live-data regression |
| 20261112u03_qa_texts_branches | 20261016d | new header; blog update guarded by `jsonb_typeof(translations)='object'` | robustness only |
| 20261112u04…u06 | e, f, ga | new header only | — |
| 20261112u07_qa_uk_texts | 20261016h | new header; object guards on custom_documents/products/cms updates | robustness (the custom_documents update raised on scalar translations in the robustness test) |
| 20261112u08, u09 | i, j | new header; object guard | robustness |
| 20261112u10_qa_moto_translations | k | new header; object guards | robustness |
| 20261112u11…u14 | l, m, w1, w2 | new header only | — |

Excluded on purpose: 20261016a_qa_messages_insert_policy.sql, 20261016g_qa_binding_docs_washing.sql.

## 4. Overlap with migrations already live

Migrations after 2026-10-16 that touch the same tables: `20261023_web_layout_labels.sql`
(web.layout.editRez.cal.dow.*, web.layout.rez.cal.dayShort.*, web.layout.rez.cta.continue) and
`20261023f_faq_gear_rental.sql` (faq 77557a0b + ai_kb_version). No u file touches those keys or that FAQ
(checked on the change lists of the seeded run). Because the seed is today's live data, every guard was
tested against the state those migrations left: every targeted row matched and was changed; the only
NOTICEs are 14 wildcard patterns of u02 that do not occur in today's texts.

## 5. Overlap with group t (owner texts, repo files 20261112t01–t32)

Same field changed by both groups (t first, then u): faq dac51062 translations de/nl/pl answer
("in der gesamten ČR" → "in ganz Tschechien" etc. inside the new t texts) and faq e7079920 uk answer
(address "Mezná 9, 393 01 Mezná (біля Пельгржимова)" → "Mezná 9, 393 01 Pelhřimov"). In both cases u
replaces only the exact substring, so it accepts and refines the t result. Further 6 rows are touched by
both groups in different fields (t: some languages, u: uk translation or one question); u's md5 guards on
the Czech source still matched, so nothing was skipped. u03 step 3 (web.postup.step.5.text) runs only after
t has put "Němčic" into web.jak_pujcit_postup.process.steps.4.text; without t it is skipped with no error.
