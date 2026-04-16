# ANALYZA 3/3 – Shop, Profil, Globalni navigace

## 6. SHOP / MERCH FLOW

### 6.1 Obchod (`/shop`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Grid produktu | 2 sloupce, CachedNetworkImage | OK |
| Loading | Zeleny spinner | OK |
| Chyba | Genericky text "error" | **Chybi specificka hlaska + Zkusit znovu** |
| Prazdny obchod | **ZADNY empty state!** | **BUG – prazdna plocha** bez vysvetleni |
| Vyprodano badge | Cerveny "Vyprodano" na karte | OK |
| Kosik badge | Zeleny kruhek s poctem | OK |
| Voucher banner | Gradient karta s CTA | OK |
| **Chybi:** | Zadne kategorie/filtry/razeni/hledani | **Zakladni navigace v obchode uplne chybi** |
| **Chybi:** | Zadny pull-to-refresh | Uzivatel nemuze obnovit seznam |

### 6.2 Detail produktu (`/shop/:id`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Carousel fotek | PageView + tecky | OK |
| Cena | Zelena, velke pismo | OK |
| Popis | Pod nazvem | OK |
| Barva/Material | Info radky | OK |
| Velikost | Chipy (jen kdyz produkt ma sizes) | OK |
| Vyprodano | Cerveny banner, CTA schovane | OK |
| Pridat do kosiku | Zelene tlacitko s cenou | OK |
| **BUG:** Validace velikosti | Toast "Error / Error" (stejny i18n klic) | **Spatna hlaska** – misto "Vyberte velikost" |
| **Chybi:** | Zadny vyber mnozstvi | Vzdy prida 1 kus |
| **Chybi:** | Zadne "Zobrazit kosik" po pridani | Uzivatel musi sam najit kosik |

### 6.3 Kosik (`/cart`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Prazdny kosik | Emoji + text | **Chybi CTA** "Zpet do obchodu" |
| Polozky | Nazev, cena, +/- mnozstvi, smazat | OK |
| Minus na 0 | Automaticky odebere polozku | **Chybi potvrzeni** – nechtene smazani |
| Smazani (kos) | Okamzite bez potvrzeni | **Chybi undo** – nelze vratit |
| Doprava | Posta 99 Kc / Osobni zdarma | OK |
| **BUG:** Mnozstvi bez limitu | **Zadna kontrola skladu** | Uzivatel muze pridat 999ks |
| **Chybi:** | Zadne obrazky produktu v kosiku | Tezsi orientace |
| **Chybi:** | Zadny "Pokracovat v nakupu" | Slepá ulicka pri prazdnem kosiku |

### 6.4 Checkout (`/checkout`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Auto-fill z profilu | Jmeno, adresa | OK |
| Doprava (fyzicke) | Posta/Osobni vyber | OK |
| Doprava (digitalni) | Automaticky skryta | OK |
| Platba kartou | Stripe, ulozena karta | OK |
| Promo kod | Validace, duplicity, max 1% kod | OK |
| Prazdny kosik check | Toast | OK |
| Adresa validace | Kontrola neprazdnosti (4 pole) | **Chybi format PSC, delka ulice** |
| Promo chyby | Hardcoded cestina! | **Neprelozitelne** do 7 jazyku |
| **KRITICKE:** Auth check | **Checkout je BEZ AUTENTIZACE** ale RPC vyzaduje login | **Uzivatel dostane generickou chybu** misto "Prihlaste se" |
| **Chybi:** | Zadna revalidace skladu pred platbou | Produkt muze byt vyprodany |
| **Chybi:** | Zadny casovy limit (na rozdil od booking 10min) | Nekonecne cekani mozne |
| **Chybi:** | Potvrzovaci stranka po platbe | Jen toast + redirect na /shop |

### 6.5 Voucher (`/voucher`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Predvolby | 500 / 1000 / 2000 Kc + vlastni | OK |
| Vlastni castka | Min 100, max 99999 | OK |
| Typ | Elektronicky (zdarma) / Tisteny (+180 Kc) | OK |
| Koupit | Prida do kosiku, presmeruje | OK |
| **Chybi:** | Zadna personalizace (zprava, jmeno prijemce) | Voucher nema osobni touch |
| **Chybi:** | Zadny email pro doruceni e-voucheru | Kam se posle? |
| **Chybi:** | Nahled jak voucher vypada | Uzivatel kupi naslepo |

---

## 7. PROFIL FLOW

### 7.1 Profil (`/profile`) – slouzi jako hlavni menu

**4 sekce:** Muj ucet | Nastaveni | Pomoc a podpora | Ostatni

| Menu polozka | Akce | CHYBI |
|---|---|---|
| Osobni udaje | Rozbalitelny formular | OK |
| Zpravy | → /messages | OK |
| Doklady | → /docs | OK |
| Faktury | → /invoices | OK |
| Smlouvy | → /contracts | OK |
| Platebni metody | → PaymentMethodsScreen | OK |
| Notifikace | Consent sheet | OK |
| Biometrie | Toggle sheet | OK |
| Soukromi | Consent sheet | OK |
| Zmena hesla | Sheet | OK |
| Jazyk | Vyber ze 7 jazyku | OK |
| SOS | → /sos (cervene) | OK |
| FAQ | Externi URL | OK |
| Pobocky | Bottom sheet | OK |
| Odhlaseni | Sign out + redirect | OK |
| Smazat ucet | Dialog + RPC | OK |

| Problem | Detail |
|---|---|
| **Ulozeni profilu – chyba** | Zobrazi raw exception text "$e" uzivateli |
| **Smazani uctu** | Chyba zobrazi raw exception |
| **Chybi:** | **Potvrzeni zmen** pred ulozenim profilu |
| **Chybi:** | **Progress indicator** pri ukladani |

### 7.2 Zpravy (`/messages`)

**2 taby:** Oznameni | Konverzace

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Oznameni | Seznam z admin_messages, realtime | OK |
| Klik na oznameni | **ZADNA AKCE** – display only | **Chybi navigace** na souvisejici obsah |
| Precteno/neprecteno | **Vizualne nerozliseno** (field existuje) | **Chybi vizualni indikator** |
| Konverzace | Seznam vlaken, realtime | OK |
| Neprectene | Zeleny border + badge s poctem | OK |
| Nova konverzace | Bottom sheet s inputem | OK |
| Prazdny predmet | Tichy return bez chyby | **Chybi validace** "Zadejte predmet" |

### 7.3 Detail konverzace (`/messages/:id`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Chat bubliny | Zelene (uzivatel) / bile (admin) | OK |
| Realtime | StreamBuilder | OK |
| Zavrena konverzace | Skryty input, status "Uzavreno" | OK |
| **BUG:** Odeslani zpravy | **Zadny try/catch!** | Sitova chyba crashne tichy |
| **Chybi:** | Zadne prilohy (fotky, soubory) | Jen text |
| **Chybi:** | Zadny "konverzace uzavrena" vysvetleni | Proc nemuzete odpovedet |

### 7.4 Faktury (`/invoices`)

| Prvek | Soucasny stav | CHYBI |
|---|---|---|
| Seznam | Seskupene po rocich, ikony dle typu | OK |
| Prazdny stav | "Faktury se generuji automaticky" | OK |
| Zobrazeni | HTML WebView | OK |
| Chyba | Hardcoded "Chyba: $e" | **Neprelozitelne + raw exception** |
| **Chybi:** | **Stazeni PDF** – jen WebView zobrazeni | Uzivatel nemuze ulozit/sdílet |
| **Chybi:** | Filtr/hledani | Vsechny faktury v jednom seznamu |

---

## 8. GLOBALNI / PRUREZY

### 8.1 Bottom Navigation

| Problem | Detail |
|---|---|
| **Nepoctene badge** | `unreadCountProvider` existuje ale NENI napojen na badge! |
| Prepinani tabu | Resetuje booking flow pri presunu na Home | OK |
| Aktivni stav | Zeleny pill + ikona | OK |

### 8.2 Tri globalni FABs

| FAB | Kdy se zobrazi | Akce |
|---|---|---|
| Kosik | Polozky v kosiku, ne na shop/payment | Klik → /cart, X = dismiss |
| Booking | Neplacena rezervace <10min | Klik → /payment, X = cancel booking |
| SOS | Aktivni incident s replacement | Klik → /sos/replacement, X = dismiss (7 dni) |

### 8.3 KRITICKE GLOBALNI PROBLEMY

| # | Problem | Dopad |
|---|---|---|
| 1 | **Push notifikace NIKDY neinicializovany** – `PushService.initialize()` se NEVOLA v main.dart | Uzivatel nedostava notifikace vubec |
| 2 | **Offline guard NIKDY nastartovany** – `OfflineGuard.startWatching()` se NEVOLA | Zadny overlay pri ztrate internetu |
| 3 | **Checkout bez auth** ale RPC vyzaduje auth | Neautentizovany uzivatel dostane generickou chybu |
| 4 | **Hardcoded cestina** na mnoha mistech (offline overlay, consent sheet, zmena hesla, promo chyby, cancel dialog, thread detail) | 6 ze 7 jazyku zobrazuje cestinu |
| 5 | **Platform hardcoded 'android'** v PushService | iOS push nebude fungovat spravne |
| 6 | **Stripe LIVE klic** v kodu | Bezpecnostni riziko (ale je to anon key pattern) |

### 8.4 Auth Guard – nechranene route

Tyto route **NEVYZADUJI prihlaseni** ale POTREBUJI ho:
- `/checkout` – createShopOrder RPC selze
- `/ai-agent` – edge function bez kontextu
- `/protocol` – predavaci protokol bez prirazeni k rezervaci

### 8.5 Chybejici globalni funkce

| Funkce | Status |
|---|---|
| Pull-to-refresh | Chybi na Home, Shop, Rezervacich |
| Offline stav | Implementovano ale NEVYUZITO |
| Push notifikace | Implementovano ale NEINICIALIZOVANO |
| Unread badge | Provider existuje ale NENAPOJEN |
| Deep linking z URL | Jen z push notifikaci, ne z URL |
| Retry logika | Jen OCR (3x) a platba polling (5x), jinde NIC |
| Crash reporting | ZADNY – zadny Sentry/Crashlytics |

---

## CELKOVE SKORE PRIPRAVENOSTI

| Oblast | Hotovo | Kriticke mezery |
|---|---|---|
| Auth flow | 75% | Potvrzeni hesla, GDPR souhlasy, lokalizace chyb |
| Home | 60% | Pull-refresh, fake badges, mrtve filtry |
| Booking | 85% | Success bez detailu, draft chyby |
| Rezervace | 70% | Protokol neuklada, chybi CTA, door codes |
| SOS | 65% | Chybi navody, cisla linky, popis poruchy |
| Shop | 55% | Auth gap, sklad, prazdny stav, velikost bug |
| Profil | 75% | Raw exceptions, chybi download faktur |
| Globalni | 40% | Push mrtve, offline mrtvy, badge mrtvy |

**CELKEM: ~65% pripravenost na produkci z hlediska UX navodu a error handling.**
