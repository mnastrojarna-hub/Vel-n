# ANALYZA 2/3 – Rezervace a SOS Flow

## 4. REZERVACE FLOW

### 4.1 Seznam rezervaci (`/reservations`)

**Filtry:** Vse | Aktivni | Nadchazejici | Dokoncene | Zrusene (swipe gesto taky meni)

| Stav | Soucasny stav | CHYBI |
|---|---|---|
| Loading | Zeleny spinner | OK |
| Chyba nacitani | Cerveny text "loadingError" | **Chybi tlacitko Zkusit znovu** – uzivatel nevi co delat |
| Prazdny seznam | Emoji + "Zadna rezervace" | **Chybi CTA** "Rezervovat motorku" – slepá ulicka |
| Realtime update | StreamProvider na bookings tabulku | OK |
| Karta – aktivni | Detail + Prodlouzit + SOS | OK |
| Karta – nadchazejici | Detail + Upravit | OK (ale **chybi Cancel** primo na karte) |
| Karta – dokoncene | Detail jizdy + Hodnotit | OK |
| Karta – zrusene | Detail + Obnovit (→ /search) | OK |
| Pending unpaid >10min | Klientsky zobrazen jako "zruseny" | **BUG – DB zaznam se neaktualizuje**, jen vizualni |

### 4.2 Detail rezervace (`/reservations/:id`)

**2 taby:** Detail | Platebni karta

**Detail tab – dle statusu:**

| Status | Tlacitka | CHYBI |
|---|---|---|
| Aktivni | Prodlouzit/Zkratit, SOS, Predavaci protokol | OK |
| Nadchazejici | Upravit, Zrusit (cerveny) | OK |
| Dokoncene | Faktura, Smlouva, Google recenze, Objednat znovu | OK |
| Zrusene | Storno poplatek+vraceni, Obnovit rezervaci | OK |

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Info karta | Motorka, ID, datumy, cas, misto | OK |
| Financni prehled | Cena, doruceni, extras, slevy, platba | OK |
| Door codes (aktivni) | Kody pro pristup | **Tichy fail** – chyba se skryje, uzivatel nevidi kody bez vysvetleni |
| Hodnoceni (dokoncene) | 5 hvezd, tap to rate | **Zadny error handling** – selhani hodnoceni muze crashnout |
| Faktura | HTML view | **Chybi info** kdyz faktura neni ready ("faktura jeste neni pripravena") |
| Navigace na pobocku | Tlacitko otevre mapu | OK |
| **Chybi:** | | **Kontakt na pobocku** – telefon, email, oteviraci doba |
| **Chybi:** | | **Cas do vyzvednuti** – odpocet pro nadchazejici |
| **Chybi:** | | **Checklist co vzit** – RP, obcanku, obleceni |

### 4.3 Uprava rezervace (`/reservations/:id/edit`)

**2 rezimy:** Prodlouzit/Zmenit | Zkratit/Zmenit

**Kalendar logika:**
- Extend: klik pred/za existujici rozsah, kontrola volnosti
- Shorten: klik uvnitr rozsahu, min 1 den
- Aktivni: nelze zmenit zacatek, jen konec
- Nadchazejici: oba smery

| Akce | Soucasny stav | CHYBI |
|---|---|---|
| Zmena datumu | Kalendar s barevnym kodovanim | OK, ale **chybi legenda** co barvy znamenaji |
| Zmena casu | Hodiny (0-23) + minuty (00/15/30/45) | OK |
| Zmena motorky (nadch.) | Seznam alternativ s licencni validaci | OK |
| Extras | 3 checkboxy + velikosti vybaveni | OK |
| Storno podminky (zkraceni) | Oranzovy banner s pravidly | OK |
| Cenovy prehled | Original vs nove, priplatek/vraceni | OK |
| Ulozit (priplatek) | → /payment | OK |
| Ulozit (bez priplatku) | Potvrzovaci stranka | OK |
| **Chybi:** | | **Potvrzovaci dialog** pred ulozenim zmen – "Opravdu chcete zmenit?" |
| **Chybi:** | | **Vysvetleni storno %** u zkraceni – kolik se vrati a proc |

### 4.4 Zruseni rezervace (Cancel Dialog)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Storno podminky | 7+ dni=100%, 2-7=50%, <2=0% | OK |
| Aktualni vraceni | "Aktualne: X% vraceni (Y Kc)" | OK |
| Duvod storna | Volitelny text | OK |
| RPC volani | cancel_booking_tracked | OK |
| Chyba storna | SnackBar "Chyba storna: $e" | **Raw exception** – chybi lidsky text |
| **BUG:** | Hardcoded cestina v samostatnem widgetu | **Neni prelozitelne** do 7 jazyku |
| **Chybi:** | | **Potvrzeni "opravdu zrusit?"** – jen jedno kliknuti na cervene tlacitko |

### 4.5 Predavaci protokol (`/protocol`)

**9 polozek checklistu** (5 zamcenych: klice, pojisteni, technicak, vesta, lekarnicka)
**Poznamky** k poskozeni, **Digitalni podpis** (biometrie nebo PIN)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Checklist | UI funguje | OK vizualne |
| Podpis | Biometrie (simulovany!) nebo PIN | Biometrie je fake 1.2s delay |
| Odeslani | **NEODESLANI DO SUPABASE!** | **KRITICKY BUG** – cely protokol je jen UI mock, data se neukladaji |
| Fotky poskozeni | **NEEXISTUJI** | **Chybi upload fotek** – jak dokazat stav pri prevzeti |
| **Chybi:** | | **Navod** co kontrolovat pri prevzeti motorky |
| **Chybi:** | | **Fotodokumentace** stavu motorky (pred a po) |

### 4.6 Smlouvy (`/contracts`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| VOP + GDPR | Vzdy zobrazeny | OK |
| Dynamicke dokumenty | Z documents tabulky | OK |
| Sablony | Z document_templates + placeholder nahrazeni | OK |
| Fallback | Lokalni HTML kdyz sablona chybi | OK |
| **Chybi:** | | **Moznost stahnout PDF** – jen webview, ne download |

### 4.7 AI Agent (`/ai-agent`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Chat rozhrani | Bublinky, typing indicator | OK |
| SOS doporuceni | Pokud AI navrhne, zobrazi SOS kartu | OK |
| Bez aktivni rez. | booking_id = null, edge fn bez kontextu | **Chybi upozorneni** ze AI nema kontext motorky |
| Chyba komunikace | "Chyba komunikace s AI agentem" | **Chybi tlacitko Zkusit znovu** |
| **Chybi:** | | **Napoveda** co se lze ptat – prikladove otazky |
| **Chybi:** | | **Offline stav** – co kdyz neni internet |

---

## 5. SOS FLOW

### 5.1 SOS Menu (`/sos`)

**3 hlavni volby:**
1. Nehoda/Kradez → podmenu (lehka nehoda, tezka nehoda, kradez)
2. Porucha na ceste → podmenu (lehka, motorka nepojede, servis)
3. Sdileni polohy → okamzite odeslani GPS

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| AI Agent karta | Navigace na /ai-agent | OK |
| Aktivni incident banner | Oranzovy s ID a statusem | OK |
| Telefonni kontakt | +420 774 256 271 | OK |
| **Bez aktivni rezervace** | **Flow NEBLOKUJE!** | **Chybi kontrola** – uzivatel bez rez. muze hlasit incident |
| **Chybi:** | | **Uvodni navod** – "V nouzi nejdrive zavolejte 112/155/158" |
| **Chybi:** | | **Vizualni hierarchie** nalehanosti – co je opravdu nouzove |

### 5.2 Nehoda – Tezka (motorka nepojede) (`/sos/accident`)

**Rozhodnuti o vine:** Moje vina / Neni moje vina (POVINNE pred akcemi)

| Akce | Ne moje vina | Moje vina |
|---|---|---|
| Nahradni motorka | ZDARMA (zelena) | PLACENA (cervena) |
| Ukoncit jizdu + odtah | Odtah zdarma | Odtah zdarma |

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Fault toggle | 2 tlacitka | OK |
| Info banner po vyber | Zeleny/cerveny vysvetleni | OK |
| GPS zachyceni | Tichy fail (null GPS) | **Chybi upozorneni** ze GPS nefunguje, poloha nezachycena |
| Foto po nahlaseni | 1 fotka pres kameru, volitelna | **Chybi navod** CO fotit (motorka, misto, SPZ druheho) |
| **Chybi:** | | **Krok-po-kroku navod** – zavolat policii, zajistit misto, fotodokumentace |
| **Chybi:** | | **Cisla tiseovych linek** – 112, 155, 158 |

### 5.3 Porucha – Nepojede (`/sos/breakdown`)

**Bez rozhodnuti o vine** – poruchy jsou vzdy "zdarma"

| Akce | Cena |
|---|---|
| Nahradni motorka | Zdarma |
| Ukoncit + odtah | Zdarma |

| Chybi | Popis |
|---|---|
| **Navod** | Co zkusit PRED nahlasenim (benzin, pojistky, zapaleni) |
| **Popis poruchy** | Zadne pole pro popis problemu – technici nevedi co je za zavadu |

### 5.4 Kradez (`/sos/theft`)

**4 kroky:** Zavolat policii → Kontaktovat MotoGo → Cislo pripadu → Zabezpeceni

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Tlacitko volat policii | Cervene, vytoci 158 | OK |
| Zabezpeceni toggle | Ano/Ne s popisem | OK |
| Nahradni motorka | Zabezpeceno=zdarma, Ne=placene | OK |
| Nahlasit kradez | GPS + incident creation | OK |
| **Chybi:** | | **Pole pro cislo policejniho protokolu** |
| **Chybi:** | | **Co delat dal** – blokace, dokumenty pro pojistovnu |

### 5.5 Servis na vlastni pest (`/sos/service`)

**4 kroky:** Najit servis → Kontaktovat → Faktura → Nahrat foto faktury

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Najit servis | Otevre Google Maps "motorka servis" | **Malo presne** – nehledá nejblizsi servisy |
| Upload faktury | Kamera, 1 fotka | **Chybi moznost** vice fotek nebo galerie |
| Potvrzeni | "Faktura nahrana. Proplati se do 7 dni" | OK |
| **Chybi:** | | **Seznam schvalenych servisu** s kontakty |
| **Chybi:** | | **Maximalni castka** k proplaceni |
| **Chybi:** | | **Co je/neni hrazeno** – jen strucny banner |

### 5.6 Nahradni motorka (`/sos/replacement`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Vyber motorky | Seznam vsech aktivnich, radio button | OK |
| Dorucovaci adresa | Autocomplete + fee kalkulace | OK |
| Cenovy souhrn (vina) | Motorka + doruceni + kauze 30000 Kc | OK |
| Zdarma (bez viny) | Rovnou /sos/done | OK |
| Platba (vina) | → /sos/payment (Stripe) | OK |
| **Chybi:** | | **Filtr** jen kompatibilni motorky (RP skupina) |
| **Chybi:** | | **Cas doruceni** – odhad kdy prijede nahradni motorka |
| **Chybi:** | | **Kontakt na ridice/kurýra** |

### 5.7 SOS Done Screen (`/sos/done`)

**9 variant** dle typu incidentu – kazda s jinym textem a barvou.

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| "Co se stane dal" | Kontextualni text | OK |
| Kontakt | Telefon | OK |
| Navigace | Zpravy, Rezervace, Domu | OK |
| **Chybi:** | | **Casovy odhad** reakce MotoGo (do kdy se ozvou) |
| **Chybi:** | | **Sledovani statusu** – jak zjistit postup reseni |

---

## SOUHRNNE KRITICKE NALEZY (Rezervace + SOS)

### KRITICKE BUGY
1. **Predavaci protokol se NEUKLADA** – data jdou do /dev/null
2. **Hodnoceni bez error handling** – muze crashnout
3. **Pending >10min jen vizualne zrusene** – DB se neaktualizuje
4. **SOS bez aktivni rezervace** – flow neblokuje pristup

### CHYBEJICI NAVODY A TEXTY
5. Prazdny seznam rezervaci – slepá ulicka bez CTA
6. Door codes tichy fail – uzivatel nevidi kody
7. Cancel dialog – hardcoded cestina, neprelozitelne
8. AI agent – zadne prikladove otazky
9. SOS – chybi cisla tisnovych linek 112/155/158
10. SOS nehoda – chybi krokovy navod (policie, fotky, misto)
11. SOS porucha – chybi pole pro popis problemu
12. Nahradni motorka – chybi odhad casu doruceni
13. Chyba storna – raw exception misto lidskeho textu
14. Protokol – chybi fotodokumentace stavu motorky
