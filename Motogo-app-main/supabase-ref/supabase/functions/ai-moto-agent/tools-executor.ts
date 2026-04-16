// ===== ai-moto-agent/tools-executor.ts =====
// Tool execution logic — database queries for each tool

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export async function executeTool(
  toolName: string,
  input: Record<string, unknown>,
  supabaseAdmin: SupabaseClient,
  userId: string,
): Promise<unknown> {
  switch (toolName) {
    case 'get_active_booking': {
      const { data, error } = await supabaseAdmin
        .from('bookings')
        .select(`
          id, status, payment_status, start_date, end_date, pickup_time,
          total_price, extras_price, pickup_method, return_method,
          mileage_start, mileage_end, notes, booking_source,
          motorcycles(
            id, model, brand, spz, engine_type, engine_cc, power_kw, power_hp,
            weight_kg, has_abs, has_asc, features, manual_url, description,
            ideal_usage, category, fuel_tank_l, seat_height_mm, color, mileage,
            year, license_required, image_url
          )
        `)
        .eq('user_id', userId)
        .in('status', ['active', 'confirmed', 'reserved'])
        .order('start_date', { ascending: false })
        .limit(10)

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Zákazník nemá žádnou aktivní ani nadcházející rezervaci.' }
      const active = data.find(b => b.status === 'active')
      if (active) return active
      if (data.length > 1) return { multiple_bookings: data, message: 'Zákazník má více rezervací. Zeptej se, o kterou motorku jde.' }
      return data[0]
    }

    case 'get_booking_history': {
      const limit = typeof input.limit === 'number' ? input.limit : 10
      const { data, error } = await supabaseAdmin
        .from('bookings')
        .select(`
          id, status, payment_status, start_date, end_date, total_price,
          pickup_method, return_method, mileage_start, mileage_end, rating,
          motorcycles(id, model, brand, category, engine_cc)
        `)
        .eq('user_id', userId)
        .order('start_date', { ascending: false })
        .limit(limit)

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Zákazník nemá žádné rezervace.' }
      return data
    }

    case 'get_motorcycle_manual': {
      let query = supabaseAdmin.from('motorcycles').select('*')

      if (input.motorcycle_id) {
        query = query.eq('id', input.motorcycle_id)
      } else if (input.brand || input.model) {
        if (input.brand) query = query.ilike('brand', `%${input.brand}%`)
        if (input.model) query = query.ilike('model', `%${input.model}%`)
      } else {
        return { error: 'Musíš zadat motorcycle_id nebo brand+model.' }
      }

      const { data, error } = await query.limit(1)
      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Motorka nenalezena.' }
      return data[0]
    }

    case 'search_troubleshooting': {
      const searchQuery = (input.query as string) || ''

      const { data: kbData, error: kbError } = await supabaseAdmin
        .from('motorcycle_knowledge_base')
        .select('*')
        .or(`title.ilike.%${searchQuery}%,content.ilike.%${searchQuery}%`)
        .limit(5)

      if (!kbError && kbData && kbData.length > 0) {
        return kbData
      }

      return {
        message: 'Tabulka motorcycle_knowledge_base neexistuje nebo neobsahuje relevantní data. Použij obecné diagnostické znalosti.',
        general_tips: {
          red_light: 'Červená kontrolka = STOP, vypněte motor. Možné příčiny: přehřátí, únik oleje, porucha elektroniky. -> SOS',
          oil_light: 'Zastavte, vypněte motor. Zkontrolujte hladinu oleje. Při podtečení NEJEĎTE. -> SOS',
          abs_light: 'Bliká = ABS dočasně deaktivováno. Zkuste restart. Trvale svítí = opatrně brzdění.',
          temperature: 'OKAMŽITĚ zastavte. Počkejte 15-20 min. NIKDY neotevírejte víčko na horký motor. -> SOS',
          wont_start: '1) Spojka stisknutá, 2) Neutrál, 3) Kill switch=RUN, 4) Stojan zasunutý, 5) Choke u karburátorů.',
          flat_tire: 'Snižte rychlost, nebrzděte prudce, zastavte u krajnice. NEJEĎTE dál. -> SOS',
          oil_leak: 'ZASTAVTE OKAMŽITĚ, vypněte motor. -> SOS',
          battery_low: 'Pod 12V omezte spotřebu. Jumpstart: + na +, - na kostru. -> SOS',
          fuel_reserve: 'Rezerva 2-4 L, dojezd cca 30-80 km. Tankujte Natural 95/98.',
          rain_riding: 'Rain mód, snížená rychlost, zvětšené rozestupy, pozor na kanály a listy.',
          emergency_contact: 'MotoGo24: +420 774 256 271 (24/7), info@motogo24.cz',
        },
      }
    }

    case 'get_fleet_overview': {
      const { data, error } = await supabaseAdmin
        .from('motorcycles')
        .select('id, brand, model, category, engine_cc, engine_type, power_kw, power_hp, has_abs, has_asc, license_required, seat_height_mm, weight_kg, fuel_tank_l, price_weekday, price_weekend, image_url')
        .eq('status', 'active')
        .order('brand')

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Žádné aktivní motorky ve flotile.' }
      return data
    }

    default:
      return { error: `Neznámý nástroj: ${toolName}` }
  }
}
