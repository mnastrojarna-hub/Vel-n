import re, pathlib
D = pathlib.Path('/home/user/Vel-n/.claude/handoff/sql-paydec')
O = pathlib.Path('/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb/a/final')
H = pathlib.Path('/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb/a/headers')

def body(name, hdr_end):
    lines = (D / name).read_text().split('\n')
    return '\n'.join(lines[hdr_end:])

def sub1(s, old, new):
    assert s.count(old) == 1, (old[:60], s.count(old))
    return s.replace(old, new)

# a01
b = body('20261016p1_card_rounding.sql', 53)
start = b.index('-- ── 3) KF: řádek dorovnání')
end = b.index('CREATE OR REPLACE FUNCTION public.generate_final_invoice_on_complete()')
b = b[:start] + ('-- ── 3) KF: řádek dorovnání ───────────────────────────────────────────────────\n'
 '-- Tělo = živá DB 2026-11-12 (vč. větve výpůjčky jen výbavy „GEAR 20261023db“, která zůstává beze změny);\n'
 '-- nové jsou jen řádky označené „D1“ (dorovnání se odečte od základu pronájmu a ukáže se samostatným\n'
 '-- řádkem, součet KF proti DP a dobropisům dál vychází na 0 — platí i pro výbavu).\n') + b[end:]
(O / '20261112a01_card_rounding.sql').write_text((H / 'a01.txt').read_text() + b)

# a02
b = body('20261016p2_customer_restore.sql', 69)
b = sub1(b, """  IF p_b.start_date IS NULL OR p_b.start_date::date <= v_today THEN
    RETURN jsonb_build_object('error', 'date_passed');
  END IF;""", """  IF p_b.start_date IS NULL OR p_b.start_date::date <= v_today THEN
    -- 2026-11-12: reason 'today' = začíná dnes (appka má pro to vlastní text pdRestoreStartsToday)
    RETURN jsonb_build_object('error', 'date_passed',
      'reason', CASE WHEN p_b.start_date::date = v_today THEN 'today' ELSE 'past' END);
  END IF;""")
b = sub1(b, """  -- Zaplacená / vrácená (storno s vratkou), převzatá nebo SOS náhrada → jen Velín.
  IF p_b.payment_status IS DISTINCT FROM 'unpaid' OR p_b.picked_up_at IS NOT NULL
     OR COALESCE(p_b.sos_replacement, false) THEN""", """  -- Zaplacená / vrácená (storno s vratkou), převzatá nebo SOS náhrada → jen Velín.
  -- 2026-11-12: výpůjčka jen výbavy (booking_kind 'gear', od 20261023a) také jen Velín — kontrola
  -- ceny níže počítá ceník motorky, cenu výbavy by neověřila (gear se pozná VÝHRADNĚ podle booking_kind).
  IF p_b.payment_status IS DISTINCT FROM 'unpaid' OR p_b.picked_up_at IS NOT NULL
     OR COALESCE(p_b.sos_replacement, false)
     OR p_b.booking_kind IS NOT DISTINCT FROM 'gear' THEN""")
(O / '20261112a02_customer_restore.sql').write_text((H / 'a02.txt').read_text() + b)

# a03
b = body('20261016p3_swap_card_rounding.sql', 54)
i = b.index('-- -----------------------------------------------------------------------------\n-- S3b')
j = b.index('NOTIFY pgrst')
b = b[:i] + b[j:]
(O / '20261112a03_swap_card_rounding.sql').write_text((H / 'a03.txt').read_text() + b)

# a04
b = body('20261016p4_gear_rounding_modified_mail.sql', 63)
b = sub1(b, '-- ── 2) update_booking_gear: tělo 1:1 se živou DB, nové řádky „D1 20261016p4" ─────',
            '-- ── 2) update_booking_gear: tělo = živá DB 2026-11-12, nové řádky „D1 20261016p4" ─')
(O / '20261112a04_gear_rounding_modified_mail.sql').write_text((H / 'a04.txt').read_text() + b)
print('ok')
