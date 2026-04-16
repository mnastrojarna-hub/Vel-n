async function enrichMOTOS(){
  if(typeof MOTOS === 'undefined' || !window.supabase) return;
  try {
    // Ulož originál při prvním volání
    if(!_MOTOS_ORIG){
      _MOTOS_ORIG = MOTOS.map(function(m){
        return JSON.parse(JSON.stringify(m));
      });
    }

    // Načti VŠECHNY motorky z DB
    var r = await window.supabase
      .from('motorcycles')
      .select('id, model, status, mileage, year, category, price_weekday, price_weekend, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, branch_id, image_url, images, stk_valid_until, engine_type, engine_cc, power_kw, power_hp, torque_nm, weight_kg, fuel_tank_l, seat_height_mm, license_required, has_abs, has_asc, description, ideal_usage, features, manual_url, next_service_date, branches(name, address, city, is_open)');
    var dbMotos = (r.data || []);

    // Vytvoř mapu podle normalizovaného jména
    var dbMap = {};
    dbMotos.forEach(function(dm){
      var key = dm.model.toLowerCase().replace(/\s+/g, '');
      dbMap[key] = dm;
    });

    // Přebuduj MOTOS z originálu — jen aktivní motorky
    var fresh = [];
    for(var i = 0; i < _MOTOS_ORIG.length; i++){
      var m = JSON.parse(JSON.stringify(_MOTOS_ORIG[i]));
      var key = m.name.toLowerCase().replace(/\s+/g, '');
      var db = dbMap[key];

      // Motorka není v DB nebo není active → přeskoč
      if(!db || db.status !== 'active') continue;
      // Zobrazujeme všechny pobočky včetně zavřených

      // Přiřaď _db objekt
      m._db = {
        id: db.id,
        status: db.status,
        mileage: db.mileage,
        branch_id: db.branch_id,
        branch_name: db.branches ? db.branches.name : null,
        branch_address: db.branches ? db.branches.address : null,
        branch_city: db.branches ? db.branches.city : null,
        branch_is_open: db.branches ? db.branches.is_open : null,
        image_url: db.image_url,
        images: db.images,
        stk_valid_until: db.stk_valid_until,
        next_service_date: db.next_service_date,
      };

      // Fotky z Velínu (Supabase storage) mají přednost před statickými
      if(db.image_url) m.img = db.image_url;
      if(db.images && db.images.length) m.imgs = db.images;

      // Aktualizuj specs z DB (pokud jsou vyplněny ve Velínu)
      if(db.engine_type || db.power_kw || db.torque_nm || db.weight_kg){
        var dbSpecs = [];
        if(db.engine_type || db.engine_cc) dbSpecs.push({l:'Motor', v: (db.engine_cc ? db.engine_cc+' cc ' : '')+(db.engine_type||'')});
        if(db.power_kw) dbSpecs.push({l:'Výkon', v: db.power_kw+' kW'+(db.power_hp ? ' / '+db.power_hp+' k' : '')});
        if(db.torque_nm) dbSpecs.push({l:'Točivý moment', v: db.torque_nm+' Nm'});
        if(db.weight_kg) dbSpecs.push({l:'Hmotnost', v: db.weight_kg+' kg'});
        if(db.fuel_tank_l) dbSpecs.push({l:'Nádrž', v: db.fuel_tank_l+' L'});
        if(db.seat_height_mm) dbSpecs.push({l:'Sedlo', v: db.seat_height_mm+' mm'});
        if(db.license_required) dbSpecs.push({l:'ŘP kategorie', v: db.license_required});
        var absAsc = [];
        if(db.has_abs !== null) absAsc.push(db.has_abs ? 'ABS' : '—');
        if(db.has_asc !== null) absAsc.push(db.has_asc ? 'ASC' : '—');
        if(absAsc.length) dbSpecs.push({l:'ABS / ASC', v: absAsc.join(' / ')});
        if(dbSpecs.length > 0) m.specs = dbSpecs;
      }
      // Aktualizuj kategorii, ŘP a výkon z DB (přepiš hardcoded)
      if(db.category){ var _nc=db.category.toLowerCase().replace(/[íé]/g,function(c){return c==='í'?'i':'e';}); m.cat=_nc; }
      if(db.license_required) m.rp = db.license_required;
      if(db.power_kw) m.vykon = db.power_kw;

      if(db.description) m.desc = db.description;
      if(db.ideal_usage && db.ideal_usage.length) m.vyuziti = db.ideal_usage;
      if(db.features && db.features.length) m.feats = db.features;
      if(db.manual_url) m.manual = db.manual_url;

      // Aktualizuj pobočku z DB (přepiš hardcoded loc)
      if(db.branches){
        m.loc = (db.branches.address || '') + ', ' + (db.branches.city || '') + (db.year ? ' · ' + db.year : '');
        m.branch = db.branch_id;
        m._db.branch_name = db.branches.name;
        m._db.branch_address = db.branches.address;
        m._db.branch_city = db.branches.city;
      }

      // Aktualizuj ceny z DB (přepiš hardcoded pricing)
      if(db.price_weekday || db.price_weekend){
        m.pricing = {
          po: Number(db.price_mon || db.price_weekday) || m.pricing.po,
          ut: Number(db.price_tue || db.price_weekday) || m.pricing.ut,
          st: Number(db.price_wed || db.price_weekday) || m.pricing.st,
          ct: Number(db.price_thu || db.price_weekday) || m.pricing.ct,
          pa: Number(db.price_fri || db.price_weekend) || m.pricing.pa,
          so: Number(db.price_sat || db.price_weekend) || m.pricing.so,
          ne: Number(db.price_sun || db.price_weekend) || m.pricing.ne,
        };
      }

      fresh.push(m);
    }

    // Přidej motorky z DB které NEMAJÍ lokální protějšek (přidány přes Velín)
    var usedKeys = {};
    for(var ui = 0; ui < fresh.length; ui++){
      usedKeys[fresh[ui].name.toLowerCase().replace(/\s+/g, '')] = true;
    }
    dbMotos.forEach(function(db){
      if(db.status !== 'active') return;
      var key = db.model.toLowerCase().replace(/\s+/g, '');
      if(usedKeys[key]) return; // již máme z lokálních dat
      // Vytvoř novou motorku čistě z DB dat
      var nm = {
        id: 'db-' + db.id.substr(0,8),
        name: db.model,
        loc: (db.branches ? db.branches.address + ', ' + db.branches.city : 'Mezná') + (db.year ? ' · ' + db.year : ''),
        img: db.image_url || '',
        imgs: db.images && db.images.length ? db.images : (db.image_url ? [db.image_url] : []),
        avail: true,
        cat: (db.category || 'cestovni').toLowerCase().replace(/[íé]/g,function(c){return c==='í'?'i':'e';}),
        rp: db.license_required || 'A',
        vykon: db.power_kw || 0,
        desc: db.description || db.model,
        specs: [],
        feats: db.features || [],
        vyuziti: db.ideal_usage || [],
        pricing: {
          po: Number(db.price_mon || db.price_weekday) || 2000,
          ut: Number(db.price_tue || db.price_weekday) || 2000,
          st: Number(db.price_wed || db.price_weekday) || 2000,
          ct: Number(db.price_thu || db.price_weekday) || 2000,
          pa: Number(db.price_fri || db.price_weekend) || 2500,
          so: Number(db.price_sat || db.price_weekend) || 2500,
          ne: Number(db.price_sun || db.price_weekend) || 2500,
        },
        branch: db.branch_id || 'mezna',
        manual: db.manual_url || '',
        price: (Number(db.price_weekday) || 2000).toLocaleString('cs-CZ') + ' Kč',
        _db: {
          id: db.id,
          status: db.status,
          mileage: db.mileage,
          branch_id: db.branch_id,
          branch_name: db.branches ? db.branches.name : null,
          branch_address: db.branches ? db.branches.address : null,
          branch_city: db.branches ? db.branches.city : null,
          image_url: db.image_url,
          images: db.images,
          stk_valid_until: db.stk_valid_until,
          next_service_date: db.next_service_date,
        }
      };
      // Build specs
      var ds = [];
      if(db.engine_type || db.engine_cc) ds.push({l:'Motor', v: (db.engine_cc ? db.engine_cc+' cc ' : '')+(db.engine_type||'')});
      if(db.power_kw) ds.push({l:'Výkon', v: db.power_kw+' kW'+(db.power_hp ? ' / '+db.power_hp+' k' : '')});
      if(db.torque_nm) ds.push({l:'Točivý moment', v: db.torque_nm+' Nm'});
      if(db.weight_kg) ds.push({l:'Hmotnost', v: db.weight_kg+' kg'});
      if(db.fuel_tank_l) ds.push({l:'Nádrž', v: db.fuel_tank_l+' L'});
      if(db.seat_height_mm) ds.push({l:'Sedlo', v: db.seat_height_mm+' mm'});
      if(db.license_required) ds.push({l:'ŘP kategorie', v: db.license_required});
      var absAsc = [];
      if(db.has_abs !== null) absAsc.push(db.has_abs ? 'ABS' : '—');
      if(db.has_asc !== null) absAsc.push(db.has_asc ? 'ASC' : '—');
      if(absAsc.length) ds.push({l:'ABS / ASC', v: absAsc.join(' / ')});
      nm.specs = ds;
      fresh.push(nm);
    });

    // Nahraď MOTOS čerstvým polem (in-place pro zachování reference)
    MOTOS.length = 0;
    for(var j = 0; j < fresh.length; j++) MOTOS.push(fresh[j]);

    window._enrichMOTOSDone = true;
    // Naplň filtr poboček na domovské stránce
    _populateBranchFilter();
  } catch(e){
    console.error('[API] enrichMOTOS chyba:', e);
  }
}
