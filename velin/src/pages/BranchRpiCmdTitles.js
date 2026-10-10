// ─── Vysvětlivky příkazů a stavů karty řídicí jednotky (BranchRpiZones.jsx) ─────────────────
// Jeden zdroj textu: na PC bublina `title` u tlačítka/čipu, na dotyku (< 1024 px) tentýž text pod „i“
// (useTouchHintList / HintList v BranchRpiTouchHint.jsx) — jinak by byl na telefonu a tabletu nedosažitelný.

export const NAME_ON_DISPLAY_TITLE = 'Název, který zákazník vidí v záhlaví displeje na pobočce. Jednotka ho bere VÝHRADNĚ z názvu pobočky ve Velíně — po přejmenování se propíše do 30 s (nebo hned tlačítkem „Synchronizovat konfiguraci“).'
export const PIN_UNLOCK_TITLE = 'Okamžitě zruší blokaci zadávání na displeji pobočky; počítadlo chybných pokusů začne znovu od nuly.'
export const SHELL_FREE_TITLE = 'Na displeji pobočky jde teď psát libovolné příkazy (servisní terminál). Každý příkaz se zapisuje do Hlášení a chyb.'
export const USB_RESETS_TITLE = 'Kolikrát health monitor za posledních 24 h odpojil a připojil modem na USB (poslední stupeň obnovy před rebootem).'
export const RNDIS_TITLE = 'EXPERIMENTÁLNÍ — jen s technikem u modemu. Přepne modem SIM7600 do režimu RNDIS (síťová karta usb0 bez ModemManageru). Při testu 26. 9. modem po přepnutí ÚPLNĚ zmizel z USB a vrátilo ho až fyzické odpojení a zapojení; na pobočce bez obsluhy by jednotka zůstala offline. Výsledek přijde do Hlášení a chyb (LTE_MODE); jednotka si nesoulad nastavení a modemu do 2 minut srovná sama.'
export const QMI_TITLE = 'Vrátí modem do původního režimu QMI (ModemManager). Internet vypadne na ~2 minuty.'
export const ALL_OFF_TITLE = 'Nouzové vypnutí: zhasne světla ve všech kójích i venku, zastaví hudbu, vypne signalizaci a odjistí relé. Dveře NEODEMYKÁ ani nezamyká. Použijte, když něco svítí nebo hraje a nemá.'
export const RESTART_TITLE = 'Restartuje jen program jednotky (ne celý Raspberry). Trvá pár sekund, zóny se znovu načtou. První pomoc, když se něco zaseklo.'
export const SYNC_TITLE = 'Jednotka si HNED stáhne aktuální nastavení z Velína (hardware, dveře, kódy, hudbu) — jinak to udělá sama do 60 s. Použijte po úpravě nastavení, když nechcete čekat.'
export const IDENTIFY_TITLE = 'Kterou pobočku mám před sebou? Na displeji této jednotky se zobrazí „Tady jsem 👋“ a signalizace VŠECH kójí 3× blikne zeleně. Slouží k rozpoznání, který řádek ve Velíně patří které fyzické jednotce — nic neotevírá, zákazníka to neomezí.'
export const REBOOT_TITLE = 'Restartuje celý počítač na pobočce. Cca minutu nejde zadat kód ani otevřít dveře — nedělejte, když je někdo v kóji.'
export const SHELL_LOCK_TITLE = 'Zamkne volné psaní příkazů na displeji pobočky (připravená tlačítka terminálu zůstanou).'
export const SHELL_UNLOCK_TITLE = 'Povolí na 30 minut psaní libovolných příkazů technikovi, který má u sebe jen DIAGNOSTICKÝ kód. Se servisním heslem terminál píše rovnou (a funguje i když je pobočka offline — příkaz odsud by tam stejně nedorazil). Běží pod uživatelem motogo (ne root), každý příkaz jde do Hlášení a chyb. Po 30 minutách se sám zamkne.'

// Dlaždice zóny
export const CONTACT_TITLE = 'Syrová hodnota dveřního vstupu z modulu (1 = kontakt sepnut mezi DI a DGND, 0 = rozpojeno; svorka COM na Relay (B) musí zůstat VOLNÁ) a úroveň, kterou program bere jako zavřeno (má být 1 — s 0 vypadá přerušený kabel jako zavřené dveře). „Změn od startu“ = kolikrát se vstup od startu jednotky změnil; 0 po otevření zámku = signál kontaktu nejde do modulu.'
export const POLARITY_TITLE = 'Prohodí úroveň „Zavřeno =“ u těchto dveří (0 ↔ 1) a uloží do HW mapy — použijte, když program hlásí opačný stav, než dveře skutečně mají.'
export const ZONE_TEST_TITLE = 'Zkontroluje, že v této kóji funguje světlo, barevná signalizace a reproduktor — postupně je na chvíli zapne. Zámek se NESEPNE, takže se dveře neotevřou. Dělejte na prázdné kóji.'
export const CONTACT_TEST_TITLE = 'Jednotka 20 s sleduje dveřní kontakt této zóny. Během testu dveře otevřete a zase zavřete (skončete zavřenými). Výsledek za ~25 s v „Hlášení a chyby“: v pořádku / otočit polaritu / vstup se nemění (zapojení).'
