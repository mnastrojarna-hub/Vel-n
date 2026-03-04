/**
 * MotoGo24 — Edge Function: Generate Tax
 * Generování daňových přiznání a podkladů pro Finanční správu ČR.
 * Podporuje DPH měsíční/čtvrtletní, DPPO roční, kontrolní hlášení.
 *
 * POST /functions/v1/generate-tax
 * Auth: Bearer JWT (admin, superadmin only)
 * Body: { type, period_from, period_to }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import type { TaxRequest, TaxResponse, TaxType } from '../_shared/types.ts';

interface DphData {
  zaklad_dan_21: number;
  dan_21: number;
  zaklad_dan_15: number;
  dan_15: number;
  zaklad_dan_10: number;
  dan_10: number;
  odpocet_zaklad_21: number;
  odpocet_dan_21: number;
  odpocet_zaklad_15: number;
  odpocet_dan_15: number;
  odpocet_zaklad_10: number;
  odpocet_dan_10: number;
  celkem_dan: number;
  celkem_odpocet: number;
  k_odvodu: number;
}

/** Vypočítá DPH základ a daň za období. */
async function calculateDPH(
  admin: ReturnType<typeof getAdminClient>,
  periodFrom: string,
  periodTo: string,
): Promise<DphData> {
  // Příjmy (výstupní DPH)
  const { data: incomeEntries } = await admin
    .from('accounting_entries')
    .select('amount, vat_rate, vat_amount')
    .eq('type', 'income')
    .gte('date', periodFrom)
    .lte('date', periodTo);

  // Výdaje (vstupní DPH — odpočet)
  const { data: expenseEntries } = await admin
    .from('accounting_entries')
    .select('amount, vat_rate, vat_amount')
    .eq('type', 'expense')
    .gte('date', periodFrom)
    .lte('date', periodTo);

  const result: DphData = {
    zaklad_dan_21: 0, dan_21: 0,
    zaklad_dan_15: 0, dan_15: 0,
    zaklad_dan_10: 0, dan_10: 0,
    odpocet_zaklad_21: 0, odpocet_dan_21: 0,
    odpocet_zaklad_15: 0, odpocet_dan_15: 0,
    odpocet_zaklad_10: 0, odpocet_dan_10: 0,
    celkem_dan: 0, celkem_odpocet: 0, k_odvodu: 0,
  };

  // Výstupní DPH (z příjmů)
  for (const entry of incomeEntries ?? []) {
    const amount = Number(entry.amount ?? 0);
    const vatRate = Number(entry.vat_rate ?? 21);
    const vatAmount = Number(entry.vat_amount ?? 0) || Math.round(amount * (vatRate / (100 + vatRate)) * 100) / 100;
    const baseAmount = amount - vatAmount;

    switch (vatRate) {
      case 21:
        result.zaklad_dan_21 += baseAmount;
        result.dan_21 += vatAmount;
        break;
      case 15:
        result.zaklad_dan_15 += baseAmount;
        result.dan_15 += vatAmount;
        break;
      case 10:
        result.zaklad_dan_10 += baseAmount;
        result.dan_10 += vatAmount;
        break;
    }
  }

  // Vstupní DPH (z výdajů — odpočet)
  for (const entry of expenseEntries ?? []) {
    const amount = Number(entry.amount ?? 0);
    const vatRate = Number(entry.vat_rate ?? 21);
    const vatAmount = Number(entry.vat_amount ?? 0) || Math.round(amount * (vatRate / (100 + vatRate)) * 100) / 100;
    const baseAmount = amount - vatAmount;

    switch (vatRate) {
      case 21:
        result.odpocet_zaklad_21 += baseAmount;
        result.odpocet_dan_21 += vatAmount;
        break;
      case 15:
        result.odpocet_zaklad_15 += baseAmount;
        result.odpocet_dan_15 += vatAmount;
        break;
      case 10:
        result.odpocet_zaklad_10 += baseAmount;
        result.odpocet_dan_10 += vatAmount;
        break;
    }
  }

  result.celkem_dan = result.dan_21 + result.dan_15 + result.dan_10;
  result.celkem_odpocet = result.odpocet_dan_21 + result.odpocet_dan_15 + result.odpocet_dan_10;
  result.k_odvodu = Math.round((result.celkem_dan - result.celkem_odpocet) * 100) / 100;

  return result;
}

/** Generuje XML pro DPH přiznání ve formátu EPO portálu Finanční správy ČR. */
function generateDphXml(
  data: DphData,
  periodFrom: string,
  periodTo: string,
  dic: string,
): string {
  const periodYear = periodFrom.substring(0, 4);
  const periodMonth = periodFrom.substring(5, 7);

  return `<?xml version="1.0" encoding="UTF-8"?>
<Pisemnost nazevSW="MotoGo24" verzeSW="1.0">
  <DPHDP3 verzePis="03.02">
    <VetaD
      k_uladis="DPH"
      dokession="B"
      rok="${periodYear}"
      mesic="${periodMonth}"
      d_poddam="${new Date().toISOString().split('T')[0]}"
      dic="${dic}"
    />
    <VetaA
      obrat23="${Math.round(data.zaklad_dan_21)}"
      dan23="${Math.round(data.dan_21)}"
      obrat5="${Math.round(data.zaklad_dan_15)}"
      dan5="${Math.round(data.dan_15)}"
      pln23="${Math.round(data.odpocet_zaklad_21)}"
      odp_tuz23_nar="${Math.round(data.odpocet_dan_21)}"
      pln5="${Math.round(data.odpocet_zaklad_15)}"
      odp_tuz5_nar="${Math.round(data.odpocet_dan_15)}"
    />
    <VetaC
      dan_zocelk="${Math.round(data.celkem_dan)}"
      odp_zocelk="${Math.round(data.celkem_odpocet)}"
      dano_da="${data.k_odvodu >= 0 ? Math.round(data.k_odvodu) : 0}"
      dano_no="${data.k_odvodu < 0 ? Math.round(Math.abs(data.k_odvodu)) : 0}"
    />
  </DPHDP3>
</Pisemnost>`;
}

/** Generuje XML pro kontrolní hlášení. */
async function generateKontrolniHlaseni(
  admin: ReturnType<typeof getAdminClient>,
  periodFrom: string,
  periodTo: string,
  dic: string,
): Promise<{ data: Record<string, unknown>; xml: string }> {
  // Načti faktury za období
  const { data: invoices } = await admin
    .from('invoices')
    .select('id, number, customer_name, customer_dic, total_amount, vat_amount, issue_date, type')
    .gte('issue_date', periodFrom)
    .lte('issue_date', periodTo)
    .order('issue_date');

  const issuedInvoices = (invoices ?? []).filter((i) => i.type === 'issued');
  const receivedInvoices = (invoices ?? []).filter((i) => i.type === 'received');

  const periodYear = periodFrom.substring(0, 4);
  const periodMonth = periodFrom.substring(5, 7);

  // Sekce A — přijatá plnění nad 10 000 Kč
  const sectionA = issuedInvoices
    .filter((i) => Number(i.total_amount) > 10000)
    .map((i) => `    <VetaA
      dic_odb="${(i.customer_dic as string) ?? ''}"
      c_evid_dd="${i.number}"
      dppd="${i.issue_date}"
      zakl_dane1="${Math.round(Number(i.total_amount) - Number(i.vat_amount ?? 0))}"
      dan1="${Math.round(Number(i.vat_amount ?? 0))}"
    />`);

  // Sekce B — uskutečněná plnění nad 10 000 Kč
  const sectionB = receivedInvoices
    .filter((i) => Number(i.total_amount) > 10000)
    .map((i) => `    <VetaB
      dic_dod="${(i.customer_dic as string) ?? ''}"
      c_evid_dd="${i.number}"
      dppd="${i.issue_date}"
      zakl_dane1="${Math.round(Number(i.total_amount) - Number(i.vat_amount ?? 0))}"
      dan1="${Math.round(Number(i.vat_amount ?? 0))}"
    />`);

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<Pisemnost nazevSW="MotoGo24" verzeSW="1.0">
  <DPHKH1 verzePis="02.01">
    <VetaD
      k_uladis="KH"
      rok="${periodYear}"
      mesic="${periodMonth}"
      d_poddam="${new Date().toISOString().split('T')[0]}"
      dic="${dic}"
    />
${sectionA.join('\n')}
${sectionB.join('\n')}
  </DPHKH1>
</Pisemnost>`;

  return {
    data: {
      section_a_count: sectionA.length,
      section_b_count: sectionB.length,
      total_invoices: invoices?.length ?? 0,
    },
    xml,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return errorResponse('Missing Authorization header', 401);
    }

    const userClient = getUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return errorResponse('Unauthorized', 401);
    }

    // Ověř superadmin roli
    const admin = getAdminClient();
    const { data: adminUser, error: adminError } = await admin
      .from('admin_users')
      .select('id, role')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .single();

    if (adminError || !adminUser) {
      return errorResponse('Admin access required', 403);
    }

    if (adminUser.role !== 'superadmin') {
      return errorResponse('Superadmin role required for tax generation', 403);
    }

    const body = await req.json() as TaxRequest;
    if (!body.type || !body.period_from || !body.period_to) {
      return errorResponse('Missing required fields: type, period_from, period_to');
    }

    const validTypes: TaxType[] = ['dph_monthly', 'dph_quarterly', 'dppo_annual', 'kontrolni_hlaseni'];
    if (!validTypes.includes(body.type)) {
      return errorResponse(`Invalid type. Valid types: ${validTypes.join(', ')}`);
    }

    // Načti DIČ firmy
    const { data: companyVar } = await admin
      .from('cms_variables')
      .select('value')
      .eq('key', 'company_dic')
      .single();
    const dic = (companyVar?.value as string) ?? Deno.env.get('COMPANY_DIC') ?? '';

    let responseData: TaxResponse;

    switch (body.type) {
      case 'dph_monthly':
      case 'dph_quarterly': {
        const dphData = await calculateDPH(admin, body.period_from, body.period_to);
        const xml = generateDphXml(dphData, body.period_from, body.period_to, dic);

        // Ulož do tax_records
        const { data: taxRecord } = await admin
          .from('tax_records')
          .insert({
            type: body.type,
            period_from: body.period_from,
            period_to: body.period_to,
            data: dphData,
            xml_content: xml,
            status: 'draft',
            generated_by: user.id,
          })
          .select('id')
          .single();

        responseData = {
          success: true,
          data: dphData as unknown as Record<string, unknown>,
          xml,
          tax_record_id: taxRecord?.id as string,
        };
        break;
      }

      case 'dppo_annual': {
        // DPPO — zjednodušený výpočet
        const { data: incomeTotal } = await admin
          .from('accounting_entries')
          .select('amount')
          .eq('type', 'income')
          .gte('date', body.period_from)
          .lte('date', body.period_to);

        const { data: expenseTotal } = await admin
          .from('accounting_entries')
          .select('amount')
          .eq('type', 'expense')
          .gte('date', body.period_from)
          .lte('date', body.period_to);

        const totalIncome = incomeTotal?.reduce((s, e) => s + Number(e.amount), 0) ?? 0;
        const totalExpense = expenseTotal?.reduce((s, e) => s + Number(e.amount), 0) ?? 0;
        const zakladDane = Math.max(0, totalIncome - totalExpense);
        const danSazba = 0.21; // 21% DPPO sazba
        const dan = Math.round(zakladDane * danSazba);

        const dppoData = {
          celkove_prijmy: totalIncome,
          celkove_vydaje: totalExpense,
          zaklad_dane: zakladDane,
          sazba_dane: danSazba * 100,
          dan: dan,
          obdobi_od: body.period_from,
          obdobi_do: body.period_to,
        };

        const { data: taxRecord } = await admin
          .from('tax_records')
          .insert({
            type: body.type,
            period_from: body.period_from,
            period_to: body.period_to,
            data: dppoData,
            status: 'draft',
            generated_by: user.id,
          })
          .select('id')
          .single();

        responseData = {
          success: true,
          data: dppoData,
          tax_record_id: taxRecord?.id as string,
        };
        break;
      }

      case 'kontrolni_hlaseni': {
        const { data: khData, xml } = await generateKontrolniHlaseni(
          admin,
          body.period_from,
          body.period_to,
          dic,
        );

        const { data: taxRecord } = await admin
          .from('tax_records')
          .insert({
            type: body.type,
            period_from: body.period_from,
            period_to: body.period_to,
            data: khData,
            xml_content: xml,
            status: 'draft',
            generated_by: user.id,
          })
          .select('id')
          .single();

        responseData = {
          success: true,
          data: khData,
          xml,
          tax_record_id: taxRecord?.id as string,
        };
        break;
      }

      default:
        return errorResponse('Unknown tax type');
    }

    return jsonResponse(responseData);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('generate-tax error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
