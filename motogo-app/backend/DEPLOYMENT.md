# MotoGo24 — Deployment navod

Kompletni navod na nasazeni MotoGo24 platformy. Krok za krokem, od nuly do produkce.

---

## Predpoklady

- **Node.js 18+** (pro Supabase CLI a Capacitor)
- **Ucet na [supabase.com](https://supabase.com)** (zdarma pro zacatek)
- (Volitelne) Stripe ucet pro online platby
- (Volitelne) Apple Developer / Google Play Console pro app stores
- (Volitelne) SMTP ucet pro emaily (Gmail App Password staci)

---

## Krok 1: Supabase projekt (5 minut)

1. Jdi na [supabase.com](https://supabase.com) → **New Project**
2. Vyber region **eu-central-1 (Frankfurt)** — nejbliz CR
3. Zadej nazev projektu (napr. `motogo24-prod`)
4. Vygeneruj si silne heslo pro databazi a uloz ho
5. Pockej az se projekt vytvori (~2 minuty)
6. Jdi do **Settings → API** a zapis si:
   - **Project URL** (napr. `https://xxxxx.supabase.co`)
   - **anon (public) key** (zacina `eyJ...`)
   - **service_role key** (zacina `eyJ...`) — NIKDY na frontend!

---

## Krok 2: API klice (10 minut)

1. Otevri `backend/setup.html` v prohlizeci (staci dvojklik)
2. Vyplnite minimalne **Supabase klice** (povinne, cervene hvezdicky)
3. Volitelne vyplnte Stripe, SMTP, WhatsApp atd.
4. Klikni **"Stahnout .env.local"** → uloz do `backend/.env`
5. Klikni **"Config snippet"** → vloz do `frontend/index.html` pred `</head>`:

```html
<script>
window.MOTOGO_CONFIG = {
    SUPABASE_URL: 'https://xxxxx.supabase.co',
    SUPABASE_ANON_KEY: 'eyJ...'
};
</script>
```

---

## Krok 3: Databaze (5 minut)

### Varianta A: Supabase CLI (doporuceno)

```bash
# Instalace Supabase CLI
npm install -g supabase

# Prihlaseni
supabase login

# Propojeni s projektem
supabase link --project-ref TVUJ_PROJECT_REF

# Nahrani migraci
cd backend
supabase db push
```

`TVUJ_PROJECT_REF` najdes v Supabase Dashboard → Settings → General → Reference ID.

### Varianta B: SQL Editor (manualne)

1. Otevri **Supabase Dashboard → SQL Editor**
2. Spust migrace **postupne** v tomto poradi:

```
001_base_schema.sql
002_sos_system.sql
003_pricing_extras.sql
004_inventory.sql
005_maintenance.sql
006_messaging.sql
007_accounting.sql
008_documents_templates.sql
009_cms.sql
010_analytics.sql
011_notifications.sql
012_ai_integration.sql
013_admin_roles.sql
```

3. Po migracich spust `seed.sql` pro zakladni data (motorky, ceník, admin ucet)

### Varianta C: Cely SQL najednou

Pokud chces vsechno najednou, spust `FULL_MIGRATION.sql` v SQL Editoru. Obsahuje vsechny migrace i seed data.

---

## Krok 4: Storage buckety (2 minuty)

V **Supabase Dashboard → Storage → New Bucket** vytvor:

| Bucket | Pristup | Popis |
|---|---|---|
| `documents` | **Private** | Smlouvy, faktury, PDF |
| `media` | **Public** | Fotky motorek, galerie |
| `sos-photos` | **Private** | Fotky z SOS hlaseni |

Pro `media` bucket nastav public pristup:
1. Klikni na bucket `media`
2. **Policies → New Policy → Allow public read access**

---

## Krok 5: Edge Functions (10 minut)

### Deploy vsech funkci:

```bash
cd backend
supabase functions deploy send-sos
supabase functions deploy process-payment
supabase functions deploy send-email
supabase functions deploy upload-handler
supabase functions deploy admin-auth
supabase functions deploy ai-copilot
supabase functions deploy generate-document
supabase functions deploy generate-report
supabase functions deploy generate-tax
supabase functions deploy export-data
supabase functions deploy prediction-engine
supabase functions deploy inventory-check
supabase functions deploy cron-daily
supabase functions deploy cron-monthly
supabase functions deploy webhook-receiver
supabase functions deploy cms-sync
```

### Nebo vsechny najednou:

```bash
supabase functions deploy --all
```

### Nahrani secrets:

Pouzij **"CLI prikazy"** tlacitko v `setup.html` — zkopiruj a vloz do terminalu:

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="eyJ..."
supabase secrets set ANTHROPIC_API_KEY="sk-ant-..."
supabase secrets set STRIPE_SECRET_KEY="sk_live_..."
supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_..."
supabase secrets set SMTP_HOST="smtp.gmail.com"
supabase secrets set SMTP_PORT="587"
supabase secrets set SMTP_USER="info@motogo24.cz"
supabase secrets set SMTP_PASS="tvoje-heslo"
supabase secrets set WHATSAPP_TOKEN="EAAx..."
supabase secrets set WHATSAPP_PHONE_ID="123456"
supabase secrets set SMS_API_KEY="tvuj-sms-klic"
supabase secrets set SMS_SENDER="MotoGo24"
supabase secrets set GOOGLE_MAPS_API_KEY="AIzaSy..."
supabase secrets set ADMIN_PHONE="+420774256271"
supabase secrets set ADMIN_EMAIL="info@motogo24.cz"
supabase secrets set APP_URL="https://motogo24.cz"
```

### Overeni:

```bash
supabase secrets list
supabase functions list
```

---

## Krok 6: CRON joby (2 minuty)

V **SQL Editor** spust tyto prikazy pro automaticke ulohy:

```sql
-- Denni kontrola (kazdy den v 6:00 rano)
SELECT cron.schedule('daily-check', '0 6 * * *', $$
SELECT net.http_post(
    url := 'SUPABASE_URL/functions/v1/cron-daily',
    body := '{}'::jsonb,
    headers := '{"Authorization":"Bearer SERVICE_ROLE_KEY"}'::jsonb
);
$$);

-- Mesicni report (1. den mesice v 8:00 rano)
SELECT cron.schedule('monthly-report', '0 8 1 * *', $$
SELECT net.http_post(
    url := 'SUPABASE_URL/functions/v1/cron-monthly',
    body := '{}'::jsonb,
    headers := '{"Authorization":"Bearer SERVICE_ROLE_KEY"}'::jsonb
);
$$);
```

**Dulezite:** Nahrad `SUPABASE_URL` a `SERVICE_ROLE_KEY` skutecnymi hodnotami z Kroku 2.

### Overeni CRON:

```sql
SELECT * FROM cron.job;
```

---

## Krok 7: Stripe webhook (5 minut, volitelne)

Pokud pouzivas Stripe platby:

1. Jdi na [dashboard.stripe.com/webhooks](https://dashboard.stripe.com/webhooks)
2. **Add endpoint**:
   - URL: `https://TVUJ_PROJECT.supabase.co/functions/v1/webhook-receiver`
   - Events: `checkout.session.completed`, `payment_intent.succeeded`, `payment_intent.payment_failed`
3. Zkopiruj **Webhook Signing Secret** (`whsec_...`)
4. Nastav ho v Supabase:

```bash
supabase secrets set STRIPE_WEBHOOK_SECRET="whsec_..."
```

---

## Krok 8: Test (5 minut)

1. Otevri `frontend/index.html` v prohlizeci
2. **Registruj se** novym uctem
3. **Prihlas se** — mela by se zobrazit hlavni stranka s motorkami
4. **Proklikej motorky** — detail, galerie, cenik
5. **Vytvor rezervaci** — vyber motorku, datum, vyplnit formular
6. **Otestuj SOS** — zkontroluj ze prijde email/notifikace

### Kontrola v Supabase Dashboard:

- **Table Editor** → `users` — novy uzivatel
- **Table Editor** → `bookings` — nova rezervace
- **Edge Functions → Logs** — volani funkci
- **Authentication → Users** — registrovani uzivatele

---

## Krok 9: Build mobilni app

### Android:

```bash
cd frontend
npm install
bash build.sh
```

Vysledek: `motogo24-debug.apk` v aktualni slozce.

Pro **release** build (podepsany):

```bash
# Vygeneruj keystore (jednou)
keytool -genkey -v -keystore motogo24.keystore -alias motogo24 -keyalg RSA -keysize 2048 -validity 10000

# Build
npx cap sync android
cd android
./gradlew assembleRelease
```

### iOS (potrebujes Mac):

```bash
cd frontend
npx cap add ios
npx cap sync ios
npx cap open ios
```

V Xcode:
1. Nastav **Team** (Apple Developer ucet)
2. Nastav **Bundle Identifier** (napr. `cz.motogo24.app`)
3. **Product → Archive → Distribute App**

---

## Krok 10: Publikace

### Google Play:

1. **Podepsany AAB**: Android Studio → Build → Generate Signed Bundle
2. [play.google.com/console](https://play.google.com/console) → Create App
3. Vyplnit:
   - Store listing (nazev, popis, screenshoty)
   - Content rating
   - Pricing & distribution
4. Upload AAB do **Production** tracku
5. Submit for Review
6. **Poplatek**: $25 jednorazove

### Apple App Store:

1. [Apple Developer Program](https://developer.apple.com/programs/) — $99/rok
2. Xcode → Archive → Upload to **App Store Connect**
3. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → vytvor aplikaci
4. Vyplnit metadata, screenshoty, popis
5. **TestFlight** → interni testovani
6. Submit for Review (~1-3 dny)

---

## Kde co najit

| Sluzba | URL | Popis |
|---|---|---|
| Supabase Dashboard | [supabase.com/dashboard](https://supabase.com/dashboard) | Databaze, auth, storage, funkce |
| Stripe Dashboard | [dashboard.stripe.com](https://dashboard.stripe.com) | Platby, fakturace |
| Apple Developer | [developer.apple.com](https://developer.apple.com) | iOS distribuce |
| Google Play Console | [play.google.com/console](https://play.google.com/console) | Android distribuce |
| Claude AI | [console.anthropic.com](https://console.anthropic.com) | AI copilot API klice |
| Gmail App Passwords | [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) | SMTP hesla |
| Facebook Developers | [developers.facebook.com](https://developers.facebook.com) | WhatsApp API |
| Google Cloud Console | [console.cloud.google.com](https://console.cloud.google.com) | Maps API |
| SMS Brana | [smsbrana.cz](https://www.smsbrana.cz) | SMS sluzba |
| Datove schranky | [mojedatovaschranka.cz](https://www.mojedatovaschranka.cz) | Statni sprava |

---

## Struktura projektu

```
MotoGo24/
├── frontend/                    # Mobilni app (PWA + Capacitor)
│   ├── index.html              # Hlavni HTML
│   ├── app.js                  # App logika
│   ├── native-bridge.js        # Supabase bridge
│   ├── css/                    # Styly
│   ├── js/                     # JavaScript moduly
│   ├── icons/                  # App ikony
│   ├── build.sh                # Build script (APK)
│   ├── capacitor.config.ts     # Capacitor konfigurace
│   └── package.json
│
├── backend/                     # Supabase backend
│   ├── setup.html              # API Key Manager (tento nastroj)
│   ├── .env.example            # Sablona env promennych
│   ├── DEPLOYMENT.md           # Tento navod
│   └── supabase/
│       ├── migrations/         # SQL migrace (001-013)
│       ├── functions/          # Edge Functions (17 funkci)
│       │   ├── send-sos/
│       │   ├── process-payment/
│       │   ├── send-email/
│       │   ├── upload-handler/
│       │   ├── admin-auth/
│       │   ├── ai-copilot/
│       │   ├── generate-document/
│       │   ├── generate-report/
│       │   ├── generate-tax/
│       │   ├── export-data/
│       │   ├── prediction-engine/
│       │   ├── inventory-check/
│       │   ├── cron-daily/
│       │   ├── cron-monthly/
│       │   ├── webhook-receiver/
│       │   ├── cms-sync/
│       │   └── _shared/        # Sdilene utility
│       ├── seed.sql            # Zakladni data
│       └── FULL_MIGRATION.sql  # Vsechny migrace v jednom
│
└── README.md                    # Prehled projektu
```

---

## Reseni problemu

### Edge Function nefunguje

```bash
# Zkontroluj logy
supabase functions logs send-sos

# Zkontroluj secrets
supabase secrets list

# Znovu deploy
supabase functions deploy send-sos
```

### Databaze chyba pri migraci

```sql
-- Zkontroluj existujici tabulky
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Smazat a znovu (POZOR: maze data!)
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
-- Pak znovu spust migrace
```

### CORS chyba na frontendu

Zkontroluj ze `SUPABASE_URL` a `SUPABASE_ANON_KEY` v `window.MOTOGO_CONFIG` jsou spravne. Supabase automaticky povoluje CORS pro anon klic.

### Build APK selhava

```bash
# Ujisti se ze mas spravnou verzi Node
node --version  # >= 18

# Cista instalace
cd frontend
rm -rf node_modules
npm install
bash build.sh
```
