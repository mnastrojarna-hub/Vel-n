# STATE patch — skupina d (barvy ranků) — NEPOUŽÍT, dokud 20261112d01 není v supabase/migrations

Soubor `20261112d01_loyalty_colors_ramp.sql` NENÍ součástí bundle (snížení kontrastu ve starém vzhledu,
appce 4.1.3 a oslavě level-upu — viz c/regression.md). Teprve až ho majitel schválí a orchestrátor ho
přidá, doplnit:

## SUPABASE_BACKEND_STATE_1.md
Řádek `loyalty_levels`: za „color_hex [barva ringu MG loga v appce]“ doplnit „(**2026-11-12 `20261112d01`:** škála designu v2.2 — 1–5 zelené, 6–9 kovy, 10–16 modré, 17–19 VIP, 20 ohnivé zlato `#FF8C1A`; bez fialové/růžové)“.

## SUPABASE_BACKEND_STATE_2.md
V sekci `loyalty_levels` řádek `name`/`color_hex` doplnit:
- **color_hex** — **2026-11-12 (`20261112d01_loyalty_colors_ramp.sql`, zadání majitele 2026-10-15/16):** nová škála 1 `#A3B8A8` · 2 `#BDF6D1` · 3 `#4ADE80` · 4 `#00AC7F` · 5 `#0AA2A4` · 6 `#C2844A` · 7 `#929496` · 8 `#E5D376` · 9 `#B9BEC6` · 10 `#AEE9FF` · 11 `#2CD1D4` · 12 `#6EAFFF` · 13 `#00A1C7` · 14 `#5087D4` · 15 `#117897` · 16 `#165EEB` · 17 `#D42020` · 18 `#EDB42D` · 19 `#F5F8FB` · 20 `#FF8C1A` (CIEDE2000 každá dvojice ≥ 12,38; dřív 8 = 20 = `#FFD700`). UPDATE jen řádků s původní barvou (ručně změněná barva ve Velínu zůstává). Appka v2 mapuje staré i nové hodnoty na stejnou škálu sama (`core/v2/rank/rank_palette.dart`).

## SUPABASE_BACKEND_STATE_3/4/5
Beze změny (jen data; `get_loyalty_status` / `admin_loyalty_status` / žebříček vrací `color_hex` z tabulky beze změny tvaru).

## SUPABASE_BACKEND_STATE_6.md — nový řádek
| 2026-11-12 (`20261112d01_loyalty_colors_ramp.sql`, APLIKUJE AUTO-DEPLOY po merge) | **Barvy věrnostních ranků podle designu v2.2** (zadání majitele 2026-10-15 „žádná růžová ani fialová“ + 2026-10-16 „zelený → modrý → kovy, aby si ranky nebyly podobné“): `loyalty_levels.color_hex` 19 řádků (rank 3 beze změny), jen tam, kde je pořád původní barva; kontrolní NOTICE vypíše odchylky a duplicitní barvy, nasazení nepadá. Slevy, prahy, názvy, překlady ani ranky zákazníků beze změny. Appka v2 beze změny vzhledu (mapuje sama); mění se starý vzhled, appka 4.1.3 a oslava level-upu. |
