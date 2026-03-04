/**
 * MotoGo24 — Edge Function: Upload Handler
 * Validace, zpracování a upload souborů do Supabase Storage.
 *
 * POST /functions/v1/upload-handler
 * Auth: Bearer JWT
 * Body: FormData s file + metadata { bucket, path }
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getUserClient } from '../_shared/supabase-client.ts';
import type { StorageBucket, UploadResponse } from '../_shared/types.ts';

const ALLOWED_MIME_TYPES: Record<string, string> = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB
const MAX_IMAGE_WIDTH = 1200;
const VALID_BUCKETS: StorageBucket[] = ['documents', 'media', 'sos-photos'];

/** Zmenší obrázek na maximální šířku (jednoduchý resize přes canvas-like approach). */
async function resizeImage(
  imageBytes: Uint8Array,
  mimeType: string,
): Promise<Uint8Array> {
  // V Deno Edge Functions nemáme přímý přístup k sharp nebo canvas.
  // Používáme ImageMagick přes WASM nebo vracíme originál, pokud resize není dostupný.
  // Pro produkci: Supabase Image Transformation nebo external API.
  try {
    const { ImageMagick, initialize, MagickFormat } = await import(
      'https://esm.sh/imagemagick-deno@0.0.31'
    );
    await initialize();

    let outputFormat: MagickFormat;
    switch (mimeType) {
      case 'image/png':
        outputFormat = MagickFormat.Png;
        break;
      case 'image/webp':
        outputFormat = MagickFormat.WebP;
        break;
      default:
        outputFormat = MagickFormat.Jpeg;
    }

    let resizedBytes: Uint8Array = imageBytes;

    ImageMagick.read(imageBytes, (img: { width: number; resize: (w: number, h: number) => void; write: (fmt: unknown, cb: (data: Uint8Array) => void) => void }) => {
      if (img.width > MAX_IMAGE_WIDTH) {
        const ratio = MAX_IMAGE_WIDTH / img.width;
        const newHeight = Math.round(img.width * ratio);
        img.resize(MAX_IMAGE_WIDTH, newHeight);
      }
      img.write(outputFormat, (data: Uint8Array) => {
        resizedBytes = data;
      });
    });

    return resizedBytes;
  } catch (resizeErr: unknown) {
    const msg = resizeErr instanceof Error ? resizeErr.message : String(resizeErr);
    console.error('Image resize unavailable, using original:', msg);
    return imageBytes;
  }
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

    // Parse multipart form data
    const formData = await req.formData();
    const file = formData.get('file') as File | null;
    const bucket = formData.get('bucket') as StorageBucket | null;
    const path = formData.get('path') as string | null;

    if (!file) {
      return errorResponse('Missing file in form data');
    }

    if (!bucket || !VALID_BUCKETS.includes(bucket)) {
      return errorResponse(`Invalid bucket. Valid buckets: ${VALID_BUCKETS.join(', ')}`);
    }

    if (!path) {
      return errorResponse('Missing path in form data');
    }

    // Validace MIME typu
    const mimeType = file.type;
    if (!ALLOWED_MIME_TYPES[mimeType]) {
      return errorResponse(`Invalid file type: ${mimeType}. Allowed: PDF, JPG, PNG, WebP`);
    }

    // Validace velikosti
    if (file.size > MAX_FILE_SIZE) {
      return errorResponse(`File too large: ${(file.size / 1024 / 1024).toFixed(1)}MB. Max: 10MB`);
    }

    let fileBytes = new Uint8Array(await file.arrayBuffer());
    const isImage = mimeType.startsWith('image/');

    // Resize obrázků
    if (isImage) {
      fileBytes = await resizeImage(fileBytes, mimeType);
    }

    // Upload do Supabase Storage
    const admin = getAdminClient();
    const storagePath = `${user.id}/${path}`;

    const { error: uploadError } = await admin.storage
      .from(bucket)
      .upload(storagePath, fileBytes, {
        contentType: mimeType,
        upsert: true,
      });

    if (uploadError) {
      console.error('Storage upload error:', uploadError);
      return errorResponse(`Upload failed: ${uploadError.message}`, 500);
    }

    // Získej public URL
    const { data: urlData } = admin.storage
      .from(bucket)
      .getPublicUrl(storagePath);

    const response: UploadResponse = {
      success: true,
      url: urlData.publicUrl,
      path: storagePath,
      size: fileBytes.length,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('upload-handler error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
