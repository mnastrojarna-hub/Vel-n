# Denní zálohování MotoGo24

Workflow `.github/workflows/daily-backup.yml` běží **každý den v 6:00 ráno (Europe/Prague)** a zálohuje:

| Co | Jak | Soubor v archivu |
|----|-----|------------------|
| Git repozitář (všechny větve + tagy) | `git bundle --all` | `git-repo.bundle` |
| DB role + grants | `supabase db dump --role-only` | `db/roles.sql` |
| DB schema (public) | `supabase db dump --schema public` | `db/schema_public.sql` |
| DB schema (auth, storage) | `supabase db dump --schema auth,storage` | `db/schema_system.sql` |
| **100 % dat public schématu** (všech ~98 tabulek) | `supabase db dump --data-only --use-copy` | `db/data_public.sql` |
| **Data auth** (uživatelé, identity, hesla-hash) + storage metadata | dtto pro auth,storage | `db/data_system.sql` |
| **Všechny soubory ve Storage** (documents, media, sos-photos) | `backup/storage-backup.mjs` (service_role) | `storage/<bucket>/...` |

Vše se zabalí do `motogo24-backup-YYYY-MM-DD.tar.gz.gpg` — **šifrováno GPG AES256**
(archiv obsahuje osobní údaje zákazníků, skeny dokladů atd. → GDPR).

## Kam se záloha ukládá

**Zatím:** GitHub Actions artifact s retencí **30 dní** (Actions → běh workflow → Artifacts).

**Až bude rozhodnuto cílové úložiště**, v workflow se odkomentuje jeden z připravených kroků:
- **Varianta A:** S3-kompatibilní (AWS S3, Backblaze B2, Cloudflare R2, Wasabi)
- **Varianta B:** rclone (Google Drive, OneDrive, SFTP, NAS, …)

## Potřebné GitHub secrets (nutno nastavit ručně!)

Settings → Secrets and variables → Actions → Repository secrets:

| Secret | Hodnota |
|--------|---------|
| `SUPABASE_DB_URL` | `postgresql://postgres:<DB_HESLO>@db.vnwnqteskbykeucanlhk.supabase.co:5432/postgres` (Dashboard → Project Settings → Database → Connection string) |
| `SUPABASE_URL` | `https://vnwnqteskbykeucanlhk.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | service_role klíč (Dashboard → Settings → API) |
| `BACKUP_PASSPHRASE` | silné heslo pro šifrování archivu — **ulož si ho bezpečně mimo GitHub**, bez něj zálohu nelze rozbalit |

## Obnova ze zálohy

```bash
# 1. Dešifrovat a rozbalit
gpg --batch --passphrase '<BACKUP_PASSPHRASE>' -d motogo24-backup-2026-06-10.tar.gz.gpg | tar -xz

# 2. Git repozitář
git clone git-repo.bundle obnoveny-repo

# 3. Databáze (do prázdného/nového Supabase projektu)
psql "$NEW_DB_URL" -f db/roles.sql
psql "$NEW_DB_URL" -f db/schema_public.sql
psql "$NEW_DB_URL" -f db/data_public.sql
# auth data: db/data_system.sql (pozor — vyžaduje shodné instance_id, řešit s podporou Supabase)

# 4. Storage soubory — nahrát zpět přes supabase CLI nebo Storage API
```

## Ruční spuštění

Actions → „Denni kompletni zaloha (Supabase + git)" → Run workflow.

## Poznámky

- Dva cron časy (4:00 + 5:00 UTC) + guard krok řeší letní/zimní čas — reálně proběhne jen běh odpovídající 6:00 Praha.
- Supabase **Secrets** (API klíče edge funkcí) nelze přes API exportovat — jsou zdokumentované v `SUPABASE_BACKEND_STATE_5.md` a je nutné je držet i v password manageru.
- Edge funkce a migrace jsou v gitu (`supabase/`), takže je pokrývá git bundle.
