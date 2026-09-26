"""Tabulka rad „co s tím“ pro protokol diagnostiky (`diag_protocol.py`) — česky, konkrétně
(zařízení, kanál, IP se doplní přes `hint(key, **fmt)`). Klíč = typ nálezu."""
from __future__ import annotations

from typing import Any

HINTS = {
    "modbus_unreachable": "Zkontrolujte kabel/napájení modulu {name} na IP {host} (LED LINK na modulu a switchi); ping z RPi selhal.",
    "shelly_unreachable": "Zkontrolujte napájení a LAN/Wi-Fi Shelly {name} na IP {host}; ověřte, že v Shelly běží RPC (Settings → Local API).",
    "device_mismatch": "Zařízení {name} na {host} neodpovídá jako {type} — zkontrolujte IP v HW mapě (Velín → Samoobsluha) a typ modulu.",
    "module_offline_in_program": "Modul {name} je na síti, ale program ho má offline/v obnově — počkejte 30 s, případně restartujte službu motogo-controller.",
    "ip_conflict": "Dvě zařízení mají v HW mapě stejnou IP a port — opravte adresy ve Velíně (Pobočky → Samoobsluha).",
    "gateway_missing": "LTE bez výchozí trasy — Nahodit LTE (nmcli con up motogo-lte), pak USB reset modemu; health to dělá sám (reconnect → reset → USB reset). Kabelem internet není. "
                       "Terminál na displeji: „Nahodit I/O síť“ / „Nahodit LTE“.",
    "gateway_eth": "Trasa přes eth0 posílá internet do prázdna (kabelem internet není, LTE má metriku 100). Jednotka ji odstraní sama (health route_fix / dispečer 50-motogo-lan-addr, do 60 s); ručně: rm -f /var/lib/motogo/lan_gateway; sudo -n /etc/NetworkManager/dispatcher.d/50-motogo-lan-addr eth0 manual.",
    "dns_missing": "Bez DNS serveru nefunguje Velín — DNS dává jen profil LTE (operátor + záložní 1.1.1.1/8.8.8.8): Nahodit LTE.",
    "iface_down": "Rozhraní {name} nemá adresu/spojení — zkontrolujte kabel do switche modulů a profil motogo-lan.",
    "lte": "Zkontrolujte SIM (PIN vypnutý, kredit), anténu a profil motogo-lte; stav: mmcli -m any. Modem v QMI, který ModemManager nevidí → RNDIS z karty jednotky.",
    "rndis_no_ip": "RNDIS bez adresy: datové spojení modemu nenaběhlo (AT$QCRMCALL). Health udělá USB reset modemu (po něm se spojení spouští znovu); ručně na jednotce: sudo /usr/local/sbin/motogo-lte-rndis start. Když to nepomůže opakovaně, vraťte modem do QMI (karta jednotky → „Modem → QMI“) a řešte hardware.",
    "modem_usb_missing": "Modem SIM7600 není vůbec vidět na USB (lsusb): zkontrolujte USB kabel a napájení modemu (LED PWR/NET), zkuste jiný USB port přímo na Raspberry; health zkusí USB reset a poté reboot.",
    "lte_pid_unknown": "Modem se hlásí pod neznámým USB PID: vraťte ho do QMI (karta jednotky → „Modem → QMI“; skript pošle AT+CUSBPIDSWITCH=9001,1,1 na AT port) a pak případně znovu do RNDIS. Když PID zůstane, modem má jinou firmware kompozici — pošlete PID (1e0e:xxxx) k doplnění do software.",
    "lte_mode_mismatch": "Režim modemu na USB neodpovídá konfiguraci jednotky: přepnutí (motogo-lte-mode) neproběhlo celé. Klikněte na kartě jednotky znovu na cílový režim JEDNOU a počkejte 3 minuty; log na jednotce: /var/log/motogo-lte-mode.log.",
    "sim_pin": "Vypněte PIN přímo na SIM (vložit do mobilu → Nastavení → SIM → PIN vypnout) — to je u pobočky "
               "nejspolehlivější, modem se pak po restartu připojí sám. Jinak musí PIN sedět v profilu: "
               "sudo nmcli con modify motogo-lte gsm.pin <PIN> && sudo nmcli con up motogo-lte. "
               "POZOR: špatný uložený PIN po 3 pokusech SIM zablokuje a bude potřeba PUK.",
    "sim_puk": "SIM je zablokovaná — odemkne ji jen PUK (karta/účet u operátora), v mobilu. Potom PIN rovnou "
               "vypněte a SIM vraťte do jednotky; do profilu motogo-lte pak žádný pin= nepatří.",
    "internet": "Internet nedostupný — zkontrolujte LTE (signál, SIM) a výchozí bránu; DNS: resolvectl status.",
    "dns_fail": "DNS neodpovídá (server operátora/routeru) — záložní 1.1.1.1/8.8.8.8 doplňuje aktualizace software; ručně: "
                "nmcli con modify motogo-lte +ipv4.dns 1.1.1.1 (a motogo-lan), pak Nahodit LTE. Když nejde ani TCP 1.1.1.1:443, je to výpadek internetu, ne DNS.",
    "not_paired": "Spárujte jednotku ve Velíně (Pobočky → Samoobsluha → Zařízení) — report se odešle po spárování.",
    "heartbeat": "Velín neodpovídá — zkontrolujte internet a párování (token zařízení); log: journalctl -u motogo-controller.",
    "realtime": "Realtime kanál nespojen — příkazy z Velína dorazí až pollingem (do 10 s); zkontrolujte internet.",
    "service": "Zkontrolujte službu: systemctl status {unit}; journalctl -u {unit} -n 50.",
    "failed_units": "Zobrazte selhané jednotky: systemctl --failed.",
    "health": "Health služba neposílá stav (motogo-health) — systemctl restart motogo-health.",
    "mpv": "Přehrávač mpv neběží — zkontrolujte USB zvukovku (aplay -l), audio.device v konfiguraci a log služby.",
    "music": "Nahrajte hudbu do adresáře s hudbou (paths.music_dir) — bez souborů nehraje žádná zóna.",
    "outbox": "Neodeslané RPC čekají ve frontě — po obnovení internetu se odešlou samy; přetrvává-li, zkontrolujte párování.",
    "code_cache": "Cache kódů chybí/je stará — proveďte synchronizaci (Velín → Synchronizovat) nebo zkontrolujte internet.",
    "lockout": "PIN lockout po neplatných pokusech — vyprší sám; zkontrolujte, zda někdo nehádá kódy.",
    "errors": "Projděte události (Velín → Události pobočky / journalctl -u motogo-controller).",
    "update": "Poslední aktualizace selhala — spusťte ji znovu z Velína nebo zkontrolujte log aktualizace.",
    "reboot_required": "OS vyžaduje restart po záplatách — naplánujte restart mimo provoz (Velín → Restart OS).",
    "cpu_temp": "Vysoká teplota CPU — zkontrolujte chlazení/ventilaci skříně jednotky.",
    "throttled": "Raspberry hlásí podpětí/throttling — zkontrolujte napájecí zdroj (5 V / 5 A) a kabel USB-C.",
    "disk": "Málo místa na disku — smažte staré logy/hudbu (journalctl --vacuum-size=200M).",
    "mem": "Málo volné paměti — restartujte jednotku mimo provoz a sledujte, zda se opakuje.",
    "ntp": "Čas není synchronizovaný — zkontrolujte internet (timedatectl); platnost kódů se hodnotí špatně.",
    "not_ready": "Jednotka není připravena (start/přestavba HW) — vyčkejte, případně zkontrolujte log.",
    "config_problems": "Opravte HW mapu ve Velíně (Pobočky → Samoobsluha → Zóny) — s chybnou mapou se zóny nespouští.",
    "no_zones": "Jednotka nemá žádné zóny — spárujte ji a nastavte HW mapu dveří ve Velíně (Samoobsluha → Zóny).",
    "contact_polarity": "Stav dveří nesedí se vstupem: ve Velíně u zóny → „Test kontaktu (20 s)“ (dveře během testu otevřít a zavřít) — verdikt řekne, zda otočit „Zavřeno =“ (tlačítko Otočit polaritu), nebo opravit zapojení COM–DGND / DI.",
    "missing_role": "Doplňte roli {role} zóny {zone} v HW mapě (Velín → Samoobsluha → Zóny).",
    "door_without_hw": "Dveře {label} nemají HW mapu (zone/lock/contact) — bez ní se neotevřou; nastavte ji ve Velíně.",
    "duplicate": "Stejný kanál ve dvou rolích — opravte HW mapu (každé relé/vstup jen jednou).",
    "timings": "Zkontrolujte časování ve Velíně (Samoobsluha → Časování).",
    "zone.light": "Relé {dev} R{ch}: zkontrolujte vodič ke světlu a svorky relé; modul musí být v Normal mode.",
    "zone.signal": "Shelly signalizace zóny je offline — zkontrolujte napájení Shelly a síť.",
    "zone.audio": "Zkontrolujte mpv (USB zvukovku), hudbu v music_dir a relé audio selektoru zóny.",
    "zone.contact": "Kontakt dveří: zkontrolujte NC kontakt, vodič do DI vstupu WAV617 a closed_level v HW mapě.",
    "zone.lock": "Zámek: modul WAV645 musí být online a relé zámku v klidu ROZEPNUTÉ — sepnuté relé = zámek pod proudem, odpojte modul.",
    "zone.shelly": "Shelly světlo: zkontrolujte napájení LED pásku, nastavení kanálu (light id) v HW mapě a Light.Set.",
    "zone.fault": "Poruchu zóny řeší kontakt/I/O: zavřete dveře, ověřte moduly; stav se obnoví sám nebo přes all_off.",
    "zone.io": "I/O zóny offline — zkontrolujte uvedené moduly (LAN, napájení).",
    "zone.skipped": "Spusťte diagnostiku znovu, až kóje nebude obsazená / porucha odezní.",
    "zone.test": "HW test zóny trvá příliš dlouho — zkontrolujte odezvu modulů/Shelly (ping, LAN) a spusťte diagnostiku znovu.",
    # venek (zóna bez dveří, kontrakt §B/§C) — světlo = relé Waveshare, hudba jen v režimu multi
    "outdoor_light": "Zkontrolujte relé venkovního osvětlení {dev} R{ch} (vodič ke světlu, svorky relé) a jistič venkovního okruhu; "
                     "modul musí být v Normal mode.",
    "outdoor_audio": "Venek hraje jen v režimu multi: nastavte audio výstup venku ve Velíně (Samoobsluha → hardware → Venek) a zkontrolujte "
                     "zvukovou kartu výstupu (CARD=Venek), mpv a hudbu v music_dir.",
    "outdoor_config": "Venek je v HW mapě bez světla i audio výstupu — doplňte je ve Velíně (Samoobsluha → hardware → Venek) nebo venek vymažte.",
    "power": "Zkontrolujte měnič/monitor FV (power_status_url) — URL musí vracet JSON v LAN jednotky.",
    "power_soc": "Nízké nabití baterie — zkontrolujte FV výrobu a spotřebu.",
    "camera": "Kamera {name} neodpovídá — zkontrolujte napájení, LAN a URL ({url_kind}) ve Velíně (Samoobsluha → Kamery).",
    "provision_addr": "Jednotka nemá na {iface} pomocnou adresu 192.168.1.253 (tovární síť Waveshare) — moduly z výroby (192.168.1.254) "
                      "nenajde a nenastaví jim IP. Aktualizujte software z Velína (instaluje dispečer 50-motogo-lan-addr) a restartujte jednotku.",
    "provision_no_lan": "Rozhraní {iface} nemá žádnou IPv4 adresu — zkontrolujte kabel do switche modulů; profil motogo-lan / dispečer 50-motogo-lan-addr.",
    "provision_none": "Žádný modul Waveshare neodpověděl na vyhledávání (UDP 1092): zkontrolujte napájení modulů (LED PWR), kabel a LED LINK "
                      "na modulu i switchi, případně že switch nefiltruje broadcast. Modul se hlásí i z tovární adresy 192.168.1.254.",
    "provision_pending": "Modul {mac} na {ip} není na žádné adrese z HW mapy — jednotka mu nastaví IP chybějícího zařízení automaticky "
                         "(do ~1 min; stejný modul nejvýš jednou za 5 min). Přetrvává-li, zkontrolujte typ modulu v mapě (WAV617 = 8 vstupů, WAV645 = 16 relé).",
    "provision_extra": "Modul {mac} na {ip} není v HW mapě a žádné zařízení nechybí — nadbytečný/cizí modul, nebo v mapě chybí jeho zařízení (Velín → Samoobsluha).",
    "provision_missing": "Zařízení {name} ({host}) neodpovídá a na LAN není žádný volný modul k přiřazení — modul chybí, je bez napájení, nebo ho drží jiná adresa mimo síť jednotky.",
    "net_outages": "Výpadky internetu: pobočka jede JEN přes LTE a modem SIM7600 v režimu QMI padá z USB (kernel -71). Trvalé řešení = režim RNDIS: Velín → karta jednotky → „Modem → RNDIS (stabilní)“ (jednotka se po 3 USB resetech za 24 h přepne i sama, událost LTE_MODE). Dál zkontrolujte anténu, SIM (PIN vypnutý, data) a signál (RSRP > −105 dBm).",
    "modem_gone": "Modem SIM7600 mizí z USB / z ModemManageru (kernel -71, HARDWARE.md „Známá závada“): health ho resetuje, ale pomáhá jen dočasně. Trvalé řešení = přepnout modem do režimu RNDIS (Velín → karta jednotky → „Modem → RNDIS (stabilní)“); když nepomůže ani RNDIS, jiný USB kabel/port nebo jiný modem.",
    "gateway_wifi": "Jednotka je na Wi-Fi (test mimo pobočku) — v pořádku pro testování, ale na pobočce Wi-Fi není: LTE modem MUSÍ fungovat sám. Zkontrolujte sekci LTE a Historie sítě; pokud modem chybí (no_modem), přepněte ho do RNDIS z karty jednotky.",
    "lan_unknown": "V LAN je Modbus/Shelly zařízení mimo HW mapu — cizí/ nové zařízení nebo špatná IP v mapě.",
    "lan_subnet": "Podsíť je pro scan příliš velká/neplatná — upravte diagnostics.scan_subnets (max /22).",
    "step": "Krok diagnostiky selhal/vypršel — spusťte znovu; opakuje-li se, zkontrolujte log motogo-controller.",
}


def hint(key: str, **fmt: Any) -> str:
    try:
        return HINTS.get(key, "").format(**fmt)
    except (KeyError, IndexError):
        return HINTS.get(key, "")
