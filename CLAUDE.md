# MotoGo24 — Claude Code Instructions

## POVINNÉ: Přečti backend state na začátku každé session

**VŽDY na začátku KAŽDÉ konverzace / session přečti soubory:**

```
/SUPABASE_BACKEND_STATE_1.md  — Tabulky
/SUPABASE_BACKEND_STATE_2.md  — Klíčové sloupce
/SUPABASE_BACKEND_STATE_3.md  — RPC funkce
/SUPABASE_BACKEND_STATE_4.md  — Triggery
/SUPABASE_BACKEND_STATE_5.md  — RLS, Realtime, Edge, Storage, Secrets, Cron, FK
/SUPABASE_BACKEND_STATE_6.md  — Changelog
```

Tyto soubory obsahují kompletní stav Supabase backendu — všechny tabulky, sloupce, RLS politiky, edge funkce, secrets, triggery a RPC funkce. BEZ tohoto kontextu NESMÍŠ provádět žádné frontendové ani backendové změny.

## Architektura projektu

Toto je soustava propojených aplikací pro MotoGo24 (půjčovna motorek):

- **motogo-app-flutter/** — Mobilní appka pro zákazníky (codemagic build)
- **velin/** — Velín = superadmin dashboard (React 18 + Vite + TailwindCSS)
- **supabase/** — Backend: Edge Functions + SQL migrace

## Pravidla

1. **NIKDY neměň UX, UI ani flow** pokud to uživatel výslovně nepožaduje
2. **pro celý repozitář:** Maximálně 5000 tokenů na soubor pokud je to technicky možné a neomezí to funkčnost.
3. **SQL změny:** Vždy dej SQL příkazy jako text do chatu, NIKDY rovnou do gitu. Až po implementaci a ověření commitni
4. **SUPABASE_BACKEND_STATE_*.md:** Po každé SQL změně MUSÍŠ aktualizovat příslušný soubor (1-6)
5. **Backend first:** Před každou frontendovou změnou ověř, že backend (tabulky, RLS, funkce) podporuje požadovanou funkcionalitu

## Supabase kontext

- Projekt: MotoGo24
- Region: (ověřit v dashboardu)
- Email služba: Resend (noreply@motogo24.cz)
- Platby: real stripe funkční
- Firma: Bc. Petra Semorádová, IČO: 21874263
- Kontakt: +420 774 256 271, info@motogo24.cz

## Git workflow

- Vždy pracuj na větvi začínající `claude/`
- Commit message česky nebo anglicky dle kontextu
- Před pushem ověř, že branch name odpovídá session
