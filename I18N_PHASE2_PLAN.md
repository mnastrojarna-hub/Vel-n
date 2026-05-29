# i18n — Fáze 2: plán překladu hardcoded textů

Stav po fázi 1: překladová mapa kompletní — všech 7 jazyků má 1049 klíčů.

Tento dokument NEMĚNÍ kód. Je to soupis a plán pro náhradu natvrdo zadaných
českých textů v UI voláním `t(context).tr('key')`.

## Souhrn

| Kategorie | Počet |
|---|---|
| České literály celkem (lib/) | 1764 |
| **Nechat česky** (právní/účetní/doc-scanner — řešeno přes velín+API) | 1319 |
| **K překladu** (zákaznické UI) | **445** |
| — z toho klíč už v mapě existuje (jen napojit) | 131 |
| — z toho potřebuje nový klíč + překlad do 7 jazyků | 314 |

> ⚠️ **Duplicita rezervačního formuláře (ověřeno):**
> - **Aktivní** verze = `core/router.dart` (inline, ř. ~420–668) +
>   `core/booking_form_widget.dart` (importován routerem) +
>   `core/booking_form_*.dart` sekce. → **tyto překládat.**
> - **Mrtvý kód** = `features/booking/booking_form_screen.dart` (32 řetězců).
>   Sousední `booking_form_body.dart` výslovně uvádí, že tento soubor
>   „causes green blank screen". → **NEpřekládat**, doporučeno smazat zvlášť.
> - `features/booking/booking_ui_helpers.dart` a `booking_address_widgets.dart`
>   vs. `core/booking_form_*` / `address_picker.dart` — před úpravou ověřit,
>   které jsou reálně volané (možná další mrtvý kód).
>
> Po odečtení mrtvého `booking_form_screen.dart` (32) zbývá k překladu **~413** řetězců.

## Doporučené pořadí (po flow, commit po každé fázi)

### Fáze A — Rezervační formulář (booking)
_210 řetězců — 87 napojit, 123 nových klíčů_

- `core/router.dart` — 40 (21 napojit / 19 nových)
- `features/booking/booking_form_screen.dart` — 32 (18 napojit / 14 nových)
- `features/booking/booking_ui_helpers.dart` — 23 (11 napojit / 12 nových)
- `features/booking/booking_address_widgets.dart` — 19 (9 napojit / 10 nových)
- `core/booking_form_widget.dart` — 15 (2 napojit / 13 nových)
- `features/booking/widgets/price_summary.dart` — 14 (3 napojit / 11 nových)
- `features/booking/widgets/address_picker.dart` — 12 (10 napojit / 2 nových)
- `core/booking_form_price_section.dart` — 7 (0 napojit / 7 nových)
- `features/booking/price_calculator.dart` — 7 (0 napojit / 7 nových)
- `features/booking/widgets/booking_consents_cta.dart` — 5 (1 napojit / 4 nových)
- `features/booking/booking_models.dart` — 4 (0 napojit / 4 nových)
- `features/booking/widgets/booking_date_section.dart` — 4 (2 napojit / 2 nových)
- `features/booking/booking_form_body.dart` — 4 (4 napojit / 0 nových)
- `features/booking/widgets/extras_selector.dart` — 3 (2 napojit / 1 nových)
- `core/booking_form_promo_section.dart` — 3 (2 napojit / 1 nových)
- `core/booking_size_dialogs.dart` — 2 (0 napojit / 2 nových)
- `features/booking/widgets/booking_time_section.dart` — 2 (1 napojit / 1 nových)
- `features/booking/widgets/map_picker.dart` — 2 (0 napojit / 2 nových)
- `features/booking/booking_provider.dart` — 2 (0 napojit / 2 nových)
- `features/booking/widgets/promo_code_input.dart` — 1 (0 napojit / 1 nových)
- `core/booking_form_pickup_section.dart` — 1 (0 napojit / 1 nových)
- `features/booking/widgets/booking_form_header.dart` — 1 (1 napojit / 0 nových)
- `core/pending_booking_fab_provider.dart` — 1 (0 napojit / 1 nových)
- `core/booking_form_time_section.dart` — 1 (0 napojit / 1 nových)
- `core/booking_form_moto_card.dart` — 1 (0 napojit / 1 nových)
- `core/booking_form_extras_section.dart` — 1 (0 napojit / 1 nových)
- `core/booking_form_return_section.dart` — 1 (0 napojit / 1 nových)
- `features/booking/widgets/booking_form_extra_item.dart` — 1 (0 napojit / 1 nových)
- `features/booking/widgets/booking_moto_section.dart` — 1 (0 napojit / 1 nových)

### Fáze B — Rezervace: detail / úpravy / storno
_66 řetězců — 13 napojit, 53 nových klíčů_

- `features/reservations/reservation_edit_screen.dart` — 17 (0 napojit / 17 nových)
- `features/reservations/reservation_provider.dart` — 11 (6 napojit / 5 nových)
- `features/reservations/widgets/reservation_edit_calendar_section.dart` — 9 (4 napojit / 5 nových)
- `features/reservations/reservation_models.dart` — 7 (0 napojit / 7 nových)
- `features/reservations/widgets/res_detail_tab_content.dart` — 5 (0 napojit / 5 nových)
- `features/reservations/widgets/reservation_edit_extras_section.dart` — 5 (1 napojit / 4 nových)
- `features/reservations/widgets/res_modification_history.dart` — 4 (0 napojit / 4 nových)
- `features/reservations/widgets/reservation_edit_moto_section.dart` — 3 (1 napojit / 2 nových)
- `features/reservations/widgets/reservation_edit_widgets.dart` — 1 (0 napojit / 1 nových)
- `features/reservations/widgets/res_location_row.dart` — 1 (1 napojit / 0 nových)
- `features/reservations/widgets/reservation_edit_confirm_page.dart` — 1 (0 napojit / 1 nových)
- `features/reservations/widgets/reservation_card.dart` — 1 (0 napojit / 1 nových)
- `features/reservations/widgets/res_cancel_dialog.dart` — 1 (0 napojit / 1 nových)

### Fáze C — Platba
_22 řetězců — 1 napojit, 21 nových klíčů_

- `features/payment/stripe_service.dart` — 11 (1 napojit / 10 nových)
- `features/payment/widgets/upsell_section.dart` — 6 (0 napojit / 6 nových)
- `features/payment/widgets/payment_header_widgets.dart` — 4 (0 napojit / 4 nových)
- `features/payment/payment_methods_screen.dart` — 1 (0 napojit / 1 nových)

### Fáze D — SOS
_18 řetězců — 3 napojit, 15 nových klíčů_

- `features/sos/sos_replacement_screen.dart` — 8 (0 napojit / 8 nových)
- `features/sos/sos_provider.dart` — 4 (0 napojit / 4 nových)
- `features/sos/sos_service_screen.dart` — 3 (1 napojit / 2 nových)
- `features/sos/sos_breakdown_immobile_screen.dart` — 1 (1 napojit / 0 nových)
- `features/sos/sos_theft_screen.dart` — 1 (1 napojit / 0 nových)
- `features/sos/sos_report_screen.dart` — 1 (0 napojit / 1 nových)

### Fáze E — Shop / poukazy
_23 řetězců — 0 napojit, 23 nových klíčů_

- `features/shop/voucher_screen.dart` — 6 (0 napojit / 6 nových)
- `features/shop/cart_screen.dart` — 6 (0 napojit / 6 nových)
- `features/shop/widgets/checkout_summary_section.dart` — 4 (0 napojit / 4 nových)
- `features/shop/product_detail_screen.dart` — 3 (0 napojit / 3 nových)
- `features/shop/shop_checkout_screen.dart` — 2 (0 napojit / 2 nových)
- `features/shop/widgets/checkout_promo_card.dart` — 1 (0 napojit / 1 nových)
- `features/shop/shop_screen.dart` — 1 (0 napojit / 1 nových)

### Fáze F — Profil & nastavení
_55 řetězců — 10 napojit, 45 nových klíčů_

- `features/profile/widgets/settings_sheets.dart` — 20 (5 napojit / 15 nových)
- `features/profile/permissions_screen.dart` — 11 (2 napojit / 9 nových)
- `features/profile/widgets/branch_detail_card.dart` — 10 (0 napojit / 10 nových)
- `features/profile/widgets/consent_sheet.dart` — 7 (1 napojit / 6 nových)
- `features/profile/widgets/branch_moto_list.dart` — 5 (2 napojit / 3 nových)
- `features/profile/widgets/branches_sheet.dart` — 2 (0 napojit / 2 nových)

### Fáze G — Katalog, zprávy, onboarding, auth, home, core
_51 řetězců — 17 napojit, 34 nových klíčů_

- `core/overlays/onboarding_overlays.dart` — 10 (1 napojit / 9 nových)
- `features/messages/ai_agent_screen.dart` — 9 (0 napojit / 9 nových)
- `features/catalog/moto_model.dart` — 6 (5 napojit / 1 nových)
- `core/native/permission_service.dart` — 6 (1 napojit / 5 nových)
- `features/catalog/catalog_provider.dart` — 4 (4 napojit / 0 nových)
- `features/auth/register_screen.dart` — 4 (4 napojit / 0 nových)
- `features/messages/thread_detail_screen.dart` — 3 (1 napojit / 2 nových)
- `features/catalog/widgets/price_footer.dart` — 2 (0 napojit / 2 nových)
- `core/widgets/error_boundary.dart` — 2 (0 napojit / 2 nových)
- `features/auth/auth_provider.dart` — 2 (0 napojit / 2 nových)
- `main.dart` — 1 (0 napojit / 1 nových)
- `core/widgets/logo_header.dart` — 1 (1 napojit / 0 nových)
- `core/placeholder_screen.dart` — 1 (0 napojit / 1 nových)

## Detailní soupis řetězců k překladu

Legenda: ✅ = klíč už existuje v mapě (jen napojit), ➕ = nový klíč potřeba.

### Fáze A — Rezervační formulář (booking)

**`core/booking_form_extras_section.dart`**

- ➕ L201: `+${item.price.toStringAsFixed(0)} Kč`

**`core/booking_form_moto_card.dart`**

- ➕ L66: `Pobočka: ${moto.branchName}`

**`core/booking_form_pickup_section.dart`**

- ➕ L33: `Mezná 9, Mezná`

**`core/booking_form_price_section.dart`**

- ➕ L51: `${bd.basePrice.toStringAsFixed(0)} Kč`
- ➕ L56: `+${(e.price * e.quantity).toStringAsFixed(0)} Kč`
- ➕ L61: `+${bd.pickupDeliveryFee.toStringAsFixed(0)} Kč`
- ➕ L66: `+${bd.returnDeliveryFee.toStringAsFixed(0)} Kč`
- ➕ L71: `−${bd.discountTotal.toStringAsFixed(0)} Kč`
- ➕ L74: `0 Kč`
- ➕ L91: `${bd.total.toStringAsFixed(0)} Kč`

**`core/booking_form_promo_section.dart`**

- ✅ L151: `SLEVOVÝ KÓD`
- ✅ L177: `Klikněte pro zadání kódu`
- ➕ L207: `${d.code} (−${d.value.toStringAsFixed(0)} Kč)`

**`core/booking_form_return_section.dart`**

- ➕ L33: `Mezná 9, Mezná`

**`core/booking_form_time_section.dart`**

- ➕ L93: `ZMĚNIT`

**`core/booking_form_widget.dart`**

- ➕ L45: `helma – řidič`
- ➕ L46: `rukavice – řidič`
- ➕ L47: `bunda – řidič`
- ➕ L48: `kalhoty – řidič`
- ➕ L53: `boty – řidič`
- ➕ L57: `výbava – spolujezdec`
- ➕ L106: `$dc ${dc == 1 ? "den" : dc < 5 ? "dny" : "dní"}`
- ✅ L130: `Pro výběr jednoho dne klikněte dvakrát`
- ➕ L173: `Celkem za pronájem`
- ➕ L182: `${bd.basePrice.toStringAsFixed(0)} Kč`
- ➕ L286: `Potvrzuji, že jsem zákonný zástupce a dětský `
- ➕ L287: `motocykl bude provozován pod mým dohledem`
- ➕ L318: `Při přistavení vyplňte velikosti výbavy`
- ➕ L328: `Chybí: ${missingSizes.join(`
- ✅ L365: `POKRAČOVAT K PLATBĚ`

**`core/booking_size_dialogs.dart`**

- ➕ L46: `Boty spolujezdce se vybírají samostatně.`
- ➕ L106: `VYBERTE VŠECHNY VELIKOSTI`

**`core/pending_booking_fab_provider.dart`**

- ➕ L106: `Zákazník si to rozmyslel`

**`core/router.dart`**

- ✅ L422: `Vyplňte formulář`
- ➕ L447: `od ${moto.priceLabel}/den · záloha neúčtována`
- ➕ L457: `Pobočka: ${moto.branchName}`
- ➕ L493: `$dc ${dc == 1 ? "den" : dc < 5 ? "dny" : "dní"}`
- ✅ L506: `Pro výběr jednoho dne klikněte dvakrát`
- ➕ L537: `Celkem za pronájem`
- ➕ L542: `${bd.basePrice.toStringAsFixed(0)} Kč`
- ✅ L555: `ČAS VYZVEDNUTÍ`
- ✅ L634: `Na pobočce`
- ✅ L638: `Přistavení na vaši adresu`
- ✅ L639: `1 000 Kč + 40 Kč/km`
- ✅ L645: `Adresa vyzvednutí`
- ✅ L668: `VRÁCENÍ MOTORKY`
- ✅ L671: `Na pobočce`
- ✅ L675: `Odvoz z vaší adresy`
- ✅ L676: `1 000 Kč + 40 Kč/km`
- ✅ L682: `Adresa vrácení`
- ✅ L705: `VÝBAVA A DOPLŇKY`
- ✅ L719: `Základní výbava zdarma`
- ➕ L810: `⚠ Klikněte pro výběr velikosti`
- ➕ L818: `+${item.price.toStringAsFixed(0)} Kč`
- ✅ L839: `Shrnutí ceny`
- ➕ L844: `Motorka × $dc ${dc == 1 ? "den" : dc < 5 ? "dny" : "dní"}`
- ➕ L845: `${bd.basePrice.toStringAsFixed(0)} Kč`
- ➕ L848: `+${(e.price * e.quantity).toStringAsFixed(0)} Kč`
- ✅ L850: `Přistavení`
- ➕ L851: `+${bd.pickupDeliveryFee.toStringAsFixed(0)} Kč`
- ➕ L854: `+${bd.returnDeliveryFee.toStringAsFixed(0)} Kč`
- ➕ L857: `−${bd.discountTotal.toStringAsFixed(0)} Kč`
- ➕ L859: `✓ Záloha se neúčtuje`
- ✅ L866: `Celkem (cena konečná)`
- ➕ L870: `${bd.total.toStringAsFixed(0)} Kč`
- ✅ L877: `Cena bez DPH, nejsme plátci`
- ✅ L901: `SLEVOVÝ KÓD`
- ✅ L925: `Klikněte pro zadání kódu`
- ➕ L964: `Potvrzuji, že jsem zákonný zástupce a dětský `
- ➕ L965: `motocykl bude provozován pod mým dohledem`
- ✅ L982: `POKRAČOVAT K PLATBĚ`
- ➕ L1029: `Boty spolujezdce se vybírají samostatně.`
- ➕ L1086: `VYBERTE VŠECHNY VELIKOSTI`

**`features/booking/booking_address_widgets.dart`**

- ✅ L37: `Klikněte pro zadání adresy`
- ➕ L59: `${delivFee.toStringAsFixed(0)} Kč`
- ✅ L88: `Město`
- ➕ L136: `${fee.toStringAsFixed(0)} Kč`
- ✅ L144: `Ulice a číslo`
- ✅ L150: `Zjišťuji polohu...`
- ➕ L218: `${fee.toStringAsFixed(0)} Kč`
- ✅ L237: `Použít moji polohu (GPS)`
- ➕ L249: `Počítám...`
- ➕ L282: `${fee.toStringAsFixed(0)} Kč`
- ✅ L298: `Spočítat vzdálenost a cenu`
- ✅ L307: `Zrušit`
- ✅ L311: `Uložit`
- ➕ L378: `Počítám km...`
- ➕ L399: `~${km.toStringAsFixed(0)} km · ${fee.toStringAsFixed(0)} Kč`
- ✅ L412: `Zjišťuji polohu...`
- ➕ L418: `GPS nedostupné — zadejte adresu ručně nebo z mapy`
- ➕ L476: `${fee.toStringAsFixed(0)} Kč`
- ➕ L482: `GPS chyba — zadejte adresu ručně`

**`features/booking/booking_form_body.dart`**

- ✅ L117: `Vyzvednutí`
- ✅ L137: `VRÁCENÍ MOTORKY`
- ✅ L138: `Vrácení`
- ✅ L158: `VÝBAVA A DOPLŇKY`

**`features/booking/booking_form_screen.dart`**

- ✅ L77: `Vyplňte formulář pro rezervaci`
- ➕ L104: `od ${moto.priceLabel}/den · záloha neúčtována`
- ➕ L108: `Pobočka: ${moto.branchName}${moto.branchCity != null ? `
- ➕ L112: `ZMĚNIT`
- ✅ L134: `Pro výběr jednoho dne klikněte dvakrát`
- ✅ L156: `ČAS VYZVEDNUTÍ`
- ➕ L157: `Vyberte čas, kdy si motorku vyzvednete / chcete přistavit.`
- ✅ L172: `ŘIDIČSKÝ PRŮKAZ`
- ✅ L175: `Údaje z vašeho profilu`
- ✅ L179: `Na pobočce`
- ✅ L182: `Přistavení na vaši adresu`
- ✅ L187: `VRÁCENÍ MOTORKY`
- ✅ L188: `Na pobočce`
- ✅ L191: `Odvoz z vaší adresy`
- ✅ L196: `VÝBAVA A DOPLŇKY`
- ✅ L203: `Základní výbava zdarma`
- ➕ L207: `Výbava spolujezdce`
- ➕ L208: `Boty řidiče`
- ✅ L218: `Shrnutí ceny`
- ➕ L220: `${breakdown.basePrice.toStringAsFixed(0)} Kč`
- ➕ L221: `Přistavení / vrácení`
- ➕ L222: `Doplňky a výbava`
- ➕ L223: `−${breakdown.discountTotal.toStringAsFixed(0)} Kč`
- ➕ L224: `✓ Záloha se neúčtuje`
- ✅ L227: `Celkem (cena konečná)`
- ➕ L228: `${breakdown.total.toStringAsFixed(0)} Kč`
- ✅ L231: `Cena bez DPH, nejsme plátci`
- ✅ L242: `SLEVOVÝ KÓD`
- ✅ L249: `Zadejte kód`
- ➕ L281: `Souhlasím s obchodními podmínkami a VOP`
- ➕ L283: `Souhlasím se zpracováním osobních údajů`
- ✅ L300: `POKRAČOVAT K PLATBĚ`

**`features/booking/booking_models.dart`**

- ➕ L299: `Výbava spolujezdce`
- ➕ L306: `Boty řidiče`
- ➕ L308: `Moto boty – uveďte velikost`
- ➕ L317: `Moto boty – uveďte velikost`

**`features/booking/booking_provider.dart`**

- ➕ L79: `${value.toStringAsFixed(0)} Kč`
- ➕ L103: `${value.toStringAsFixed(0)} Kč`

**`features/booking/booking_ui_helpers.dart`**

- ✅ L188: `Klikněte pro zadání adresy`
- ➕ L210: `~${distKm.toStringAsFixed(0)} km · ${delivFee!.toStringAsFixed(0)} Kč`
- ➕ L211: `${delivFee!.toStringAsFixed(0)} Kč`
- ✅ L246: `Město`
- ➕ L305: `${fee.toStringAsFixed(0)} Kč`
- ✅ L313: `Ulice a číslo`
- ✅ L319: `Zjišťuji polohu...`
- ➕ L353: `${fee.toStringAsFixed(0)} Kč`
- ✅ L372: `Použít moji polohu (GPS)`
- ➕ L384: `Počítám...`
- ➕ L417: `${fee.toStringAsFixed(0)} Kč`
- ✅ L433: `Spočítat vzdálenost a cenu`
- ✅ L442: `Zrušit`
- ✅ L446: `Uložit`
- ➕ L573: `[SUGGEST] Mapy.cz ✓ ${items.length} výsledků`
- ➕ L593: `[SUGGEST] Nominatim ✓ ${nData.length} výsledků`
- ➕ L642: `Počítám km...`
- ✅ L703: `Zjišťuji polohu...`
- ➕ L711: `GPS nedostupné — zadejte adresu ručně nebo z mapy`
- ➕ L789: `GPS chyba — zadejte adresu ručně`
- ➕ L814: `${fee.toStringAsFixed(0)} Kč`
- ✅ L1048: `Slevový kód`
- ✅ L1057: `Zadejte kód...`

**`features/booking/price_calculator.dart`**

- ➕ L266: `Třebíč`
- ➕ L267: `České Budějovice`
- ➕ L268: `Mezná`
- ➕ L269: `Plzeň`
- ➕ L270: `Ústí nad Labem`
- ➕ L272: `Příbram`
- ➕ L273: `Žďár nad Sázavou`

**`features/booking/widgets/address_picker.dart`**

- ✅ L63: `Vyzvednutí`
- ✅ L64: `Přistavení na vaši adresu`
- ✅ L65: `Odvoz z vaší adresy`
- ✅ L114: `Na pobočce`
- ➕ L115: `Mezná 9, Mezná`
- ✅ L122: `Vyzvednutí`
- ✅ L123: `Přistavení na vaši adresu`
- ✅ L124: `Odvoz z vaší adresy`
- ✅ L125: `1 000 Kč + 40 Kč/km`
- ✅ L126: `od 1 000 Kč`
- ✅ L148: `Klikněte pro zadání adresy`
- ➕ L175: `${_deliveryFee!.toStringAsFixed(0)} Kč`

**`features/booking/widgets/booking_consents_cta.dart`**

- ➕ L20: `Souhlasím s obchodními podmínkami a VOP`
- ➕ L26: `Souhlasím se zpracováním osobních údajů`
- ➕ L33: `Potvrzuji, že jsem zákonný zástupce a dětský `
- ➕ L34: `motocykl bude pod mým dohledem`
- ✅ L76: `POKRAČOVAT K PLATBĚ`

**`features/booking/widgets/booking_date_section.dart`**

- ✅ L78: `Pro výběr jednoho dne klikněte dvakrát`
- ➕ L105: `CELKOVÁ CENA ZA PRONÁJEM`
- ➕ L114: `${bd.basePrice.toStringAsFixed(0)} Kč`
- ✅ L122: `Cena bez DPH, nejsme plátci`

**`features/booking/widgets/booking_form_extra_item.dart`**

- ➕ L64: `+${price.toStringAsFixed(0)} Kč`

**`features/booking/widgets/booking_form_header.dart`**

- ✅ L55: `Vyplňte formulář pro rezervaci`

**`features/booking/widgets/booking_moto_section.dart`**

- ➕ L42: `od ${moto.priceLabel}/den · záloha neúčtována`

**`features/booking/widgets/booking_time_section.dart`**

- ✅ L19: `ČAS VYZVEDNUTÍ`
- ➕ L24: `Vyberte čas vyzvednutí / přistavení`

**`features/booking/widgets/extras_selector.dart`**

- ✅ L151: `Základní výbava zdarma`
- ✅ L166: `Při přistavení potřebujeme znát velikosti výbavy`
- ➕ L244: `+${item.price.toStringAsFixed(0)} Kč`

**`features/booking/widgets/map_picker.dart`**

- ➕ L255: `Vyberte místo na mapě`
- ➕ L299: `Hledám adresu...`

**`features/booking/widgets/price_summary.dart`**

- ➕ L45: `${breakdown.basePrice.toStringAsFixed(0)} Kč`
- ➕ L52: `+${(extra.price * extra.quantity).toStringAsFixed(0)} Kč`
- ➕ L59: `+${breakdown.pickupDeliveryFee.toStringAsFixed(0)} Kč`
- ➕ L66: `+${breakdown.returnDeliveryFee.toStringAsFixed(0)} Kč`
- ➕ L72: `Pojištění`
- ➕ L73: `+${breakdown.insuranceFee.toStringAsFixed(0)} Kč`
- ➕ L80: `+${item.price.toStringAsFixed(0)} Kč`
- ➕ L87: `−${breakdown.discountTotal.toStringAsFixed(0)} Kč`
- ➕ L94: `✓ Záloha se neúčtuje`
- ➕ L95: `0 Kč`
- ✅ L110: `Celkem (cena konečná)`
- ➕ L114: `${_totalWithUpsell.toStringAsFixed(0)} Kč`
- ✅ L122: `Cena bez DPH, nejsme plátci`
- ✅ L144: `dní`

**`features/booking/widgets/promo_code_input.dart`**

- ➕ L158: `🎁 ${d.code} (−${d.value.toStringAsFixed(0)} Kč)`

### Fáze B — Rezervace: detail / úpravy / storno

**`features/reservations/reservation_edit_screen.dart`**

- ➕ L207: `helma – řidič`
- ➕ L208: `rukavice – řidič`
- ➕ L209: `bunda – řidič`
- ➕ L210: `kalhoty – řidič`
- ➕ L212: `boty – řidič`
- ➕ L241: `Chybí velikosti výbavy`
- ➕ L242: `Při přistavení doplňte: ${missingSizes.join(`
- ➕ L551: `${_booking!.totalPrice.toStringAsFixed(0)} Kč`
- ➕ L555: `+${calc.dateChangeAmount.toStringAsFixed(0)} Kč`
- ➕ L557: `-${calc.dateChangeAmount.abs().toStringAsFixed(0)} Kč`
- ➕ L558: `+${_pickupDelivFee.toStringAsFixed(0)} Kč`
- ➕ L559: `+${_returnDelivFee.toStringAsFixed(0)} Kč`
- ➕ L560: `+${calc.extrasTotal.toStringAsFixed(0)} Kč`
- ➕ L565: `${calc.priceDiff > 0 ? "+" : ""}${calc.priceDiff.toStringAsFixed(0)} Kč`
- ➕ L587: `Při přistavení vyplňte velikosti výbavy`
- ➕ L590: `Chybí: ${_missingGearSizes().join(`
- ➕ L607: `)} (+${calc.priceDiff.toStringAsFixed(0)} Kč)`

**`features/reservations/reservation_models.dart`**

- ➕ L397: `začátek dříve o ${sd.abs()} d`
- ➕ L398: `začátek později o $sd d`
- ➕ L399: `konec později o $ed d`
- ➕ L400: `konec dříve o ${ed.abs()} d`
- ➕ L405: `prodlouženo o $dd d`
- ➕ L408: `zkráceno o ${dd.abs()} d`
- ➕ L414: `beze změny`

**`features/reservations/reservation_provider.dart`**

- ✅ L253: `Krádež`
- ➕ L254: `Nehoda (lehká)`
- ➕ L255: `Nehoda (těžká)`
- ➕ L256: `Porucha (lehká)`
- ➕ L257: `Porucha (těžká)`
- ➕ L258: `Závada / dotaz`
- ✅ L266: `Nahlášeno`
- ✅ L267: `Přijato`
- ✅ L268: `Řeší se`
- ✅ L269: `Vyřešeno`
- ✅ L270: `Uzavřeno`

**`features/reservations/widgets/res_cancel_dialog.dart`**

- ➕ L47: `)}: $pct% (${refund.toStringAsFixed(0)} Kč)`

**`features/reservations/widgets/res_detail_tab_content.dart`**

- ➕ L140: `${res.totalPrice.toStringAsFixed(0)} Kč`
- ➕ L142: `${res.deliveryFee!.toStringAsFixed(0)} Kč`
- ➕ L144: `${res.extrasPrice!.toStringAsFixed(0)} Kč`
- ➕ L148: `−${res.discountAmount!.toStringAsFixed(0)} Kč`
- ➕ L414: `${res.totalPrice.toStringAsFixed(0)} Kč`

**`features/reservations/widgets/res_location_row.dart`**

- ✅ L45: `Přistavení`

**`features/reservations/widgets/res_modification_history.dart`**

- ➕ L145: `$osFmt – $oeFmt (${desc.origDays} dní)`
- ➕ L150: `$csFmt – $ceFmt (${desc.newDays} dní)`
- ➕ L567: `${res.stornoFee!.toStringAsFixed(0)} Kč`
- ➕ L572: `${res.refundAmount!.toStringAsFixed(0)} Kč`

**`features/reservations/widgets/reservation_card.dart`**

- ➕ L120: `${reservation.totalPrice.toStringAsFixed(0)} Kč`

**`features/reservations/widgets/reservation_edit_calendar_section.dart`**

- ✅ L60: `VRÁCENÍ`
- ➕ L65: `+$diffDays ${diffDays == 1 ? "den" : diffDays < 5 ? "dny" : "dní"} (prodloužení)`
- ➕ L66: `${diffDays.abs()} ${diffDays.abs() == 1 ? "den" : diffDays.abs() < 5 ? "dny" ...`
- ➕ L80: `VAŠE AKTIVNÍ REZERVACE`
- ✅ L103: `Pro výběr jednoho dne klikněte na stejný den dvakrát`
- ✅ L121: `← Zkrátit začátek`
- ✅ L140: `Zkrátit konec →`
- ➕ L166: `Stávající`
- ➕ L168: `Zkráceno`

**`features/reservations/widgets/reservation_edit_confirm_page.dart`**

- ➕ L41: `ZPĚT NA REZERVACE`

**`features/reservations/widgets/reservation_edit_extras_section.dart`**

- ➕ L47: `DOPLŇKY`
- ➕ L52: `Výbava spolujezdce`
- ➕ L55: `Boty řidiče`
- ➕ L59: `Uveďte velikost`
- ✅ L71: `Při přistavení potřebujeme znát velikosti výbavy`

**`features/reservations/widgets/reservation_edit_moto_section.dart`**

- ➕ L41: `ZMĚNA MOTORKY`
- ➕ L50: `AKTUÁLNÍ MOTORKA  `
- ✅ L98: `Chyba načítání`

**`features/reservations/widgets/reservation_edit_widgets.dart`**

- ➕ L184: `+${price.toStringAsFixed(0)} Kč`

### Fáze C — Platba

**`features/payment/payment_methods_screen.dart`**

- ➕ L342: `Platí do ${card.displayExpiry}${card.holderName != null ? `

**`features/payment/stripe_service.dart`**

- ➕ L39: `Vaše přihlášení vypršelo. Pro dokončení platby `
- ➕ L40: `se prosím znovu přihlaste.`
- ➕ L69: `Vaše přihlášení vypršelo. Pro dokončení platby `
- ➕ L70: `se prosím znovu přihlaste.`
- ➕ L99: `Strhnutí uložené karty selhalo.`
- ➕ L124: `Server vrátil neočekávanou odpověď (HTTP ${response.statusCode}). `
- ✅ L125: `Zkuste to prosím znovu.`
- ➕ L130: `Spojení se serverem trvá příliš dlouho. `
- ➕ L131: `Zkontrolujte připojení k internetu a zkuste platbu znovu.`
- ➕ L136: `Nepodařilo se spojit s platebním serverem. `
- ➕ L137: `Zkontrolujte připojení k internetu a zkuste to znovu.`

**`features/payment/widgets/payment_header_widgets.dart`**

- ➕ L154: `${item.amount.toStringAsFixed(0)} Kč`
- ➕ L167: `${amount.toStringAsFixed(0)} Kč`
- ➕ L199: `${amount.toStringAsFixed(0)} Kč`
- ➕ L280: `)} ${amount.toStringAsFixed(0)} Kč →`

**`features/payment/widgets/upsell_section.dart`**

- ➕ L45: `DOPORUČUJEME K REZERVACI`
- ➕ L168: `Rozšířené pojištění`
- ➕ L176: `Snížená spoluúčast při nehodě`
- ➕ L186: `+${price.toStringAsFixed(0)} Kč`
- ➕ L272: `${product.price.toStringAsFixed(0)} Kč`
- ➕ L294: `✓ PŘIDÁNO`

### Fáze D — SOS

**`features/sos/sos_breakdown_immobile_screen.dart`**

- ✅ L44: `Porucha — motorka nepojízdná`

**`features/sos/sos_provider.dart`**

- ➕ L197: `Nepřihlášen — přihlaste se znovu`
- ➕ L318: `zaviněná`
- ➕ L321: `Zákazník ukončuje jízdu — žádá odtah ($faultLabel)`
- ➕ L357: `Zákazník nahrál fakturu za servis`

**`features/sos/sos_replacement_screen.dart`**

- ➕ L154: `Zákazník objednal náhradní motorku: ${_selectedMoto!.model} (${_total.toStrin...`
- ➕ L155: `Zákazník objednal náhradní motorku: ${_selectedMoto!.model} (zdarma)`
- ➕ L300: `)}: ${_deliveryKm.toStringAsFixed(0)} km × 40 + 1 000 = ${_deliveryFee.toStri...`
- ➕ L311: `${_motoTotal.toStringAsFixed(0)} Kč`
- ➕ L316: `${_deliveryFee.toStringAsFixed(0)} Kč`
- ➕ L318: `${_damageDeposit.toStringAsFixed(0)} Kč`
- ➕ L320: `${_total.toStringAsFixed(0)} Kč`
- ➕ L341: `)} ${_total.toStringAsFixed(0)} Kč →`

**`features/sos/sos_report_screen.dart`**

- ➕ L408: `Sdílení polohy`

**`features/sos/sos_service_screen.dart`**

- ✅ L46: `Servis na vlastní pěst`
- ➕ L210: `IČ: 123 456 78 · DIČ: CZ12345678`
- ➕ L211: `Mezná 9, 393 01`

**`features/sos/sos_theft_screen.dart`**

- ✅ L42: `Krádež motorky`

### Fáze E — Shop / poukazy

**`features/shop/cart_screen.dart`**

- ➕ L109: `${subtotal.toStringAsFixed(0)} Kč`
- ➕ L118: `+${shipping.toStringAsFixed(0)} Kč`
- ➕ L126: `−${discount.toStringAsFixed(0)} Kč`
- ➕ L136: `${total.toStringAsFixed(0)} Kč`
- ➕ L181: `${item.price.toStringAsFixed(0)} Kč`
- ➕ L191: `${item.total.toStringAsFixed(0)} Kč`

**`features/shop/product_detail_screen.dart`**

- ➕ L95: `${product.price.toStringAsFixed(0)} Kč`
- ➕ L157: `Množství`
- ➕ L180: `${(product.price * _qty).toStringAsFixed(0)} Kč`

**`features/shop/shop_checkout_screen.dart`**

- ➕ L193: `${total.toStringAsFixed(0)} Kč`
- ➕ L616: `🎁 ${d.code} (−${d.value.toStringAsFixed(0)} Kč)`

**`features/shop/shop_screen.dart`**

- ➕ L229: `${product.price.toStringAsFixed(0)} Kč`

**`features/shop/voucher_screen.dart`**

- ➕ L84: `$amt Kč`
- ➕ L107: `Kč`
- ➕ L124: `+ ${printedVoucherShipping.toStringAsFixed(0)} Kč`
- ➕ L135: `)} ${_amount.toStringAsFixed(0)} Kč${_printed ? " (${tr.tr(`
- ➕ L138: `${_total.toStringAsFixed(0)} Kč`
- ➕ L145: `)} · ${_total.toStringAsFixed(0)} Kč →`

**`features/shop/widgets/checkout_promo_card.dart`**

- ➕ L157: `🎁 ${d.code} (−${d.value.toStringAsFixed(0)} Kč)`

**`features/shop/widgets/checkout_summary_section.dart`**

- ➕ L52: `${item.total.toStringAsFixed(0)} Kč`
- ➕ L77: `+${shipping.toStringAsFixed(0)} Kč`
- ➕ L98: `−${discount.toStringAsFixed(0)} Kč`
- ➕ L113: `${total.toStringAsFixed(0)} Kč`

### Fáze F — Profil & nastavení

**`features/profile/permissions_screen.dart`**

- ✅ L86: `Oprávnění aplikace`
- ➕ L96: `Oprávnění udělená při prvním spuštění.\n`
- ➕ L97: `Klikněte na oprávnění pro změnu v nastavení telefonu.`
- ✅ L116: `Biometrické přihlášení`
- ➕ L131: `Aktivována`
- ➕ L138: `Deaktivována`
- ➕ L203: `Otevřít nastavení telefonu`
- ➕ L217: `Oprávnění`
- ➕ L218: `Oprávnění znovu vyžádána`
- ➕ L226: `Povolit vše znovu`
- ➕ L275: `Zakázáno`

**`features/profile/widgets/branch_detail_card.dart`**

- ➕ L35: `Obslužná`
- ➕ L165: `Otevřít v mapách`
- ➕ L218: `Kód pobočky`
- ➕ L237: `Navigovat na pobočku`
- ➕ L327: `turistická`
- ➕ L328: `městská`
- ➕ L329: `horská`
- ➕ L330: `rekreační voda`
- ➕ L331: `metropolitní centrum`
- ➕ L332: `městská tranzitní`

**`features/profile/widgets/branch_moto_list.dart`**

- ➕ L30: `Motorky na pobočce (${motorcycles.length})`
- ➕ L164: `ŘP $license`
- ➕ L172: `Cestovní`
- ✅ L173: `Dětské`
- ✅ L174: `Sportovní`

**`features/profile/widgets/branches_sheet.dart`**

- ➕ L70: `Pobočky MotoGo24`
- ➕ L101: `Nepodařilo se načíst pobočky`

**`features/profile/widgets/consent_sheet.dart`**

- ➕ L29: `Marketingový souhlas`
- ➕ L32: `VOP — všeobecné obchodní podmínky`
- ➕ L33: `GDPR — zpracování osobních údajů`
- ➕ L34: `Zpracování dat pro provoz služby`
- ➕ L35: `Četl/a jsem návrh smlouvy na motogo24.cz a souhlasím`
- ➕ L36: `Fotografování dokladů a motorky`
- ✅ L131: `Uložit`

**`features/profile/widgets/settings_sheets.dart`**

- ✅ L23: `Změna hesla`
- ➕ L29: `Nové heslo (min. 8 znaků)`
- ➕ L34: `Potvrďte heslo`
- ➕ L39: `Min. 8 znaků`
- ✅ L43: `Hesla se neshodují`
- ✅ L51: `Heslo změněno`
- ➕ L58: `Změnit heslo`
- ➕ L69: `Čeština 🇨🇿`
- ➕ L96: `Jazyk změněn`
- ✅ L168: `Oprávnění aplikace`
- ➕ L175: `Oprávnění udělená při prvním spuštění.\n`
- ➕ L176: `Pro odvolání otevřete nastavení telefonu.`
- ✅ L196: `Biometrické přihlášení`
- ➕ L205: `Aktivována`
- ➕ L209: `Deaktivována`
- ➕ L257: `Otevřít nastavení telefonu`
- ➕ L271: `Oprávnění`
- ➕ L272: `Oprávnění znovu vyžádána`
- ➕ L280: `Povolit vše znovu`
- ➕ L326: `Zakázáno`

### Fáze G — Katalog, zprávy, onboarding, auth, home, core

**`core/native/permission_service.dart`**

- ➕ L59: `Navigace, sdílení pozice při poruše`
- ➕ L65: `Fotoaparát`
- ➕ L66: `Skenování dokladů, dokumentace škod`
- ✅ L79: `Oznámení`
- ➕ L80: `SOS aktualizace, zprávy, stav rezervací`
- ➕ L87: `Nahrávání fotek faktur a dokladů`

**`core/overlays/onboarding_overlays.dart`**

- ➕ L14: `Čeština`
- ➕ L126: `Navigace k půjčovně, sdílení pozice při poruše`
- ➕ L127: `Fotoaparát`
- ✅ L129: `Oznámení`
- ➕ L130: `Nahrávání fotek faktur a dokladů`
- ➕ L131: `Biometrické ověření`
- ➕ L156: `🏍️ Vítejte v MotoGo24`
- ➕ L159: `Pro plnou funkčnost potřebujeme váš souhlas`
- ➕ L172: `Povolit vše a pokračovat →`
- ➕ L178: `Přeskočit – nastavím později`

**`core/placeholder_screen.dart`**

- ➕ L40: `Migrace v dalších fázích`

**`core/widgets/error_boundary.dart`**

- ➕ L159: `Něco se pokazilo`
- ➕ L168: `Omlouváme se za komplikace. Zkuste to prosím znovu.`

**`core/widgets/logo_header.dart`**

- ✅ L68: `PŮJČOVNA MOTOREK`

**`features/auth/auth_provider.dart`**

- ➕ L216: `Server je nedostupný, zkuste to prosím za chvíli.`
- ➕ L220: `Reset hesla se nepodařil.`

**`features/auth/register_screen.dart`**

- ✅ L35: `Česká republika`
- ✅ L413: `Česká republika`
- ✅ L414: `Slovenská republika`
- ✅ L415: `Německo`

**`features/catalog/catalog_provider.dart`**

- ✅ L190: `Vše`
- ✅ L191: `Cestovní / Enduro`
- ✅ L192: `Dětské`
- ✅ L193: `Sportovní`

**`features/catalog/moto_model.dart`**

- ➕ L191: `${min.toStringAsFixed(0)} Kč`
- ✅ L335: `Výkon`
- ✅ L336: `Točivý moment`
- ✅ L338: `Nádrž`
- ✅ L340: `ŘP kategorie`
- ✅ L427: `Čt`

**`features/catalog/widgets/price_footer.dart`**

- ➕ L42: `} Kč`
- ➕ L100: `${totalPrice.toStringAsFixed(0)} Kč`

**`features/messages/ai_agent_screen.dart`**

- ➕ L31: `👋 Dobrý den! Jsem MotoGo AI asistent. Jak vám mohu pomoci? `
- ➕ L32: `Mohu poradit s kontrolkami, poruchami, manuály nebo technickými dotazy.`
- ➕ L74: `Omlouvám se, nepodařilo se zpracovat dotaz.`
- ➕ L83: `🆘 Agent doporučuje nahlásit SOS incident.`
- ➕ L136: `🤖 AI Servisní agent`
- ➕ L154: `⏳ Přemýšlím...`
- ➕ L176: `Popište problém nebo dotaz...`
- ➕ L218: `Nahlásit SOS incident`
- ➕ L219: `Klikněte pro nahlášení problému`

**`features/messages/thread_detail_screen.dart`**

- ✅ L122: `Uzavřeno`
- ➕ L133: `Napište první zprávu`
- ➕ L155: `Napište zprávu...`

**`main.dart`**

- ➕ L86: `Omlouváme se za komplikace.`
