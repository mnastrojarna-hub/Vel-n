# MotoGo24 — Backend (Supabase)

## Struktura

```
backend/
├── supabase/
│   ├── migrations/          # Jednotlivé SQL migrace (001–013)
│   │   ├── 001_base_schema.sql       # Základní tabulky, funkce, RLS
│   │   ├── 002_sos_system.sql        # SOS / Incident systém
│   │   ├── 003_pricing_extras.sql    # Cenotvorba, extras, push tokeny
│   │   ├── 004_inventory.sql         # Sklad, dodavatelé, objednávky
│   │   ├── 005_maintenance.sql       # Servis a údržba motorek
│   │   ├── 006_messaging.sql         # Omnichannel messaging
│   │   ├── 007_accounting.sql        # Účetnictví, faktury, daně
│   │   ├── 008_documents_templates.sql # Šablony dokumentů
│   │   ├── 009_cms.sql               # CMS, promo kódy, feature flags
│   │   ├── 010_analytics.sql         # Analytika, výkonnost, predikce
│   │   ├── 011_notifications.sql     # Notifikace a automatizace
│   │   ├── 012_ai_integration.sql    # AI asistent integrace
│   │   └── 013_admin_roles.sql       # Admin role + RLS na vše
│   ├── FULL_MIGRATION.sql   # Kompletní DB v jednom souboru (copy-paste)
│   └── seed.sql              # Produkční seed data
├── .env.example              # Šablona environment proměnných
└── README.md                 # Tento soubor
```

## Spuštění migrací

### Varianta A: Jeden soubor (doporučeno pro první setup)

1. Otevřete Supabase Dashboard → SQL Editor
2. Otevřete soubor `supabase/FULL_MIGRATION.sql`
3. Ctrl+A → Ctrl+C → vložte do SQL Editoru
4. Klikněte **Run**

### Varianta B: Postupně (pro vývoj)

Spusťte migrace v pořadí 001–013, pak seed:

```bash
# Pomocí Supabase CLI
supabase db push

# Nebo manuálně v SQL Editoru — postupně kopírujte 001, 002, ..., 013, seed.sql
```

### Varianta C: Supabase CLI

```bash
cd backend
cp .env.example .env
# Vyplňte .env

supabase init
supabase link --project-ref <YOUR_PROJECT_REF>
supabase db push
```

## Environment proměnné

Zkopírujte `.env.example` do `.env` a vyplňte:

- **SUPABASE_URL** — URL vašeho Supabase projektu
- **SUPABASE_ANON_KEY** — Anonymní klíč (pro frontend)
- **SUPABASE_SERVICE_ROLE_KEY** — Service role klíč (pro backend)
- **ANTHROPIC_API_KEY** — API klíč pro Claude AI asistenta
- **STRIPE_SECRET_KEY** — Stripe platby

## Seed data

Seed obsahuje:

- 2 pobočky (Mezná, Brno)
- 14 motorek z reálného katalogu
- 16 extras (helmy, bundy, kufry, GPS)
- 4 pricing pravidla (sezóna, long-term, promo)
- 4 promo kódy
- 1 superadmin (admin@motogo24.cz)
- CMS proměnné, feature flags, notification rules, document templates
