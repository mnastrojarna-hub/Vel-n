// Write tools: Bookings, Fleet, Customers, SOS
// Hláška k odmítnutému přesunu (admin_move_motorcycle, migrace 20260929g) — pro AI i operátora
function moveErr(r) {
  const u = r?.unit === 'mh' ? 'MH' : 'km';
  switch(r?.error){
    case 'km_required':
      return 'Přesun mezi obslužnou a samoobslužnou pobočkou vyžaduje aktuální stav tachometru — zeptej se operátora a zadej odometer_km.' + (Number(r.last) > 0 ? ` Poslední známý stav: ${r.last} ${u}.` : ' Poslední stav není evidován.');
    case 'km_below_last':
      return `Zadaný stav je NIŽŠÍ než poslední evidovaný (${r.last} ${u}). Ověř u operátora; je-li správně, zopakuj s force=true.`;
    case 'km_jump':
      return `Zadaný stav je o víc než ${r.unit === 'mh' ? '500 MH' : '20 000 km'} vyšší než poslední evidovaný (${r.last} ${u}) — překlep? Je-li správně, zopakuj s force=true.`;
    case 'km_below_purchase':
      return `Stav je nižší než stav při koupi motorky (${r.purchase_km} ${u}) — takovou hodnotu nelze zadat.`;
    case 'invalid_km':
      return 'Neplatný stav tachometru (celé číslo 0–9 999 999).';
    case 'forbidden':
      return 'Přesun motorky smí provést jen admin.';
    default:
      return `Přesun motorky se nezdařil: ${r?.error || 'neznámá chyba'}`;
  }
}
// sbUser = klient s JWT operátora — RPC s kontrolou is_admin() (service role má auth.uid() NULL → forbidden)
export async function execWriteCore(name, input, sb, dryRun, sbUser) {
  switch(name){
    // === BOOKING ===
    case 'update_booking_status':
      {
        const { booking_id, new_status, reason } = input;
        const { data: booking } = await sb.from('bookings').select('id, status, payment_status, user_id, moto_id, total_price, start_date, end_date').eq('id', booking_id).single();
        if (!booking) return {
          error: 'Rezervace nenalezena'
        };
        const summary = `Změna stavu rezervace z "${booking.status}" na "${new_status}"${reason ? ` (důvod: ${reason})` : ''}`;
        if (dryRun) return {
          status: 'preview',
          summary,
          current: booking
        };
        const update = {
          status: new_status
        };
        if (new_status === 'cancelled') {
          update.cancelled_at = new Date().toISOString();
          update.cancellation_reason = reason || 'AI Copilot';
        }
        if (new_status === 'completed') update.returned_at = new Date().toISOString();
        if (new_status === 'active') update.picked_up_at = new Date().toISOString();
        const { error } = await sb.from('bookings').update(update).eq('id', booking_id);
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary,
          booking_id
        };
      }
    case 'update_booking_details':
      {
        const { booking_id, ...fields } = input;
        const { data: booking } = await sb.from('bookings').select('id, notes, start_date, end_date').eq('id', booking_id).single();
        if (!booking) return {
          error: 'Rezervace nenalezena'
        };
        const changes = Object.keys(fields).filter((k)=>fields[k] !== undefined);
        const summary = `Úprava rezervace: ${changes.join(', ')}`;
        if (dryRun) return {
          status: 'preview',
          summary,
          current: booking,
          changes: fields
        };
        const { error } = await sb.from('bookings').update(fields).eq('id', booking_id);
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary,
          booking_id
        };
      }
    case 'confirm_booking_payment':
      {
        const { booking_id, method } = input;
        const { data: booking } = await sb.from('bookings').select('id, status, payment_status, total_price').eq('id', booking_id).single();
        if (!booking) return {
          error: 'Rezervace nenalezena'
        };
        const summary = `Potvrzení platby ${booking.total_price} Kč (${method || 'neznámá metoda'})`;
        if (dryRun) return {
          status: 'preview',
          summary,
          current: booking
        };
        const { error } = await sb.rpc('confirm_payment', {
          p_booking_id: booking_id,
          p_method: method || 'cash'
        });
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary,
          booking_id
        };
      }
    // === FLEET ===
    case 'update_motorcycle':
      {
        // Pobočka se mění JEN přes RPC admin_move_motorcycle (2026-09-29): obslužná ↔ samoobslužná vyžaduje
        // odometer_km (aktuální stav tachometru), nižší než evidovaný / velký skok jen s force. Odebrání pobočky přímo.
        const { motorcycle_id, branch_id, odometer_km, force, ...fields } = input;
        const { data: moto } = await sb.from('motorcycles').select('id, model, brand, spz, status, mileage, tracking_unit, branch_id').eq('id', motorcycle_id).single();
        if (!moto) return {
          error: 'Motorka nenalezena'
        };
        const toBranch = branch_id || null;
        const move = branch_id !== undefined && toBranch !== moto.branch_id;
        const km = odometer_km == null || odometer_km === '' ? null : Number(odometer_km);
        if (km != null && !(Number.isInteger(km) && km >= 0)) return {
          error: 'odometer_km musí být celé číslo ≥ 0 (stav tachometru).'
        };
        let needKm = false;
        if (move && toBranch) {
          const { data: brs } = await sb.from('branches').select('id, type').in('id', [
            moto.branch_id,
            toBranch
          ].filter(Boolean));
          const self = (id)=>!!id && (brs || []).find((b)=>b.id === id)?.type === 'samoobslužná';
          needKm = self(moto.branch_id) !== self(toBranch);
        }
        if (needKm && km == null) return {
          error: moveErr({
            error: 'km_required',
            last: moto.mileage,
            unit: moto.tracking_unit
          }),
          current: moto
        };
        if (needKm) {
          const { data: act } = await sb.from('bookings').select('id').eq('moto_id', motorcycle_id).eq('status', 'active').gte('end_date', new Date().toISOString().slice(0, 10)).limit(1);
          if (act?.length) return {
            error: 'Motorka je u zákazníka (probíhající pronájem) — přesun mezi obslužnou a samoobslužnou pobočkou až po vrácení.'
          };
        }
        const changes = [
          ...Object.keys(fields).filter((k)=>fields[k] !== undefined),
          ...move ? [
            'branch_id'
          ] : []
        ];
        const summary = `Úprava motorky ${moto.model} (${moto.spz}): ${changes.join(', ')}${move && km != null ? ` · stav tachometru ${km} ${moto.tracking_unit === 'mh' ? 'MH' : 'km'}` : ''}`;
        if (dryRun) return {
          status: 'preview',
          summary,
          current: moto,
          changes: {
            ...fields,
            ...move ? {
              branch_id: toBranch,
              odometer_km: km
            } : {}
          }
        };
        if (move && toBranch) {
          if (!sbUser) return {
            error: 'Přesun motorky vyžaduje přihlášeného admina — proveď ho ve Velíně (Flotila → Přesunout).'
          };
          const { data: mv, error: mvErr } = await sbUser.rpc('admin_move_motorcycle', {
            p_moto_id: motorcycle_id,
            p_branch_id: toBranch,
            p_km: km,
            p_force: !!force,
            p_note: 'AI Copilot'
          });
          if (mvErr) return {
            error: mvErr.message
          };
          if (!mv?.ok) return {
            error: moveErr(mv),
            detail: mv
          };
        } else if (move) fields.branch_id = null;
        if (Object.keys(fields).some((k)=>fields[k] !== undefined)) {
          const { error } = await sb.from('motorcycles').update(fields).eq('id', motorcycle_id);
          if (error) return {
            error: error.message
          };
        }
        return {
          status: 'executed',
          summary,
          motorcycle_id
        };
      }
    case 'update_motorcycle_pricing':
      {
        const { motorcycle_id, ...prices } = input;
        const { data: moto } = await sb.from('motorcycles').select('id, model, spz, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun').eq('id', motorcycle_id).single();
        if (!moto) return {
          error: 'Motorka nenalezena'
        };
        const summary = `Úprava ceníku ${moto.model} (${moto.spz})`;
        if (dryRun) return {
          status: 'preview',
          summary,
          current: moto,
          new_prices: prices
        };
        const { error } = await sb.from('motorcycles').update(prices).eq('id', motorcycle_id);
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary,
          motorcycle_id
        };
      }
    case 'update_branch':
      {
        const { branch_id, ...fields } = input;
        const { data: branch } = await sb.from('branches').select('id, name, is_open, type').eq('id', branch_id).single();
        if (!branch) return {
          error: 'Pobočka nenalezena'
        };
        const changes = Object.keys(fields).filter((k)=>fields[k] !== undefined);
        const summary = `Úprava pobočky "${branch.name}": ${changes.join(', ')}`;
        // Změna obslužná ↔ samoobslužná s motorkami = jejich přesun bez stavu tachometru → odmítnout už v náhledu
        // (stejně jako Velín BranchModal; v DB strážce 20260929h, chyba branch_type_change_requires_odometer)
        const typeBlocked = 'Typ pobočky (obslužná ↔ samoobslužná) nelze změnit, dokud jsou na ní přiřazené motorky — nejdřív je přesuň (update_motorcycle s odometer_km), pak změň typ.';
        if (fields.type !== undefined && fields.type === 'samoobslužná' !== (branch.type === 'samoobslužná')) {
          const { count } = await sb.from('motorcycles').select('id', {
            count: 'exact',
            head: true
          }).eq('branch_id', branch_id).neq('status', 'retired');
          if ((count || 0) > 0) return {
            error: typeBlocked
          };
        }
        if (dryRun) return {
          status: 'preview',
          summary,
          current: branch,
          changes: fields
        };
        const { error } = await sb.from('branches').update(fields).eq('id', branch_id);
        if (error && error.message.includes('branch_type_change_requires_odometer')) return {
          error: typeBlocked
        };
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary,
          branch_id
        };
      }
    case 'update_branch_accessories':
      {
        const { branch_id, type, size, quantity } = input;
        const summary = `Nastavení příslušenství: ${type} ${size} = ${quantity} ks`;
        if (dryRun) return {
          status: 'preview',
          summary,
          data: {
            branch_id,
            type,
            size,
            quantity
          }
        };
        const { error } = await sb.from('branch_accessories').upsert({
          branch_id,
          type,
          size,
          quantity
        }, {
          onConflict: 'branch_id,type,size'
        });
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary
        };
      }
    // === CUSTOMER ===
    case 'update_customer':
      {
        const { customer_id, ...fields } = input;
        const { data: profile } = await sb.from('profiles').select('id, full_name, email, phone, is_blocked').eq('id', customer_id).single();
        if (!profile) return {
          error: 'Zákazník nenalezen'
        };
        const changes = Object.keys(fields).filter((k)=>fields[k] !== undefined);
        const summary = `Úprava zákazníka "${profile.full_name}": ${changes.join(', ')}`;
        if (dryRun) return {
          status: 'preview',
          summary,
          current: profile,
          changes: fields
        };
        if (fields.is_blocked === true) {
          fields.blocked_at = new Date().toISOString();
        }
        if (fields.is_blocked === false) {
          fields.blocked_at = null;
          fields.blocked_reason = null;
        }
        const { error } = await sb.from('profiles').update(fields).eq('id', customer_id);
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary,
          customer_id
        };
      }
    case 'send_customer_message':
      {
        const { customer_id, content, channel } = input;
        const { data: profile } = await sb.from('profiles').select('id, full_name, phone, email').eq('id', customer_id).single();
        if (!profile) return {
          error: 'Zákazník nenalezen'
        };
        const ch = channel || 'in_app';
        const summary = `Odeslání zprávy zákazníkovi "${profile.full_name}" přes ${ch}`;
        if (dryRun) return {
          status: 'preview',
          summary,
          recipient: profile,
          channel: ch,
          content_preview: content.slice(0, 100)
        };
        const { error } = await sb.from('admin_messages').insert({
          user_id: customer_id,
          type: 'info',
          title: 'Zpráva z MotoGo24',
          message: content,
          created_at: new Date().toISOString()
        });
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary,
          customer_id
        };
      }
    // === SOS ===
    case 'update_sos_incident':
      {
        const { incident_id, ...fields } = input;
        const { data: inc } = await sb.from('sos_incidents').select('id, title, status, severity').eq('id', incident_id).single();
        if (!inc) return {
          error: 'SOS incident nenalezen'
        };
        const changes = Object.keys(fields).filter((k)=>fields[k] !== undefined);
        const summary = `Úprava SOS "${inc.title}": ${changes.join(', ')}`;
        if (dryRun) return {
          status: 'preview',
          summary,
          current: inc,
          changes: fields
        };
        if (fields.status === 'resolved') fields.resolved_at = new Date().toISOString();
        const { error } = await sb.from('sos_incidents').update(fields).eq('id', incident_id);
        if (error) return {
          error: error.message
        };
        return {
          status: 'executed',
          summary,
          incident_id
        };
      }
    default:
      return null;
  }
}
