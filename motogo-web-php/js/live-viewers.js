/* MotoGo24 — kolik lidí si právě prohlíží web / motorku (2026-10-22, sociální důkaz).
   Data = RPC get_live_viewers (migrace 20261022b): skuteční návštěvníci z visitor_log, bez botů.
   Nic se nevymýšlí — text se ukáže jen při skutečně nenulovém počtu OSTATNÍCH (bez sebe sama):
   [data-live-site] = web za 10 min (≥ 2 další), [data-live-moto="<uuid>"] = detail motorky
   za hodinu (≥ 1 další), jinak dnes (≥ 3). Stránky jsou v page cache → čte se až v prohlížeči. */
(function run() {
  var d = document, w = window;
  // MOTOGO_CONFIG (URL + anon klíč) sype layout.php inline až na konci stránky
  if (d.readyState === 'loading') { d.addEventListener('DOMContentLoaded', run); return; }
  var site = d.querySelector('[data-live-site]'), motoEl = d.querySelector('[data-live-moto]');
  if (!site && !motoEl) return;
  var cfg = w.MOTOGO_CONFIG || {}, url = cfg.SUPABASE_URL || (w.MG_LIVE || {}).url, key = cfg.SUPABASE_ANON_KEY || (w.MG_LIVE || {}).key;
  if (!url || !key) return;
  var lang = (d.documentElement.lang || 'cs').slice(0, 2);
  // {one|few|many|other} — výběr přes Intl.PluralRules
  var TX = {
    cs: { site: { one: 'Právě s tebou vybírá motorku ještě {n} člověk', few: 'Právě s tebou vybírají motorku ještě {n} lidé', other: 'Právě s tebou vybírá motorku ještě {n} lidí' },
          hour: { one: 'Za poslední hodinu si ji prohlédl ještě {n} zájemce', few: 'Za poslední hodinu si ji prohlédli ještě {n} zájemci', other: 'Za poslední hodinu si ji prohlédlo ještě {n} zájemců' },
          today: { one: 'Dnes si ji prohlédl {n} zájemce', few: 'Dnes si ji prohlédli {n} zájemci', other: 'Dnes si ji prohlédlo už {n} zájemců' } },
    en: { site: { one: '{n} other person is choosing a bike right now', other: '{n} other people are choosing a bike right now' },
          hour: { one: '{n} other person viewed this bike in the last hour', other: '{n} other people viewed this bike in the last hour' },
          today: { one: '{n} person viewed this bike today', other: '{n} people viewed this bike today' } },
    de: { site: { one: 'Gerade wählt noch {n} Person ein Motorrad', other: 'Gerade wählen noch {n} Personen ein Motorrad' },
          hour: { one: 'In der letzten Stunde hat sich noch {n} Person dieses Motorrad angesehen', other: 'In der letzten Stunde haben sich noch {n} Personen dieses Motorrad angesehen' },
          today: { one: 'Heute hat sich {n} Person dieses Motorrad angesehen', other: 'Heute haben sich {n} Personen dieses Motorrad angesehen' } },
    es: { site: { one: 'Ahora mismo {n} persona más está eligiendo moto', other: 'Ahora mismo {n} personas más están eligiendo moto' },
          hour: { one: 'En la última hora la ha visto {n} persona más', other: 'En la última hora la han visto {n} personas más' },
          today: { one: 'Hoy la ha visto {n} persona', other: 'Hoy la han visto {n} personas' } },
    fr: { site: { one: 'En ce moment, {n} autre personne choisit une moto', other: 'En ce moment, {n} autres personnes choisissent une moto' },
          hour: { one: '{n} autre personne a consulté cette moto dans l’heure', other: '{n} autres personnes ont consulté cette moto dans l’heure' },
          today: { one: '{n} personne a consulté cette moto aujourd’hui', other: '{n} personnes ont consulté cette moto aujourd’hui' } },
    nl: { site: { one: 'Op dit moment kiest nog {n} persoon een motor', other: 'Op dit moment kiezen nog {n} mensen een motor' },
          hour: { one: 'Het afgelopen uur bekeek nog {n} persoon deze motor', other: 'Het afgelopen uur bekeken nog {n} mensen deze motor' },
          today: { one: 'Vandaag bekeek {n} persoon deze motor', other: 'Vandaag bekeken {n} mensen deze motor' } },
    pl: { site: { one: 'Teraz motocykl wybiera jeszcze {n} osoba', few: 'Teraz motocykl wybierają jeszcze {n} osoby', other: 'Teraz motocykl wybiera jeszcze {n} osób' },
          hour: { one: 'W ostatniej godzinie oglądała go jeszcze {n} osoba', few: 'W ostatniej godzinie oglądały go jeszcze {n} osoby', other: 'W ostatniej godzinie oglądało go jeszcze {n} osób' },
          today: { one: 'Dziś oglądała go {n} osoba', few: 'Dziś oglądały go {n} osoby', other: 'Dziś oglądało go już {n} osób' } },
    uk: { site: { one: 'Зараз мотоцикл обирає ще {n} людина', few: 'Зараз мотоцикл обирають ще {n} людини', other: 'Зараз мотоцикл обирають ще {n} людей' },
          hour: { one: 'За останню годину його переглянула ще {n} людина', few: 'За останню годину його переглянули ще {n} людини', other: 'За останню годину його переглянули ще {n} людей' },
          today: { one: 'Сьогодні його переглянула {n} людина', few: 'Сьогодні його переглянули {n} людини', other: 'Сьогодні його переглянули вже {n} людей' } }
  }[lang] || null;
  if (!TX) return;
  function say(forms, n) {
    var c = 'other';
    try { c = new Intl.PluralRules(lang).select(n); } catch (e) { c = n === 1 ? 'one' : 'other'; }
    return (forms[c] || forms.other).replace('{n}', n);
  }
  function show(el, text) {
    if (!el || !text) return;
    el.innerHTML = '<i aria-hidden="true"></i><span></span>';
    el.lastChild.textContent = text;
    el.hidden = false;
  }
  var id = motoEl ? motoEl.getAttribute('data-live-moto') : null;
  fetch(url + '/rest/v1/rpc/get_live_viewers', {
    method: 'POST',
    headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_moto_id: id })
  }).then(function (r) { return r.ok ? r.json() : null; }).then(function (v) {
    if (!v) return;
    var others = Math.max(0, (v.site_now | 0) - 1);
    if (site && others >= 2) show(site, say(TX.site, others));
    if (motoEl) {
      var h = Math.max(0, (v.moto_hour | 0) - 1), t = v.moto_today | 0;
      if (h >= 1) show(motoEl, say(TX.hour, h)); else if (t >= 3) show(motoEl, say(TX.today, t));
    }
  }).catch(function () {});
})();
