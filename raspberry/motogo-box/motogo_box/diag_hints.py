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
    "gateway_missing": "Zkontrolujte LTE profil motogo-lte (nmcli con up motogo-lte) — bez výchozí brány není internet.",
    "gateway_eth": "Výchozí brána vede přes LAN modulů — v profilu motogo-lan nastavte never-default (ipv4.never-default yes).",
    "dns_missing": "Bez DNS serveru nefunguje Velín — zkontrolujte profil LTE (DNS z operátora) nebo nastavte 1.1.1.1.",
    "iface_down": "Rozhraní {name} nemá adresu/spojení — zkontrolujte kabel do switche modulů a profil motogo-lan.",
    "lte": "Zkontrolujte SIM (PIN vypnutý, kredit), anténu a profil motogo-lte; stav: mmcli -m any.",
    "internet": "Internet nedostupný — zkontrolujte LTE (signál, SIM) a výchozí bránu; DNS: resolvectl status.",
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
    "lan_unknown": "V LAN je Modbus/Shelly zařízení mimo HW mapu — cizí/ nové zařízení nebo špatná IP v mapě.",
    "lan_subnet": "Podsíť je pro scan příliš velká/neplatná — upravte diagnostics.scan_subnets (max /22).",
    "step": "Krok diagnostiky selhal/vypršel — spusťte znovu; opakuje-li se, zkontrolujte log motogo-controller.",
}


def hint(key: str, **fmt: Any) -> str:
    try:
        return HINTS.get(key, "").format(**fmt)
    except (KeyError, IndexError):
        return HINTS.get(key, "")
