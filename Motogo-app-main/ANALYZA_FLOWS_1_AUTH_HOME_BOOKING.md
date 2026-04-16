# ANALYZA 1/3 – Auth, Home, Booking Flow

## 1. AUTH FLOW

### 1.1 Login Screen (`/login`)
**Tlacitka:** Prihlasit se | Biometrie | Zapomenute heslo | Registrovat se
**Kontakt:** tel +420 774 256 271, web motogo24.vseproweb.com

| Stav / Akce | Soucasny stav | CHYBI |
|---|---|---|
| Prazdny email/heslo | Toast "Vyplnte email a heslo" | OK |
| Spatne heslo | Toast s Supabase chybou (anglicky!) | **Chybi ceska lokalizace chyb** – "Invalid login credentials" neni srozumitelne |
| Sitova chyba | Toast "loginError: ..." s raw exception | **Chybi lidsky text** – uzivatel vidi technicke detaily |
| Biometrie zrusena | Toast "Overeni zruseno" | OK |
| Biometrie – session expired | Skryje tlacitko, toast "session expired" | **Chybi navod** co delat – uzivatel nevedi proc biometrie zmizela |
| Email format | ZADNA validace formatu na loginu | **Doporuceni:** Validovat format pred odeslanim |
| Heslo zobrazeni | Tlacitko oka pro toggle | OK |
| Uz prihlaseny | Redirect na home | OK |
| Zapomenute heslo | 3-krokovy flow (email→OTP→nove heslo) | OK, ale **chybi info o doruceni kodu** (spam, cekani) |

### 1.2 Registrace (`/register`) – 3 kroky

**Krok 1 – Osobni udaje:**
| Pole | Validace | CHYBI |
|---|---|---|
| Jmeno/Prijmeni | Min 2 znaky, unicode | OK |
| Email | Regex format | OK |
| Telefon | +XXX format, 8-14 cislic | OK |
| Datum narozeni | 18-99 let, CZ format | OK |
| Heslo | Min 8 znaku | **Chybi potvrzeni hesla!** Uzivatel muze udelat preklep a ztrati pristup |

**Krok 2 – Adresa:**
| Pole | Validace | CHYBI |
|---|---|---|
| Mesto | Min 2 znaky | OK |
| Ulice | Min 3 znaky | OK |
| PSC | **ZADNA validace!** | **Chybi kontrola** formatu (5 cislic pro CZ/SK) |
| Stat | Dropdown s defaultem | OK |

**Krok 3 – Ridicak:**
| Pole | Validace | CHYBI |
|---|---|---|
| Cislo RP | Min 4 znaky | OK |
| Platnost RP | Min 14 dni od dneska | OK |
| Skupina | A2/A dropdown | OK |

**Kriticke problemy registrace:**
1. **Vsechny souhlasy (GDPR, marketing, SMS, email, push, WhatsApp, foto) se nastavi na TRUE automaticky** bez zobrazeni checkboxu – **mozny GDPR problem**
2. **Zadne potvrzeni hesla** – preklep = uzamceni uctu
3. **Chyba "User already registered"** prijde anglicky ze Supabase
4. **Chybi progress indikator** pri samotne registraci (500ms+ cekani na DB trigger)

### 1.3 Skenovani dokladu (`/docs`, `/docs/scan`)

**Tlacitka:** Naskenovat kamerou | Naskenovat pouze RP | Nahrat z galerie
**Kamerovy flow:** 4 kroky (ID predni, ID zadni, RP predni, RP zadni)

| Stav | Soucasny stav | CHYBI |
|---|---|---|
| Kamera zamitnuta | Toast "errCameraPermission" | **Chybi navod** jak povolit v nastaveni telefonu |
| OCR selhani | 3 pokusy s backoff, detailni diagnostika | OK – dobre zpracovano |
| Castecne rozpoznani | Toast "docScannedPartial" | **Chybi info** ktera pole chybi a co dodelat |
| Galerie upload | ImagePicker, 85% kvalita | OK |
| Overeni dokladu | Banner zeleny/oranzovy | OK |
| **Chybi uplne:** | | **Zadny navod PRED skenovaniem** – jak drzet doklad, osvetleni, uhel |

---

## 2. HOME SCREEN (`/`)

**Struktura:** Header → Aktivni rezervace → SOS tlacitko → Filtry → Motorky

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Sticky header | NE – scrolluje s obsahem | Vizualni nekonzistence s originalem |
| Pull-to-refresh | **NENI** | **Uzivatel nemuze obnovit data** – musi odejit a vratit se |
| Loading motorek | Zeleny spinner | OK |
| Chyba nacitani | Cerveny text s raw exception | **Chybi lidsky text a tlacitko Zkusit znovu** |
| Prazdny vysledek | Zobrazuje pocet "0 motorek" | **Chybi vysvetleni** proc nic + CTA zmenit filtry |
| "DNES VOLNA" badge | **VZDY zobrazen na kazde karte!** | **BUG – zavadejici** – neni dynamicky kontrolovano |
| Detail badge "Dostupna" | **VZDY zeleny** bez skutecne kontroly | **BUG – zavadejici info** |
| Filtr usage tags | Chipy se vybiraji ale **nemaji efekt** | **BUG – mrtvy kod**, tags se neaplikuji na vysledky |
| SOS tlacitko | Jen pri aktivni rezervaci | OK |
| Hamburger menu | Naviguje na profil | OK |
| Pocet neprectenych zprav | **Neni zobrazen nigde** (provider existuje) | **Chybi badge** na navigaci/hamburgeru |

---

## 3. BOOKING FLOW

### 3.1 Dualní filosofie
- **Cesta A:** Vybrat termin → filtrovat dostupne motorky → detail → rezervace
- **Cesta B:** Vybrat motorku na home → detail → vybrat termin → rezervace

### 3.2 Search Screen (`/search`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Kalendar vyber | Range selection, single-day hint | OK |
| Prazdne vysledky | "searchNoMotorcycles" text | **Chybi doporuceni** – zmenit filtry, rozsirit datumy |
| Chyba nacitani | **Prazdny SliverToBoxAdapter!** | **BUG – uzivatel nevidi zadnou chybu** |
| Pocet vysledku | "{n} dostupnych motorek . X dni" | OK |

### 3.3 Detail Screen (`/moto/:id`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Carousel fotek | Sipky + tecky, CachedNetworkImage | OK |
| Specifikace | Motor, vykon, vaha, nadrz, sedlo, ABS | OK |
| Cenik dnu | Po-Ne tabulka | OK |
| Obsazene dny | Z RPC, zobrazeny v kalendari | OK |
| CTA "Rezervovat" | Sedy kdyz bez datumu, zeleny s datumem | **Chybi text PROC je sedy** – "Nejdrive vyberte termin" |
| Validace ridicaku | Cerveny banner pri nedostatecnem RP | OK |
| Prekryv s jinou rez. | Cerveny banner | OK |
| Manual PDF | Link pokud existuje | OK |

### 3.4 Booking Form (`/booking`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Prazdny stav (bez motorky) | "Nejprve vyberte motorku" + CTA | OK |
| Cas vyzvednuti | Time picker | OK |
| Doruceni | Radio store/delivery, adresa, cena | OK |
| Delivery fee | 1000 Kc + 40 Kc/km (Mapy.cz→OSRM→Haversine) | **Chybi vysvetleni** jak se cena pocita |
| Extras | Seznam s cenami | OK, ale **chybi popis** co extras obsahuje |
| Promo kod | Validace pres 2 RPC | Chybove hlasky v cestine, OK |
| Souhlasy VOP/GDPR | Checkboxy | OK |
| Celkova cena | Rozpad: zaklad + extras + doruceni - slevy | OK |

### 3.5 Payment Screen (`/payment`)

| Stav | Soucasny stav | CHYBI |
|---|---|---|
| 10min odpocet | Zobrazen, po vyprseni error sheet | OK |
| Stripe Payment Sheet | Nativni, podporuje ulozene karty | OK |
| Platba zamitnuta | "Platba kartou zamitnuta" + Stripe hlaska | OK |
| Brana se neotevrela | "Platebni brana se neotevrela" | OK |
| Session expired | "Prihlaseni vyprselo" + Prihlasit se | OK |
| Timeout serveru | "Server neodpovida" + Zkusit znovu | OK |
| Sit chyba | "Chyba pripojeni" + Zkusit znovu | OK |
| Max 3 pokusy | Po 3x "rezervace zustane ulozena" | OK |
| Nulova cena (sleva) | "Potvrdit" misto platby | OK |
| **Draft selhani** | "Rezervaci se nepodarilo vytvorit" | **Chybi specificke duvody** – proc selhala |
| **Support kontakt** | Email info@motogo24.cz v error sheetu | OK |

### 3.6 Success Screen (`/success`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Animovany checkmark | Zeleny, elastic bounce | OK |
| Titulek | "Rezervace Potvrzena!" | OK |
| Bezpecnostni tipy | Zlute boxy | OK |
| **Chybi uplne:** | | **Zadne detaily rezervace!** – ID, datumy, motorka, cena, pobocka |
| **Chybi:** | | **Zadny dalsi krok** – kdy se dostavite, co vzit s sebou, kontakt |
| **Chybi:** | | **Potvrzovaci email info** – "Potvrzeni jsme zaslali na vas email" |

---

## SOUHRNNE KRITICKE NALEZY (Auth + Home + Booking)

### BUGY (nefunkcni/zavadejici)
1. Badge "DNES VOLNA" vzdy zobrazen – zavadejici
2. Detail "Dostupna" vzdy zeleny – zavadejici
3. Usage tags filtry nemaji efekt – mrtvy kod
4. Search error state prazdny – uzivatel nevidi chybu

### CHYBEJICI NAVODY A TEXTY
5. Supabase chyby v anglictine (login, register)
6. Zadne potvrzeni hesla pri registraci
7. PSC bez validace
8. Automaticke souhlasy bez zobrazeni (GDPR risk)
9. Success screen bez detailu rezervace
10. Sedy CTA button bez vysvetleni proc
11. Zadny pull-to-refresh na home
12. Zadny navod pred skenovanim dokladu
13. Biometrie zmizi bez vysvetleni
