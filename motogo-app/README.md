# MotoGo24

Platforma na pronajem motorek — mobilni app, web, admin panel.

## Struktura

- `frontend/` — mobilni app (PWA + Capacitor iOS/Android)
- `backend/` — Supabase backend (DB, auth, storage, edge functions)

## Quick Start

1. Otevri `backend/setup.html` → vyplnit API klice
2. Nahraj migrace do Supabase (SQL Editor nebo `supabase db push`)
3. `cd frontend && npm install && bash build.sh`

Kompletni navod: [backend/DEPLOYMENT.md](backend/DEPLOYMENT.md)

## Tech Stack

- **Frontend**: Vanilla JS, CSS, Capacitor 6
- **Backend**: Supabase (PostgreSQL, Auth, Storage, Edge Functions)
- **AI**: Claude (Anthropic) — admin copilot
- **Platby**: Stripe
- **Hosting**: Supabase Cloud (eu-central-1)

## Funkce

- Katalog motorek s fotogalerií a cenikem
- Online rezervace s kalendarem
- SOS system pro nehody a poruchy
- Platby pres Stripe
- Admin panel s AI copilotem (Velin)
- Automaticke emaily, SMS, WhatsApp notifikace
- Fakturace, ucetnictvi, danove exporty
- CMS pro dynamicky obsah
- Prediktivni analytika (AI)
- Export dat (CSV, PDF)

## Licence

Proprietary — MotoGo24 s.r.o.
