/**
 * MotoGo24 — Edge Function: Generate Document
 * Generování PDF dokumentů ze šablon (smlouvy, protokoly, faktury).
 *
 * POST /functions/v1/generate-document
 * Auth: Bearer JWT (admin)
 * Body: { template_type, booking_id?, customer_id?, custom_data? }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import type { DocumentGenerateRequest, DocumentGenerateResponse } from '../_shared/types.ts';

/** Nahradí proměnné v HTML šabloně reálnými daty. */
function fillTemplate(html: string, variables: Record<string, string>): string {
  let result = html;
  for (const [key, value] of Object.entries(variables)) {
    result = result.replaceAll(`{{${key}}}`, value);
  }
  return result;
}

/** Konvertuje HTML na PDF přes external API. */
async function htmlToPdf(html: string): Promise<Uint8Array> {
  const pdfApiUrl = Deno.env.get('PDF_API_URL');
  const pdfApiKey = Deno.env.get('PDF_API_KEY');

  if (pdfApiUrl && pdfApiKey) {
    // Použij external PDF API (např. html2pdf.app, PDFShift, DocRaptor)
    const resp = await fetch(pdfApiUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${pdfApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        html,
        options: {
          format: 'A4',
          margin: { top: '20mm', bottom: '20mm', left: '15mm', right: '15mm' },
        },
      }),
    });

    if (!resp.ok) {
      const errBody = await resp.text();
      throw new Error(`PDF API error: ${errBody}`);
    }

    return new Uint8Array(await resp.arrayBuffer());
  }

  // Fallback: vrátíme HTML jako "PDF" s hlavičkou
  // V produkci by se mělo použít skutečné PDF API
  const encoder = new TextEncoder();
  const wrappedHtml = `<!DOCTYPE html>
<html lang="cs">
<head>
  <meta charset="UTF-8">
  <style>
    @page { size: A4; margin: 20mm; }
    body { font-family: 'Montserrat', Arial, sans-serif; color: #1a2e22; line-height: 1.6; }
    .header { text-align: center; border-bottom: 2px solid #74FB71; padding-bottom: 16px; margin-bottom: 24px; }
    .header h1 { color: #74FB71; margin: 0; }
    .footer { margin-top: 32px; padding-top: 16px; border-top: 1px solid #ccc; text-align: center; font-size: 11px; color: #666; }
    table { width: 100%; border-collapse: collapse; margin: 16px 0; }
    table td, table th { padding: 8px 12px; border: 1px solid #ddd; text-align: left; }
    table th { background: #f0fdf0; font-weight: 600; }
  </style>
</head>
<body>${html}</body>
</html>`;
  return encoder.encode(wrappedHtml);
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

    // Ověř JWT + admin roli
    const userClient = getUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return errorResponse('Unauthorized', 401);
    }

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

    const body = await req.json() as DocumentGenerateRequest;
    if (!body.template_type) {
      return errorResponse('Missing template_type');
    }

    // Načti šablonu z document_templates
    const { data: template, error: templateError } = await admin
      .from('document_templates')
      .select('id, name, html_content, variables')
      .eq('type', body.template_type)
      .eq('is_active', true)
      .single();

    if (templateError || !template) {
      return errorResponse(`Template not found: ${body.template_type}`, 404);
    }

    // Načti data z DB
    const variables: Record<string, string> = {};
    const now = new Date();
    variables['datum'] = now.toLocaleDateString('cs-CZ');
    variables['cas'] = now.toLocaleTimeString('cs-CZ');
    variables['rok'] = String(now.getFullYear());

    if (body.booking_id) {
      const { data: booking, error: bookingError } = await admin
        .from('bookings')
        .select(`
          id, start_date, end_date, total_price, status, payment_status, payment_method,
          user_id,
          profiles!inner ( full_name, email, phone, address, id_number, license_group ),
          motorcycles!inner ( model, license_plate, vin, year, category,
            branches!inner ( name, address, phone, email, ico, dic )
          )
        `)
        .eq('id', body.booking_id)
        .single();

      if (bookingError || !booking) {
        return errorResponse('Booking not found', 404);
      }

      const profile = booking.profiles as unknown as {
        full_name: string;
        email: string;
        phone: string;
        address: string;
        id_number: string;
        license_group: string;
      };
      const moto = booking.motorcycles as unknown as {
        model: string;
        license_plate: string;
        vin: string;
        year: number;
        category: string;
        branches: {
          name: string;
          address: string;
          phone: string;
          email: string;
          ico: string;
          dic: string;
        };
      };

      variables['booking_id'] = (booking.id as string).substring(0, 8).toUpperCase();
      variables['start_date'] = booking.start_date as string;
      variables['end_date'] = booking.end_date as string;
      variables['total_price'] = String(booking.total_price);
      variables['payment_status'] = booking.payment_status as string;
      variables['payment_method'] = booking.payment_method as string ?? '';

      variables['customer_name'] = profile.full_name;
      variables['customer_email'] = profile.email;
      variables['customer_phone'] = profile.phone;
      variables['customer_address'] = profile.address ?? '';
      variables['customer_id_number'] = profile.id_number ?? '';
      variables['customer_license'] = profile.license_group ?? '';

      variables['moto_model'] = moto.model;
      variables['moto_spz'] = moto.license_plate;
      variables['moto_vin'] = moto.vin ?? '';
      variables['moto_year'] = String(moto.year ?? '');
      variables['moto_category'] = moto.category ?? '';

      variables['branch_name'] = moto.branches.name;
      variables['branch_address'] = moto.branches.address;
      variables['branch_phone'] = moto.branches.phone ?? '';
      variables['branch_email'] = moto.branches.email ?? '';
      variables['branch_ico'] = moto.branches.ico ?? '';
      variables['branch_dic'] = moto.branches.dic ?? '';
    }

    if (body.customer_id) {
      const { data: customer, error: customerError } = await admin
        .from('profiles')
        .select('full_name, email, phone, address, id_number, license_group')
        .eq('id', body.customer_id)
        .single();

      if (!customerError && customer) {
        variables['customer_name'] = customer.full_name as string;
        variables['customer_email'] = customer.email as string;
        variables['customer_phone'] = customer.phone as string ?? '';
        variables['customer_address'] = customer.address as string ?? '';
      }
    }

    // Merge custom data
    if (body.custom_data) {
      for (const [key, value] of Object.entries(body.custom_data)) {
        variables[key] = String(value);
      }
    }

    // Vyplň šablonu
    const filledHtml = fillTemplate(template.html_content as string, variables);

    // Konvertuj na PDF
    const pdfBytes = await htmlToPdf(filledHtml);

    // Ulož do Storage
    const documentId = crypto.randomUUID();
    const storagePath = `generated/${documentId}.pdf`;

    const { error: uploadError } = await admin.storage
      .from('documents')
      .upload(storagePath, pdfBytes, {
        contentType: 'application/pdf',
        upsert: false,
      });

    if (uploadError) {
      console.error('Document upload error:', uploadError);
      return errorResponse('Failed to save document', 500);
    }

    const { data: urlData } = admin.storage
      .from('documents')
      .getPublicUrl(storagePath);

    // Vytvoř záznam v generated_documents
    await admin.from('generated_documents').insert({
      id: documentId,
      template_id: template.id as string,
      template_type: body.template_type,
      booking_id: body.booking_id ?? null,
      customer_id: body.customer_id ?? null,
      file_url: urlData.publicUrl,
      file_path: storagePath,
      variables,
      generated_by: user.id,
    });

    const response: DocumentGenerateResponse = {
      success: true,
      pdf_url: urlData.publicUrl,
      document_id: documentId,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('generate-document error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
