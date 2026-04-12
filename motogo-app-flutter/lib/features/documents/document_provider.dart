import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import 'document_models.dart';

/// Resize image for OCR — max 1600px, 80% JPEG.
/// Mirrors _resizeForOCR from Capacitor doc-scanner-ocr.js.
/// Top-level so it can run in a background isolate via [compute].
Uint8List _resizeForOcr(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  const maxSize = 1600;
  if (decoded.width <= maxSize && decoded.height <= maxSize) return bytes;

  final resized = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: maxSize)
      : img.copyResize(decoded, height: maxSize);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}

/// User documents from Supabase — ID docs only (for verification screen).
final documentsProvider = FutureProvider<List<UserDocument>>((ref) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return [];
  final res = await MotoGoSupabase.client
      .from('documents')
      .select()
      .eq('user_id', user.id)
      .inFilter('type', ['id_card', 'drivers_license', 'passport'])
      .order('created_at', ascending: false);
  return (res as List).map((e) => UserDocument.fromJson(e)).toList();
});

/// Contracts & protocols from Supabase documents table.
final contractsProvider = FutureProvider<List<UserDocument>>((ref) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) {
    debugPrint('[CONTRACTS] No user logged in');
    return [];
  }
  debugPrint('[CONTRACTS] Fetching contracts for user ${user.id}');
  final res = await MotoGoSupabase.client
      .from('documents')
      .select()
      .eq('user_id', user.id)
      .inFilter('type', ['contract', 'protocol', 'vop', 'invoice_advance', 'payment_receipt', 'invoice_final', 'invoice_shop'])
      .order('created_at', ascending: false);
  final docs = (res as List).map((e) {
    debugPrint('[CONTRACTS] Doc: type=${e['type']}, file_path=${e['file_path']}, file_name=${e['file_name']}');
    return UserDocument.fromJson(e);
  }).toList();
  debugPrint('[CONTRACTS] Loaded ${docs.length} documents');
  return docs;
});

/// User invoices from Supabase.
final invoicesProvider = FutureProvider<List<UserInvoice>>((ref) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) {
    debugPrint('[INVOICES] No user logged in');
    return [];
  }
  debugPrint('[INVOICES] Fetching invoices for user ${user.id}');
  final res = await MotoGoSupabase.client
      .from('invoices')
      .select()
      .eq('customer_id', user.id)
      .order('created_at', ascending: false);
  final invoices = (res as List).map((e) {
    debugPrint('[INVOICES] Invoice: id=${e['id']}, type=${e['type']}, number=${e['number']}, pdf_path=${e['pdf_path']}');
    return UserInvoice.fromJson(e);
  }).toList();
  debugPrint('[INVOICES] Loaded ${invoices.length} invoices');
  return invoices;
});

/// Doc verification status from profile.
final docsVerifiedProvider = FutureProvider<DocsVerification>((ref) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return const DocsVerification();
  final res = await MotoGoSupabase.client.from('profiles')
      .select('id_verified_at, id_verified_until, license_verified_at, license_verified_until, passport_verified_at, passport_verified_until')
      .eq('id', user.id).maybeSingle();
  if (res == null) return const DocsVerification();
  return DocsVerification.fromJson(res);
});

class DocsVerification {
  final DateTime? idVerifiedAt;
  final DateTime? idVerifiedUntil;
  final DateTime? licenseVerifiedAt;
  final DateTime? licenseVerifiedUntil;
  final DateTime? passportVerifiedAt;
  final DateTime? passportVerifiedUntil;

  const DocsVerification({
    this.idVerifiedAt, this.idVerifiedUntil,
    this.licenseVerifiedAt, this.licenseVerifiedUntil,
    this.passportVerifiedAt, this.passportVerifiedUntil,
  });

  factory DocsVerification.fromJson(Map<String, dynamic> json) => DocsVerification(
    idVerifiedAt: _parseDate(json['id_verified_at']),
    idVerifiedUntil: _parseDate(json['id_verified_until']),
    licenseVerifiedAt: _parseDate(json['license_verified_at']),
    licenseVerifiedUntil: _parseDate(json['license_verified_until']),
    passportVerifiedAt: _parseDate(json['passport_verified_at']),
    passportVerifiedUntil: _parseDate(json['passport_verified_until']),
  );

  static DateTime? _parseDate(dynamic v) => v != null ? DateTime.tryParse(v.toString()) : null;

  bool get hasIdOrPassport => idVerifiedAt != null || passportVerifiedAt != null;
  bool get hasLicense => licenseVerifiedAt != null;
  bool get isComplete => hasIdOrPassport && hasLicense;
}

/// OCR scan via scan-document edge function.
/// Mirrors scanOCR from doc-scanner-ocr.js (Mindee v2 enqueue+poll).
/// Image is resized to max 1600px / 80% JPEG before sending (matching
/// the Capacitor _resizeForOCR behaviour).
Future<OcrResult?> scanDocument(XFile photo, ScanDocType docType) async {
  try {
    final rawBytes = await photo.readAsBytes();
    debugPrint('[DocScan] Raw photo: ${rawBytes.length} bytes');

    // Resize in background isolate — matches Capacitor's _resizeForOCR
    final bytes = await compute(_resizeForOcr, rawBytes);
    debugPrint('[DocScan] Resized photo: ${bytes.length} bytes');

    final base64Image = base64Encode(bytes);
    final user = MotoGoSupabase.currentUser;

    final res = await MotoGoSupabase.client.functions.invoke(
      'scan-document',
      body: {
        'image_base64': base64Image,
        'document_type': docType.apiType,
        'user_id': user?.id,
      },
    );

    final data = res.data as Map<String, dynamic>?;
    debugPrint('[DocScan] Response: success=${data?['success']}, '
        'fields=${data?['fields_count']}');
    if (data == null || data['success'] != true) {
      debugPrint('[DocScan] Scan failed: ${data?['error'] ?? 'unknown'}');
      return null;
    }

    final result = OcrResult.fromJson(data['data'] as Map<String, dynamic>);
    debugPrint('[DocScan] Parsed: firstName=${result.firstName}, '
        'lastName=${result.lastName}, idNumber=${result.idNumber}, '
        'licenseNumber=${result.licenseNumber}, '
        'licenseCategory=${result.licenseCategory}');
    return result;
  } catch (e) {
    debugPrint('[DocScan] Exception: $e');
    return null;
  }
}

/// Upload scanned document photo to Supabase Storage.
Future<String?> uploadDocPhoto(XFile photo, ScanDocType docType) async {
  try {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return null;
    final bytes = await photo.readAsBytes();
    final path = '${user.id}/${docType.storageType}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await MotoGoSupabase.client.storage.from('documents').uploadBinary(path, bytes);

    // Insert document record
    await MotoGoSupabase.client.from('documents').insert({
      'user_id': user.id,
      'type': docType.storageType,
      'file_name': docType.label,
      'file_path': path,
    });

    return path;
  } catch (_) {
    return null;
  }
}

/// Convert Czech date "d. m. yyyy" to ISO "yyyy-mm-dd".
/// Mirrors czToIso from api-enrichment-2.js.
String? _czDateToIso(String? v) {
  if (v == null || v.isEmpty) return null;
  final trimmed = v.trim();
  // Already ISO
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return trimmed;
  final m = RegExp(r'^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$').firstMatch(trimmed);
  if (m == null) return null;
  final day = m.group(1)!.padLeft(2, '0');
  final month = m.group(2)!.padLeft(2, '0');
  final year = m.group(3)!;
  return '$year-$month-$day';
}

/// Save OCR data to profile — mirrors apiSaveOcrToProfile from
/// api-enrichment-2.js. Saves all extracted fields including address
/// components (street, city, zip) from OP back side.
/// [docType] ensures verification flag is set even when specific fields
/// were not extracted by OCR (e.g. DL without license number).
Future<void> saveOcrToProfile(OcrResult result, {ScanDocType? docType}) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return;

  final updates = <String, dynamic>{};
  if (result.fullName.isNotEmpty) updates['full_name'] = result.fullName;
  if (result.dob != null) {
    final isoDob = _czDateToIso(result.dob);
    if (isoDob != null) updates['date_of_birth'] = isoDob;
  }
  // Address components from OP back — mirrors Capacitor apiSaveOcrToProfile
  if (result.street != null) updates['street'] = result.street;
  if (result.city != null) updates['city'] = result.city;
  if (result.zip != null) updates['zip'] = result.zip;
  if (result.idNumber != null) {
    updates['id_number'] = result.idNumber;
    updates['id_verified_at'] = DateTime.now().toIso8601String();
  }
  if (result.licenseNumber != null) {
    updates['license_number'] = result.licenseNumber;
    updates['license_verified_at'] = DateTime.now().toIso8601String();
  }
  if (result.licenseCategory != null) {
    final cats = result.licenseCategory!.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
    if (cats.isNotEmpty) updates['license_group'] = cats;
  }
  if (result.expiryDate != null) {
    final isoExp = _czDateToIso(result.expiryDate);
    if (isoExp != null) {
      updates['license_expiry'] = isoExp;
      updates['license_verified_until'] = isoExp;
    }
  }

  if (updates.isNotEmpty) {
    await MotoGoSupabase.client.from('profiles').update(updates).eq('id', user.id);
  }
}

/// Reset verification and delete documents for a given doc type.
/// Clears verified_at in profile and removes document records from DB.
Future<bool> resetDocVerification(String docType) async {
  try {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return false;

    // Clear verification timestamps in profile
    final updates = <String, dynamic>{};
    if (docType == 'id_card' || docType == 'passport') {
      updates['id_verified_at'] = null;
      updates['id_verified_until'] = null;
      updates['id_number'] = null;
      updates['passport_verified_at'] = null;
      updates['passport_verified_until'] = null;
    } else if (docType == 'drivers_license') {
      updates['license_verified_at'] = null;
      updates['license_verified_until'] = null;
      updates['license_number'] = null;
    }
    if (updates.isNotEmpty) {
      await MotoGoSupabase.client.from('profiles').update(updates).eq('id', user.id);
    }

    // Delete document records
    final types = (docType == 'id_card' || docType == 'passport')
        ? ['id_card', 'passport']
        : [docType];
    await MotoGoSupabase.client
        .from('documents')
        .delete()
        .eq('user_id', user.id)
        .inFilter('type', types);

    return true;
  } catch (_) {
    return false;
  }
}

/// Verify customer docs via RPC — mirrors verify_customer_docs.
Future<Map<String, dynamic>?> verifyCustomerDocs(OcrResult result, {DateTime? rentalEnd}) async {
  try {
    return await MotoGoSupabase.client.rpc('verify_customer_docs', params: {
      'p_ocr_name': result.fullName,
      'p_ocr_dob': result.dob,
      'p_ocr_id_number': result.idNumber,
      'p_ocr_license_number': result.licenseNumber,
      'p_ocr_license_category': result.licenseCategory,
      'p_ocr_license_expiry': result.expiryDate,
      'p_rental_end': rentalEnd?.toIso8601String(),
    }) as Map<String, dynamic>?;
  } catch (_) {
    return null;
  }
}
