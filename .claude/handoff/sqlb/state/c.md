# STATE patch — skupina c (hodnocení jízd + zprávy), migrace 20261112c01–c03

## SUPABASE_BACKEND_STATE_1.md (Tabulky) — nový řádek tabulky
| `booking_rating_reviews` | **NEW 2026-11-12 (`20261112c01_velin_rating_handled.sql`, APLIKUJE AUTO-DEPLOY po merge)** — Velín → Zprávy → Hodnocení: sdílené „✓ Vyřízeno“ u hodnocení jízdy (`bookings.rating`) BEZ psaní zákazníkovi (zadání majitele 2026-10-15). 1 řádek / rezervace: PK `booking_id` FK→bookings CASCADE, `handled_at` (NOT NULL DEFAULT now()), `handled_by` FK→admin_users SET NULL (vždy doplní trigger = přihlášený admin), `rated_at_seen` (= `bookings.rated_at` v okamžiku označení; změní-li zákazník hvězdičky, Velín značku ignoruje), `note` (≤ 2000 znaků, Velín zatím nepoužívá). Jen admin (RLS `is_admin()`), anon bez práv; realtime. Velín (`messages/useRatings.js`, `ratingsFetch.js`) tabulku pozná sám dotazem (dokud chybí → localStorage) a lokální značky po nasazení jednorázově převede (upsert `ignoreDuplicates`). Soukromý text „Napiš nám přímo, co máme zlepšit“ jde do zákazníkova chatu (`message_threads`/`messages`, předmět se značkou `#XXXXXXXX`), NIKDY do veřejné `reviews`. |

## SUPABASE_BACKEND_STATE_2.md (Klíčové sloupce)
V sekci `bookings` nahradit řádek `- **rating, rated_at** — hodnocení zákazníkem` tímto:
- **rating, rated_at** — hodnocení jízdy zákazníkem (rating 1–5, zapisuje appka přímo UPDATE; Velín → Zprávy → Hodnocení). **2026-11-12 (`20261112c02_booking_rating_guard.sql`):** u zákaznického JWT nastavuje `rated_at` = `now()` SERVERU při změně hvězdiček (NULL při smazání), samotná změna `rated_at` se zahodí; hodnocení zrušené rezervace nebo jízdy, jejíž konec (datum Praha) je až po dnešku a není `completed`/`ended_by_sos`, se tiše zahodí (bez chyby). Admin / service role beze změny. Appka 4.1.3 posílala místní čas bez zóny (posun 1–2 h) — od nasazení irelevantní.

Nová sekce:
### booking_rating_reviews (NEW 2026-11-12, `20261112c01_velin_rating_handled.sql`)
- **booking_id** (UUID PK, FK→bookings ON DELETE CASCADE)
- **handled_at** (TIMESTAMPTZ NOT NULL DEFAULT now()) — kdy obsluha označila vyřízeno (Velín posílá svůj čas; NULL → trigger doplní now())
- **handled_by** (UUID DEFAULT auth.uid(), FK→admin_users ON DELETE SET NULL) — přepisuje trigger `trg_booking_rating_reviews_stamp` na `auth.uid()` (kromě akce cizího klíče SET NULL po smazání admina — ta zůstane NULL)
- **rated_at_seen** (TIMESTAMPTZ) — `bookings.rated_at` v okamžiku označení; značka platí jen dokud se rovná aktuálnímu `rated_at`
- **note** (TEXT, CHECK ≤ 2000 znaků)

V sekci `message_threads` / `messages` doplnit:
- **message_threads.last_message_at** — **2026-11-12 (`20261112c03`):** posouvá ho i trigger `trg_messages_bump_thread` po KAŽDÉ nové zprávě (jen dopředu, nejdál na now(); status vlákna se nemění) — zákaznický `update last_message_at` z appky dál tiše nic nedělá (bez UPDATE politiky), už není potřeba.

## SUPABASE_BACKEND_STATE_3.md (RPC funkce)
Žádná nová RPC. (Nové funkce jsou jen triggerové: `_booking_rating_reviews_stamp()`, `_bookings_rating_guard()`, `_messages_bump_thread()` — viz STATE_4; EXECUTE jen postgres + service_role.)

## SUPABASE_BACKEND_STATE_4.md (Triggery) — nová podsekce
### Hodnocení jízd a zprávy (2026-11-12, `20261112c01…c03`, APLIKUJE AUTO-DEPLOY po merge)
| Trigger | Tabulka | Funkce |
|---|---|---|
| `trg_booking_rating_reviews_stamp` | booking_rating_reviews (BEFORE INSERT OR UPDATE) | `_booking_rating_reviews_stamp()` — `handled_by := auth.uid()` (je-li; při UPDATE ne, když se `handled_by` mění z hodnoty na NULL = akce FK ON DELETE SET NULL, jinak by se značky smazaného admina připsaly mazajícímu a smazání vlastního admin účtu se značkami by spadlo na FK), `handled_at` NULL → now(). SECURITY INVOKER, `search_path = public, pg_temp`, EXECUTE jen postgres/service_role. |
| `trg_bookings_rating_guard` | bookings (BEFORE UPDATE OF rating, rated_at) | `_bookings_rating_guard()` — jen zákaznický JWT (ne `auth.uid() IS NULL`, ne `is_admin()`): změna `rating` u zrušené / ještě neskončené jízdy (dle PŮVODNÍHO řádku OLD — zákazník ho týmž zápisem nezmění; skončená = `completed` NEBO `ended_by_sos` NEBO datum konce (Praha) ≤ dnešek (Praha) — zrcadlo appky `ResStatus.dokoncene` s rezervou o den) → `rating`/`rated_at` zůstanou původní; jinak změna `rating` → `rated_at = now()` (NULL při smazání); změna jen `rated_at` → zahozena. Nic nevyhazuje. SECURITY INVOKER, `search_path = public, pg_temp`, EXECUTE jen postgres/service_role. Jméno řadí trigger mezi BEFORE triggery bookings za `bookings_updated_at` a před `trg_check_*`; žádný jiný BEFORE trigger rating/rated_at nečte ani nemění. |
| `trg_messages_bump_thread` | messages (AFTER INSERT, FOR EACH ROW) | `_messages_bump_thread()` — SECURITY DEFINER, `search_path = public, pg_temp`: `message_threads.last_message_at := LEAST(COALESCE(NEW.created_at, now()), now())`, jen když je novější (jen dopředu; budoucí `created_at` od klienta vlákno nepřipíchne nahoru); status vlákna se NEMĚNÍ. Chyba → WARNING, zpráva se uloží vždy. Běží po `trg_bridge_admin_message` (abecedně), nezávislý na něm. EXECUTE jen postgres/service_role. |

## SUPABASE_BACKEND_STATE_5.md (RLS, Realtime, …)
RLS — nahradit řádek `message_threads`:
- **message_threads:** admin ALL, customer SELECT/INSERT (customer_id=uid). Customer UPDATE politika živě NEEXISTUJE (záměrně) — `last_message_at` po zprávě zákazníka posouvá od 2026-11-12 SECURITY DEFINER trigger `trg_messages_bump_thread` na `messages` (`20261112c03`, STATE_4).

RLS — nový řádek:
- **booking_rating_reviews (NEW 2026-11-12, `20261112c01`):** RLS zapnuto, politika `booking_rating_reviews_admin_all` FOR ALL TO authenticated USING/WITH CHECK `is_admin()`. Práva: REVOKE ALL od PUBLIC/anon/authenticated, GRANT SELECT/INSERT/UPDATE/DELETE authenticated, ALL service_role. Zákazník ani anon nevidí nic.

Realtime — přidat do seznamu (sekce 7):
- `booking_rating_reviews` (**NEW 2026-11-12** — `20261112c01_velin_rating_handled.sql`, guard `pg_publication_tables` (EXCEPTION → WARNING): Velín → Zprávy → Hodnocení (`useRatings.js`, kanál `velin-ratings-handled`, jen když tabulka existuje) — odznak a záložka u ostatních adminů se obnoví hned po „Vyřízeno“; RLS pustí jen admina).

FK — přidat:
- `booking_rating_reviews.booking_id` → `bookings.id` (ON DELETE CASCADE)
- `booking_rating_reviews.handled_by` → `admin_users.id` (ON DELETE SET NULL)

Edge / Storage / Secrets / Cron: beze změny.

## SUPABASE_BACKEND_STATE_6.md (Changelog) — nový řádek
| 2026-11-12 (`20261112c01_velin_rating_handled.sql`, `20261112c02_booking_rating_guard.sql`, `20261112c03_messages_bump_thread.sql`, APLIKUJE AUTO-DEPLOY po merge) | **Hodnocení jízd → Velín (zadání majitele 2026-10-15: hodnocení vede na recenzi Google, „Napiš nám přímo, co máme zlepšit“ jde do Velínu → Zprávy → Hodnocení).** c01: nová admin-only tabulka `booking_rating_reviews` (sdílené „✓ Vyřízeno“ bez psaní zákazníkovi; `rated_at_seen` = platnost značky; `handled_by` doplní trigger; RLS `is_admin()`, anon nic; realtime) — Velín ji pozná sám a lokální značky z prohlížeče převede. c02: trigger `trg_bookings_rating_guard` — zákazník hodnotí jen skončenou nezrušenou jízdu (jinak tiše beze změny), `rated_at` = čas serveru, samotné `rated_at` nepřepíše; admin/service role beze změny, appky beze změny (žádná chyba). c03: trigger `trg_messages_bump_thread` (SECURITY DEFINER) posune `message_threads.last_message_at` po každé nové zprávě (jen dopředu, nejdál na now(), status beze změny) — zpráva zákazníka do staršího vlákna už nezůstane ve Velínu dole. Žádná existující funkce, trigger ani politika se nemění; FAQ/`trg_notify_ride_completed`/`notify_booking_completed_email` záměrně beze změny (návrhy DRAFT/OPTIONAL z 2026-10-15 nenasazeny); starší INSERT politika `Users and admins can send messages` na `messages` beze změny (návrh QA 20261016a mimo bundle). |
