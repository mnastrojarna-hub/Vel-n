# owner-webtexts (2026-10-11) — return rule + FAQ app stores + home step 3 (FILES only)

Rule applied: Mezná (staffed) + delivery/return elsewhere = no wash, no refuel (reserve-light sentence REMOVED there);
Velké Němčice (self-service) = no full tank needed, but WASHED + reserve light NOT on.

## Files changed (47, all php -l OK, key paths identical except +1 compare row in pobocky v2 for all 8 langs)
- data/landing-trust.php (header comment + reason "Vracíš, jak ti to vyhovuje"), lang/v2/{en,de,es,fr,nl,pl,uk}/landing.php (same reason)
- data/vraceni-pujcovna-content-2.php, data/vraceni-jinde-content-2.php (FAQ 1 answer), data/dokumenty-content-1.php (payments row Palivo&čištění),
  data/dokumenty-content-2.php (handover item 3), data/postup-content-1.php (step 12) + same keys in lang/pages_{cs,en,de,es,fr,nl,pl,uk}.php
- pages/pujcovna.php + lang/pages_*.php pujcovna.faq.items.0.a (app on Google Play (Android) AND App Store (iPhone))
- pages/home.php + lang/pages_*.php home.process.steps.2.text (Mezná osobně/přistavení + samoobsluha Velké Němčice)
- lang/{cs,en,de,es,fr,nl,pl,uk}.php rez.return.stateText (not rendered; only in /rezervace i18n JSON)
- data/pobocky.php + lang/v2/*/pobocky.php: Mezná step 4 (+ no wash/refuel), VN step 6 (+ washed, reserve off, no full tank)
- pages/pobocky-v2-texts.php + lang/v2/*/pobocky-v2.php: NEW compare row "Vrácení motorky" after "Přistavení na adresu"
- Unchanged on purpose: landing-info chips 'Bez tankování' (vraceni_pujcovna = Mezná page), vraceni_pujcovna intro/cta (Mezná), pristaveni step 10 (delivery = Mezná)

## Live DB rows that still override files (for SQL workstream)
cms_variables (highest priority):
- web.jak_pujcit_dokumenty.payments.rows.2.1 cs+de,en,es,fr,nl,pl "Vrácení bez povinnosti dotankovat a mýt." -> CONTRADICTS (self-service). Use file text.
- web.jak_pujcit_postup.process.steps.11.text cs+7 langs: Mezná/agreed place, no wash/refuel -> consistent but omits VN; suggest + "Na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy."
- web.pujcovna.faq.items.0.a (Google Play only), web.home.process.steps.2.text (Mezná only) -> dbsql (a),(b)
- web.pobocky.branches.1.steps / branches.0.steps (CS only, no translations) -> CS VN page has no rule; suggest same sentences as data/pobocky.php
app_settings pages_overlay.<page>.<lang> (en,de,es,fr,nl,pl; no uk) override lang/pages_<lang>.php:
- jak_pujcit_vraceni_pujcovna.*.faq.items.1.a ("with us no refuel/wash, just reserve") -> CONTRADICTS
- jak_pujcit_vraceni_jinde.*.faq.items.1.a (reserve light at return elsewhere) -> per rule no refuel at Mezná service
- jak_pujcit_dokumenty.*.handover.items.2 ("no need to wash or refuel") -> CONTRADICTS (self-service)
- jak_pujcit_dokumenty.*.payments.rows.2.1, jak_pujcit_postup.*.process.steps.11.text (masked by cms_variables), pujcovna.*.faq.items.0.a, home.*.process.steps.2.text
  -> update with jsonb_set (do NOT #- array elements: lists merge by index)
faq_items:
- e6df7d9f "Musím vracet s plnou nádrží a čistou?" all langs, NO uk (Czech shown on UK FAQ) -> CONTRADICTS (self-service)
- 02b6cfc8 "Jaké palivo mám tankovat?" ... "jen ať nesvítí kontrolka rezervy" generic, NO uk -> reserve requirement only for VN
Other files (not in my list): pages/blog_fallback.php:52 "Nemusíte tankovat ani mýt" (generic), .well-known/agent.json:100-101,138 (generic "bez povinnosti dotankovat/mýt"),
velin/src/pages/cms/webTextsPobocky.js (mirror of data/pobocky.php steps; now drifts by the 2 added sentences).

## Open questions for owner
1. Mezná: must the reserve light be off there too? (old FAQ said so; new rule lists reserve only for self-service -> removed at Mezná/return elsewhere)
2. VOP čl. 5 l) still "bez mytí" for both branches (legal doc; owner edits in Velín)
3. OK to keep the new comparison row on /pobocky?

## QA review (adversarial, 2026-10-11) — fixes applied in files
- lang/de.php rez.return.stateText: "volltanken ist" -> "Volltanken ist" (noun)
- lang/v2/de/landing.php fuel card: "gewaschen und ohne leuchtende Reserve, volltanken nicht nötig" -> "gewaschen, Reserveleuchte aus, Volltanken nicht nötig"
- lang/v2/de/pobocky-v2.php compare row: "volltanken" -> "Volltanken"
- lang/v2/es/pobocky-v2.php compare row: "sin depósito lleno" (ambiguous: reads as "must not be full" and clashes with "sin depósito" = no deposit) -> "no hace falta el depósito lleno"
- lang/pl.php stateText + lang/pages_pl.php postup step 11 (jak_pujcit_postup.process.steps.11.text): "oddaj go umytego" -> "oddaj motocykl umyty"
  !! SQL m3a_owner_texts.sql pages_overlay row (jak_pujcit_postup, pl, {process,steps,11,text}) still carries the old "oddaj go umytego" text -> dbsql should copy the new file text.
- vraceni-pujcovna CTA fallback aligned with SQL cms row (generic "bez mytí" was wrong for VN): data/vraceni-pujcovna-content-2.php + lang/pages_cs.php "Bez kauce, bez tankování, v Mezné i bez mytí."; lang/pages_uk.php "Без застави, без заправки, а в Mezná ще й без миття." (en/de/es/fr already scoped to Pelhřimov; nl/pl have no wash claim). CS render unchanged (CMS overrides).
Verified: php -l 47 files OK; key paths identical vs base (only +compare row, all 8 langs same shape); render diff base vs base+webtexts (14 pages x 8 langs, ports 8105/8106): only intended sentences; no new horizontal overflow/clipping at 320/390/768/1366 (pre-existing 320px overflow de/nl/uk = compare-table header + header tools, same in base); reviews untouched.
Gap not covered by SQL draft: cms web.pobocky.branches.{0,1}.steps (CS only) — CS branch pages show no return rule; velin/src/pages/cms/webTextsPobocky.js mirror lacks the 2 new sentences.
