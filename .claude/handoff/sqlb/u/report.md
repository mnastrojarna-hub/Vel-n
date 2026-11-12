# Group u — QA text and translation fixes: per-file report

Source of truth for the data: live rows fetched today (2026-11-12) through REST with the anon key into
`u/live/` (cms_variables 1,232, faq_items 110, cms_pages 13, motorcycles 27, app_settings 86,
document_templates 8, custom_documents 3, products 6, branches 2, admin_users ids 2). Limits: anon sees only
published FAQ items (`published = true`), published CMS pages, active document templates, custom documents
with `active AND show_on_web`, and app_settings except two secret keys. Unpublished/inactive rows were not
seeded; every statement is guarded, so on live they are either changed with the same guards or skipped.

Procedure (database `u_rep`): seed live rows → apply repo files 20261112a*…t* (all groups before u) →
apply u01…u14 one by one, snapshot after each file, diff field by field → apply all again (no row changes).
The same was done with the t drafts from `.claude/handoff/sql-final` (database `sqlb_u`), with no t at
all (`u_not`), on an empty database (`u_empty`) and on a database with deliberately malformed JSON shapes
(`u_weird`, `tools/weird.sql`): all runs succeed, second runs change nothing.

## Summary

| Final file | Draft | Changed fields (rows) on live data after t | Skipped | Notes |
|---|---|---|---|---|
| 20261112u01_qa_faq_review_google_only.sql | 20261016b | 8 (1) | 0 | Czech answer + 7 translations of FAQ fa9603a9 |
| 20261112u02_qa_translation_fixes.sql | 20261016c | 70 (49) | 14 | 14 skipped = wildcard patterns not present in today's texts (expected); flat sync keys excluded (regression fix) |
| 20261112u03_qa_texts_branches.sql | 20261016d | 41 (12) | 0 | step 3 depends on t (runs only when steps.4.text names Velké Němčice) |
| 20261112u04_qa_vop_stale_translations.sql | 20261016e | 4 (1) | 0 | deletes en/es/fr/nl VOP translations (no fingerprint, full-tank promise) |
| 20261112u05_qa_vop_footer_address.sql | 20261016f | 2 (1) | 0 | VOP footer address only, version 14 → 15 |
| 20261112u06_qa_contract_stale_translations.sql | 20261016ga | 6 (1) | 0 | deletes de/en/es/fr/nl/pl contract translations (stale, old cleanliness sentence) |
| 20261112u07_qa_uk_texts.sql | 20261016h | 41 (28) | 0 | 23 uk CMS, 6 blog title, 1 pl heading, 4 document titles, 2 products |
| 20261112u08_qa_faq_uk_1.sql | 20261016i | 64 (32) | 0 | 32 uk FAQ |
| 20261112u09_qa_faq_uk_2.sql | 20261016j | 62 (31) | 0 | 31 uk FAQ |
| 20261112u10_qa_moto_translations.sql | 20261016k | 20 (5) | 0 | 18 feature lists + 2 uk descriptions |
| 20261112u11_qa_nl_wrong_language.sql | 20261016l | 36 (10) | 0 | 33 cms translations + 3 motorcycle nl fields |
| 20261112u12_qa_blog_top10_nl.sql | 20261016m | 3 (1) | 0 | nl title/excerpt/content |
| 20261112u13_web_editrez_h1_terms.sql | 20261016w1 | 3 (1) | 0 | de/es/nl |
| 20261112u14_web_blog_slug_p.sql | 20261016w2 | 1 (1) | 0 | slug p → proc-je-motogo24-nejlepsi-motopujcovna-v-cr |


## Keys touched by both t and u

See `regression.md` §5: four fields are changed by both (faq dac51062 de/nl/pl answer, faq e7079920 uk
answer); u replaces only the exact old substring inside the t result (accepts it). Six more rows are
touched by both groups in different fields; no u guard rejected a t result.

## Live-data finding fixed in u02

Draft c updated translations of three legacy flat CMS keys; the live trigger `trg_sync_cms_flat_to_nested`
would then have overwritten the Czech text of `web.pujcovna.intro.body` and `web.pujcovna.benefits.closing`
(both edited in Velín after the flat keys) with the older flat values. u02 excludes the 16 flat keys.

## Per-file details (changed fields, skipped NOTICEs)

### u01: 8 changed fields in 1 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| faq_items | fa9603a9-a628-4349-9797-4c0bcc71fc57 | answer, translations.de.answer, translations.en.answer, translations.es.answer, translations.fr.answer, translations.nl.answer, translations.pl.answer, translations.uk.answer |

Skipped (NOTICE): none

### u02: 70 changed fields in 49 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| cms_variables | web.home.h1 | translations.pl.value |
| cms_variables | web.home.hero.body | translations.fr.value |
| cms_variables | web.home.intro | translations.pl.value |
| cms_variables | web.home.motos_section.intro | translations.pl.value |
| cms_variables | web.home.seo.keywords | translations.nl.value |
| cms_variables | web.home.seo.title | translations.fr.value, translations.pl.value |
| cms_variables | web.jak_pujcit_dokumenty.cta.title | translations.fr.value |
| cms_variables | web.jak_pujcit_postup.process.steps.3.text | translations.pl.value |
| cms_variables | web.jak_pujcit_vraceni_jinde.cta.text | translations.pl.value |
| cms_variables | web.jak_pujcit_vraceni_jinde.when.items.0 | translations.de.value, translations.pl.value |
| cms_variables | web.jak_pujcit_vyzvednuti.cta.title | translations.pl.value |
| cms_variables | web.kontakt.outro.body2 | translations.de.value, translations.pl.value |
| cms_variables | web.kontakt.reg | translations.pl.value |
| cms_variables | web.kontakt.seo.description | translations.pl.value |
| cms_variables | web.layout.checkout.shipping.pickup | translations.es.value, translations.pl.value |
| cms_variables | web.layout.checkout.title | translations.en.value, translations.es.value |
| cms_variables | web.layout.editRez.moto.help | translations.pl.value |
| cms_variables | web.layout.editRez.moto.intro | translations.pl.value |
| cms_variables | web.layout.menu.catalog | translations.nl.value |
| cms_variables | web.layout.rezervace.description | translations.fr.value |
| cms_variables | web.layout.voucher.description | translations.nl.value |
| cms_variables | web.mapa_stranek.outro.body1 | translations.pl.value |
| cms_variables | web.oblasti.cta.text | translations.de.value, translations.nl.value, translations.pl.value |
| cms_variables | web.oblasti.region.jihomoravsky_kraj.citiesIntro | translations.pl.value |
| cms_variables | web.oblasti.region.jihomoravsky_kraj.ctaTitle | translations.pl.value |
| cms_variables | web.oblasti.region.jihomoravsky_kraj.intro | translations.nl.value |
| cms_variables | web.oblasti.region.vysocina.ctaText | translations.pl.value |
| cms_variables | web.oblasti.region.vysocina.ctaTitle | translations.fr.value, translations.nl.value |
| cms_variables | web.oblasti.region.vysocina.heroTagline | translations.fr.value |
| cms_variables | web.oblasti.region.vysocina.intro | translations.fr.value, translations.nl.value |
| cms_variables | web.oblasti.seo.description | translations.pl.value, translations.uk.value |
| cms_variables | web.pujcovna.cta.text | translations.pl.value |
| cms_variables | web.pujcovna.cta.title | translations.pl.value |
| cms_variables | web.pujcovna.intro.body | translations.nl.value |
| cms_variables | web.pujcovna.intro.h1 | translations.de.value |
| cms_variables | web.pujcovna.process.steps.4.text | translations.pl.value |
| cms_variables | web.pujcovna.seo.description | translations.pl.value |
| faq_items | 02b6cfc8-83af-4887-8f5f-a62214f64f2a | translations.pl.answer |
| faq_items | 050e0db7-068d-4db7-b321-5a6d0f0efa3f | translations.pl.answer |
| faq_items | a278501f-331d-4b53-a298-22eba57451ea | translations.de.answer |
| faq_items | b27221f5-dc55-4bf7-b320-c70b267c6a76 | translations.pl.answer |
| faq_items | d2051db9-f4d6-4d24-9009-c3df6be6fd45 | translations.de.answer, translations.pl.answer |
| faq_items | d87bbb0e-0cc1-43a0-9cc4-9a2dc3118aac | translations.pl.answer |
| faq_items | dac51062-20c0-4ea9-8422-54720f27b87e | translations.de.answer, translations.nl.answer, translations.pl.answer |
| faq_items | dd9c3286-142c-4601-9060-f7bb1f78f4a7 | translations.de.question, translations.pl.question |
| faq_items | e7079920-f08c-4b08-b52a-9b8623909035 | answer, translations.de.answer, translations.en.answer, translations.es.answer, translations.fr.answer, translations.nl.answer, translations.pl.answer, translations.uk.answer |
| faq_items | e9d26f91-d0b8-4578-b586-f581d95cc67a | translations.de.answer |
| cms_pages | 48a316a8-08d3-4d8b-8006-fa8edaaf4215 | translations.nl.content |
| motorcycles | edabe801-841f-457e-9fc8-944370ec4002 | translations.pl.description |

Skipped (NOTICE): 
- qa_translation_fixes: beze změny #16 cms_variables * es „en Pelhřimově“
- qa_translation_fixes: beze změny #18 cms_variables * de „in der gesamten ČR“
- qa_translation_fixes: beze změny #19 cms_variables * de „innerhalb der ČR“
- qa_translation_fixes: beze změny #22 cms_variables * nl „in heel de ČR“
- qa_translation_fixes: beze změny #23 cms_variables * nl „in de ČR“
- qa_translation_fixes: beze změny #24 cms_variables * pl „w dowolnym miejscu w ČR“
- qa_translation_fixes: beze změny #27 cms_variables * pl „gdziekolwiek w ČR“
- qa_translation_fixes: beze změny #28 cms_variables * pl „na terenie całej ČR“
- qa_translation_fixes: beze změny #29 cms_variables * pl „na terenie ČR“
- qa_translation_fixes: beze změny #30 cms_variables * pl „Policji ČR“
- qa_translation_fixes: beze změny #52 faq_items * pl „w dowolnym miejscu w ČR“
- qa_translation_fixes: beze změny #53 faq_items * pl „w dowolne miejsce w ČR“
- qa_translation_fixes: beze změny #54 faq_items * pl „w całej ČR“
- qa_translation_fixes: beze změny #55 faq_items * pl „gdziekolwiek w ČR“

### u03: 41 changed fields in 12 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| cms_variables | web.jak_pujcit_cena.gear.services.items.0 | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value, value |
| cms_variables | web.jak_pujcit_cena.gear.services.items.1 | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value, value |
| cms_variables | web.oblasti.region.jihomoravsky_kraj.citiesIntro | value |
| cms_variables | web.oblasti.region.jihomoravsky_kraj.intro | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value, value |
| cms_variables | web.postup.step.5.text | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value, translations.uk.value, value |
| cms_pages | 48a316a8-08d3-4d8b-8006-fa8edaaf4215 | content, translations.en.content, translations.es.content, translations.fr.content, translations.nl.content |
| app_settings | pages_overlay.jak_pujcit_cena.de | value.gear.services.items |
| app_settings | pages_overlay.jak_pujcit_cena.en | value.gear.services.items |
| app_settings | pages_overlay.jak_pujcit_cena.es | value.gear.services.items |
| app_settings | pages_overlay.jak_pujcit_cena.fr | value.gear.services.items |
| app_settings | pages_overlay.jak_pujcit_cena.nl | value.gear.services.items |
| app_settings | pages_overlay.jak_pujcit_cena.pl | value.gear.services.items |

Skipped (NOTICE): none

### u04: 4 changed fields in 1 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| document_templates | bb283ab2-da20-4562-8e8d-27832a77c748 | content_translations.en, content_translations.es, content_translations.fr, content_translations.nl |

Skipped (NOTICE): none

### u05: 2 changed fields in 1 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| document_templates | bb283ab2-da20-4562-8e8d-27832a77c748 | content_html, version |

Skipped (NOTICE): none

### u06: 6 changed fields in 1 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| document_templates | e5945ec0-df44-4244-b260-e589b2916bff | content_translations.de, content_translations.en, content_translations.es, content_translations.fr, content_translations.nl, content_translations.pl |

Skipped (NOTICE): none

### u07: 41 changed fields in 28 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| cms_variables | web.blog.outro.body1 | translations.uk.value |
| cms_variables | web.blog.outro.body2 | translations.uk.value |
| cms_variables | web.blog.outro.title | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value, translations.uk.value |
| cms_variables | web.dokumenty_detail.outro.body1 | translations.uk.value |
| cms_variables | web.dokumenty_detail.outro.body2 | translations.uk.value |
| cms_variables | web.dokumenty_detail.outro.title | translations.uk.value |
| cms_variables | web.eshop.outro.body1 | translations.uk.value |
| cms_variables | web.eshop.outro.title | translations.uk.value |
| cms_variables | web.eshop_detail.outro.body1 | translations.uk.value |
| cms_variables | web.eshop_detail.outro.body2 | translations.uk.value |
| cms_variables | web.eshop_detail.outro.title | translations.uk.value |
| cms_variables | web.katalog.h1 | translations.uk.value |
| cms_variables | web.katalog.outro.title | translations.uk.value |
| cms_variables | web.katalog_detail.outro.body1 | translations.uk.value |
| cms_variables | web.katalog_detail.outro.body2 | translations.uk.value |
| cms_variables | web.katalog_detail.outro.title | translations.uk.value |
| cms_variables | web.koupit_darkovy_poukaz.outro.body1 | translations.uk.value |
| cms_variables | web.koupit_darkovy_poukaz.outro.body2 | translations.pl.value, translations.uk.value |
| cms_variables | web.koupit_darkovy_poukaz.outro.title | translations.uk.value |
| cms_variables | web.mapa_stranek.intro | translations.uk.value |
| cms_variables | web.mapa_stranek.outro.body1 | translations.uk.value |
| cms_variables | web.mapa_stranek.outro.body2 | translations.uk.value |
| cms_variables | web.mapa_stranek.outro.title | translations.uk.value |
| custom_documents | 2178215f-94af-48a7-8868-6fc022fd647a | translations.pl.title, translations.uk.title |
| custom_documents | 97c772fd-f860-4fbc-9dc9-5c60f2f41562 | translations.uk.title |
| custom_documents | ef8abaf4-7460-43a9-aa4a-db9160e282df | translations.uk.title |
| products | 0551496d-77a4-4f51-bc23-9196b3440f14 | translations.uk.color, translations.uk.description, translations.uk.material, translations.uk.name |
| products | 86616309-d992-443d-8d70-07183b7788cf | translations.uk.description, translations.uk.material, translations.uk.name |

Skipped (NOTICE): none

### u08: 64 changed fields in 32 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| faq_items | 06e44d78-8b32-4b96-9f54-339ad771f754 | translations.uk.answer, translations.uk.question |
| faq_items | 16fde840-124b-4d9b-9b28-8fef51f6cd63 | translations.uk.answer, translations.uk.question |
| faq_items | 1d6a2118-149b-4215-9629-84bb4b61f8da | translations.uk.answer, translations.uk.question |
| faq_items | 1e797601-b347-44e4-82a6-c7537273f218 | translations.uk.answer, translations.uk.question |
| faq_items | 21046767-7631-4fba-aced-30f7f639f3b1 | translations.uk.answer, translations.uk.question |
| faq_items | 2eb52c53-9725-4fbf-bf6f-5163a690cb0c | translations.uk.answer, translations.uk.question |
| faq_items | 333ae882-1e32-4d8e-818e-027e48af5c35 | translations.uk.answer, translations.uk.question |
| faq_items | 3981c695-81fb-43db-9146-0c9e0876c7cf | translations.uk.answer, translations.uk.question |
| faq_items | 43a6ee13-9e6c-4cf2-b4b0-5bdeb96259e4 | translations.uk.answer, translations.uk.question |
| faq_items | 5444d2cf-0251-4a22-a373-0e361a36599f | translations.uk.answer, translations.uk.question |
| faq_items | 5a0578d6-f6c5-4ddf-91c7-aa5f1d41b8e6 | translations.uk.answer, translations.uk.question |
| faq_items | 5c26fb3a-a29e-453a-8474-152d4ee61246 | translations.uk.answer, translations.uk.question |
| faq_items | 65e534e5-11a1-4cc9-bab5-f6b01862611c | translations.uk.answer, translations.uk.question |
| faq_items | 6a4ef36b-d2b7-4b4a-bc3b-82b3a643a941 | translations.uk.answer, translations.uk.question |
| faq_items | 732b6abe-a788-4fa5-b3a2-bd0ddfc371f0 | translations.uk.answer, translations.uk.question |
| faq_items | 753cbff4-046c-4807-abf3-018a1e201766 | translations.uk.answer, translations.uk.question |
| faq_items | 76ac05d1-65d6-426b-a8c3-da192e7fb82f | translations.uk.answer, translations.uk.question |
| faq_items | 7d72e4b0-e2ff-4713-99a7-6bdaf44d924b | translations.uk.answer, translations.uk.question |
| faq_items | 8f8eb104-3f74-4d0d-82cc-271c59ac3d70 | translations.uk.answer, translations.uk.question |
| faq_items | 92fb7f7a-f82b-415c-8d8f-0dc012899b73 | translations.uk.answer, translations.uk.question |
| faq_items | 9b388e3a-bf29-4760-a948-937e88a2f447 | translations.uk.answer, translations.uk.question |
| faq_items | 9e5a0b6a-262b-4029-8349-0542310a879c | translations.uk.answer, translations.uk.question |
| faq_items | a278501f-331d-4b53-a298-22eba57451ea | translations.uk.answer, translations.uk.question |
| faq_items | a2e964db-1263-40cb-86ff-6420c0841e56 | translations.uk.answer, translations.uk.question |
| faq_items | aa6d7e5a-526d-4147-a041-bc7972ef592a | translations.uk.answer, translations.uk.question |
| faq_items | b0bc8012-76e6-4f62-bbe7-0a3ff171ec94 | translations.uk.answer, translations.uk.question |
| faq_items | b4bf8554-35d6-4bcc-a205-1d783d705615 | translations.uk.answer, translations.uk.question |
| faq_items | c0f9f534-401c-462b-af49-04ca02b73f18 | translations.uk.answer, translations.uk.question |
| faq_items | e18a59ca-f1f5-42ff-9f06-522af9b08b65 | translations.uk.answer, translations.uk.question |
| faq_items | ee9690ad-698e-45cb-ac9b-b5d20e47a267 | translations.uk.answer, translations.uk.question |
| faq_items | f2c036d1-4aec-414c-b953-41d379a43277 | translations.uk.answer, translations.uk.question |
| faq_items | fdc85aa7-9aa6-4cab-a28b-6b0076cd10d9 | translations.uk.answer, translations.uk.question |

Skipped (NOTICE): none

### u09: 62 changed fields in 31 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| faq_items | 0687d883-0734-4a1a-8b26-0df13185df1d | translations.uk.answer, translations.uk.question |
| faq_items | 0b7ecebd-da89-44ec-ab2b-e3ac2063781b | translations.uk.answer, translations.uk.question |
| faq_items | 178523b3-1d4f-4f8c-a8dd-32df04cb2431 | translations.uk.answer, translations.uk.question |
| faq_items | 1c13a6d0-0756-46ba-ae1f-761f2c837ca9 | translations.uk.answer, translations.uk.question |
| faq_items | 1f0e38c0-35a8-4737-93ba-bde974234a9e | translations.uk.answer, translations.uk.question |
| faq_items | 2c128ed9-e685-46be-b290-8b0d1f33d8f7 | translations.uk.answer, translations.uk.question |
| faq_items | 310136c2-cf0c-417e-aada-029b525c47c0 | translations.uk.answer, translations.uk.question |
| faq_items | 424453f2-03d2-4929-a6b7-0714cc19382d | translations.uk.answer, translations.uk.question |
| faq_items | 4975240d-08a4-458b-9a21-3ec8fb9557b1 | translations.uk.answer, translations.uk.question |
| faq_items | 56e73a47-b8eb-4e95-8dfd-e86993cb23ab | translations.uk.answer, translations.uk.question |
| faq_items | 59befbaa-6b5d-4188-80cc-6a67c08b1e3c | translations.uk.answer, translations.uk.question |
| faq_items | 59c0e244-3654-4d59-9398-a287ca612c72 | translations.uk.answer, translations.uk.question |
| faq_items | 745b52dd-712d-4bb8-b1ca-65204ef49b90 | translations.uk.answer, translations.uk.question |
| faq_items | 780628c8-34ab-4a86-96da-2b46f5529594 | translations.uk.answer, translations.uk.question |
| faq_items | 78d4791f-d161-41eb-b754-6a3c732f2ea6 | translations.uk.answer, translations.uk.question |
| faq_items | 822fd461-7ba5-44ee-84c8-c728cf085656 | translations.uk.answer, translations.uk.question |
| faq_items | 8e69d06c-f810-46e9-980f-fa69865d25af | translations.uk.answer, translations.uk.question |
| faq_items | 90382ead-fb70-4aed-9379-3d2cb872dda5 | translations.uk.answer, translations.uk.question |
| faq_items | 921f40e1-9bfd-4a5e-b8a4-b6afcb7f5b94 | translations.uk.answer, translations.uk.question |
| faq_items | 9446abc2-3308-484f-b255-bc425f3d3d52 | translations.uk.answer, translations.uk.question |
| faq_items | 9c44529e-7fa6-4f8b-a635-1ab9de7b1986 | translations.uk.answer, translations.uk.question |
| faq_items | b0f644e0-643d-495f-b6db-7a752c02cbeb | translations.uk.answer, translations.uk.question |
| faq_items | bc998060-a598-433c-acc3-f0f03c32ca14 | translations.uk.answer, translations.uk.question |
| faq_items | c4bdc76c-4037-488b-a46d-7e15c3697664 | translations.uk.answer, translations.uk.question |
| faq_items | d2051db9-f4d6-4d24-9009-c3df6be6fd45 | translations.uk.answer, translations.uk.question |
| faq_items | d87bbb0e-0cc1-43a0-9cc4-9a2dc3118aac | translations.uk.answer, translations.uk.question |
| faq_items | dd96d6c9-3b64-47b1-94aa-e9848d7777ac | translations.uk.answer, translations.uk.question |
| faq_items | e9d26f91-d0b8-4578-b586-f581d95cc67a | translations.uk.answer, translations.uk.question |
| faq_items | eb9da018-552b-4c67-a224-e7b116c0c55f | translations.uk.answer, translations.uk.question |
| faq_items | ee1a5c2f-6eea-4db3-b012-b4d3d01ce0b6 | translations.uk.answer, translations.uk.question |
| faq_items | fe21099d-7b78-4eb6-bfb7-78e854e8ba0a | translations.uk.answer, translations.uk.question |

Skipped (NOTICE): none

### u10: 20 changed fields in 5 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| motorcycles | 4570ce0f-a8e1-4981-bf69-20eed8a45323 | translations.pl.features |
| motorcycles | 6071c49d-8019-415e-a9d9-ef23c7ec88a6 | translations.de.features, translations.en.features, translations.es.features, translations.fr.features, translations.nl.features, translations.pl.features, translations.uk.description, translations.uk.features |
| motorcycles | a0000001-0000-0000-0000-000000000008 | translations.de.features |
| motorcycles | a0000001-0000-0000-0000-000000000012 | translations.de.features, translations.en.features, translations.es.features, translations.fr.features, translations.nl.features, translations.pl.features, translations.uk.description, translations.uk.features |
| motorcycles | e3123fff-5ecc-486b-9481-fb5eebc11fdf | translations.de.features, translations.pl.features |

Skipped (NOTICE): none

### u11: 36 changed fields in 10 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| cms_variables | web.jak_pujcit_dokumenty.payments.rows.4.1 | translations.nl.value |
| cms_variables | web.kontakt.address | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value |
| cms_variables | web.kontakt.billing.addr | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value |
| cms_variables | web.kontakt.seo_text.body | translations.nl.value |
| cms_variables | web.layout.editRez.loc.atRental | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value |
| cms_variables | web.layout.editRez.reset.otpHelp | translations.nl.value |
| cms_variables | web.layout.rez.pickup.deliveryTip | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value |
| cms_variables | web.layout.rez.pickup.returnTip | translations.de.value, translations.en.value, translations.es.value, translations.fr.value, translations.nl.value, translations.pl.value |
| motorcycles | 6071c49d-8019-415e-a9d9-ef23c7ec88a6 | translations.nl.description |
| motorcycles | a0000001-0000-0000-0000-000000000006 | translations.nl.description, translations.nl.features |

Skipped (NOTICE): none

### u12: 3 changed fields in 1 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| cms_pages | c84d8e65-eb6e-4bd8-bf11-cf3256ae3dd0 | translations.nl.content, translations.nl.excerpt, translations.nl.title |

Skipped (NOTICE): none

### u13: 3 changed fields in 1 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| cms_variables | web.layout.editRez.h1 | translations.de.value, translations.es.value, translations.nl.value |

Skipped (NOTICE): none

### u14: 1 changed fields in 1 rows

| table | row (key / id / slug) | changed fields |
|---|---|---|
| cms_pages | 5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc | slug |

Skipped (NOTICE): none

