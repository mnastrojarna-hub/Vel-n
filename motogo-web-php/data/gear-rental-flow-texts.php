<?php
// ===== MotoGo24 — Půjčení výbavy: CS defaulty textů rezervačního toku (2026-10-23) =====
// Výpůjčka výbavy = rezervace (bookings.booking_kind='gear', RPC create_web_gear_booking):
// přihlášení u existujícího e-mailu, dárkový poukaz, souhlasy, platba, potvrzení,
// nahrání dokladu totožnosti, návrat k nezaplacené rezervaci (?resume=). Spojuje se
// v gearRentalDefaults() (data/gear-rental-texts.php); překlady lang/v2/<lang>/gear-flow.php.
// HTML jen v agree_vop / agree_gdpr (sanitizeHtml); {x} = zástupné hodnoty z JS.

function gearRentalFlowDefaults() {
    return [
        // Kalendář, výbava
        'cal_clear' => 'Zrušit výběr',
        'size_out' => 'Ve vybraném termínu není volná',
        'size_dropped' => 'Velikost {size} ({item}) ve vybraném termínu není volná — vyber prosím jinou.',
        'ss_cap_note' => 'Na samoobslužné pobočce půjčujeme helmy ve velikostech S–3XL a ostatní kusy nejvýš do 4XL.',
        // Poukaz
        'voucher_toggle' => 'Mám dárkový poukaz',
        'voucher_ph' => 'Kód dárkového poukazu',
        'voucher_apply' => 'Použít',
        'voucher_remove' => 'Odebrat poukaz',
        'voucher_line' => 'Dárkový poukaz {code}',
        'voucher_bad' => 'Tenhle poukaz použít nejde — zkontroluj kód. U výbavy platí jen dárkové poukazy, ne slevové kódy.',
        'voucher_wait' => 'Ověřuji poukaz…',
        'voucher_need' => 'Poukaz ověříme, až vybereš pobočku, termín a výbavu s velikostmi.',
        'to_pay' => 'K úhradě',
        // Souhlasy (HTML)
        'agree_vop' => 'Souhlasím s <a href="/dokumenty/obchodni-podminky" target="_blank" rel="noopener">obchodními podmínkami</a>.',
        'agree_gdpr' => 'Souhlasím se <a href="/dokumenty/zasady-ochrany-osobnich-udaju" target="_blank" rel="noopener">zpracováním osobních údajů</a>.',
        // Přihlášení (e-mail už má účet)
        'login_title' => 'Tenhle e-mail u nás už má účet',
        'login_help' => 'Přihlas se svým heslem a rezervaci výbavy hned dokončíme.',
        'login_password' => 'Heslo',
        'login_submit' => 'Přihlásit a pokračovat',
        'login_busy' => 'Přihlašuji…',
        'login_err' => 'Přihlášení se nepovedlo. Zkontroluj e-mail a heslo.',
        'login_forgot' => 'Zapomenuté heslo?',
        'login_back' => '← Zpět na přihlášení',
        'forgot_help' => 'Pošleme ti e-mailem ověřovací kód, pak si nastavíš nové heslo.',
        'forgot_send' => 'Poslat ověřovací kód',
        'forgot_busy' => 'Odesílám…',
        'forgot_sent' => 'Kód jsme poslali na {email}. Platí 1 hodinu — zkontroluj i spam.',
        'forgot_code' => 'Kód z e-mailu',
        'forgot_pw' => 'Nové heslo (aspoň 8 znaků)',
        'forgot_pw2' => 'Nové heslo znovu',
        'forgot_submit' => 'Nastavit heslo a pokračovat',
        'forgot_err_code' => 'Kód není správný nebo už vypršel.',
        'forgot_err_pw' => 'Heslo musí mít aspoň 8 znaků a obě musí být stejná.',
        'forgot_err_same' => 'Nové heslo musí být jiné než to současné.',
        'logged_as' => 'Přihlášen(a) jako {email}',
        'logout' => 'Odhlásit',
        'err_server' => 'Server je teď nedostupný. Zkus to prosím za chvíli.',
        // Chyby rezervace a platby
        'err_mismatch' => 'Jsi přihlášen(a) jako {email}. Rezervaci dokonči s tímto e-mailem, nebo se odhlas.',
        'err_too_many' => 'Během krátké chvíle přišlo moc rezervací. Zkus to prosím za hodinu, nebo nám zavolej.',
        'err_stock' => 'Ve vybraném termínu už není volné: {items}. Vyber prosím jinou velikost nebo termín.',
        'err_min' => 'Částka je pod minimem platby kartou (15 Kč). Přidej prosím další kus nebo den.',
        'err_pay' => 'Platbu se nepodařilo spustit. Rezervace zůstala uložená — zkus to prosím znovu.',
        'err_pay_busy' => 'Platba už běží v jiném okně. Dokonči ji tam, nebo to zkus za pár minut znovu.',
        // Návrat k rezervaci (?resume=)
        'res_title' => 'Dokonči rezervaci výbavy',
        'res_lead' => 'Rezervace čeká na zaplacení. Hned po platbě ti pošleme potvrzení e-mailem.',
        'res_pay' => 'Zaplatit {amount}',
        'res_nf' => 'Rezervaci jsme nenašli, nebo už skončila. Vytvoř si prosím novou.',
        'res_cancelled' => 'Tahle rezervace je zrušená. Vytvoř si prosím novou.',
        'res_completed' => 'Tahle výpůjčka je už ukončená. Díky, že sis výbavu půjčil(a) u nás!',
        'res_new' => 'Nová rezervace výbavy',
        'ok_manage' => 'Upravit rezervaci',
        'ok_return_self' => 'Vrať ji nejpozději poslední den výpůjčky do šatny na stejné pobočce, zavři dveře a na displeji potvrď, že vracíš všechno.',
        // Doklad totožnosti
        'docs_title' => 'Nahraj doklad totožnosti',
        'docs_lead' => 'Výbavu půjčujeme proti dokladu totožnosti (občanka z obou stran, nebo pas) a od 18 let. Řidičák nepotřebuješ.',
        'docs_self' => 'Kódy k vyzvednutí výbavy ti pošleme, jakmile doklad nahraješ.',
        'docs_staffed' => 'Nahraj ho prosím hned — předání na pobočce pak bude rychlejší.',
        'docs_id' => 'Občanský průkaz',
        'docs_pass' => 'Cestovní pas',
        'docs_front' => 'Přední strana',
        'docs_back' => 'Zadní strana',
        'docs_page' => 'Stránka s fotkou a údaji',
        'docs_pick' => 'Vyfotit nebo nahrát',
        'docs_again' => 'Nahrát znovu',
        'docs_busy' => 'Nahrávám…',
        'docs_done' => 'Nahráno',
        'docs_err' => 'Nahrání se nepovedlo. Zkus to prosím znovu (JPG, PNG nebo PDF do 8 MB).',
        'docs_dob' => 'Datum narození',
        'docs_submit' => 'Odeslat doklad',
        'docs_checking' => 'Kontroluji…',
        'docs_ok' => 'Hotovo, doklad máme. Děkujeme!',
        'docs_need_files' => 'Nahraj prosím obě strany občanky, nebo pas.',
        'docs_need_front' => 'Chybí přední strana občanky.',
        'docs_need_back' => 'Chybí zadní strana občanky.',
        'docs_need_dob' => 'Doplň prosím datum narození.',
        'docs_age' => 'Výbavu půjčujeme od 18 let. Pokud je v údajích chyba, ozvi se nám prosím.',
        'docs_later' => 'Doklad můžeš nahrát i později přes odkaz v e-mailu.',
        // Odkaz na motorky
        'moto_title' => 'Potřebuješ i motorku?',
        'moto_text' => 'Vyber si motorku z naší nabídky — výbavu k ní přidáš rovnou v rezervaci motorky.',
        'moto_cta' => 'Prohlédnout motorky',
    ];
}
