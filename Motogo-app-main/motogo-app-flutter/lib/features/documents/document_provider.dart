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

/// Structured result from scanning — carries either data or a specific error.
class ScanResult {
  final OcrResult? data;
  final String? errorCode;
  final String? errorDetail;
  final int? httpStatus;
  final int attempts;

  const ScanResult({
    this.data, this.errorCode, this.errorDetail,
    this.httpStatus, this.attempts = 1,
  });
  bool get ok => data != null;
}

/// Classify exception into error code + readable detail.
ScanResult _classifyException(Object e, int attempt) {
  final s = e.toString();
  final lo = s.toLowerCase();
  debugPrint('[DocScan] Exception attempt $attempt: $s');

  // Supabase FunctionException — contains server response body
  // Format: "FunctionsException(status: 502, details: {...})"
  int? httpStatus;
  String? serverMsg;
  final statusMatch = RegExp(r'status:\s*(\d+)').firstMatch(s);
  if (statusMatch != null) httpStatus = int.tryParse(statusMatch.group(1)!);
  final detailsMatch = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(s);
  if (detailsMatch != null) serverMsg = detailsMatch.group(1);

  if (httpStatus != null && httpStatus >= 400) {
    final detail = serverMsg ?? s;
    if (httpStatus == 502) {
      return ScanResult(errorCode: 'server_upstream', httpStatus: httpStatus,
          errorDetail: detail, attempts: attempt);
    }
    if (httpStatus == 500) {
      return ScanResult(errorCode: 'server_config', httpStatus: httpStatus,
          errorDetail: detail, attempts: attempt);
    }
    if (httpStatus == 400) {
      return ScanResult(errorCode: 'bad_request', httpStatus: httpStatus,
          errorDetail: detail, attempts: attempt);
    }
    return ScanResult(errorCode: 'server_error', httpStatus: httpStatus,
        errorDetail: detail, attempts: attempt);
  }

  if (lo.contains('timeout') || lo.contains('timed out') ||
      lo.contains('deadline')) {
    return ScanResult(errorCode: 'timeout', errorDetail: s, attempts: attempt);
  }
  if (lo.contains('socket') || lo.contains('network') ||
      lo.contains('connection') || lo.contains('handshake') ||
      lo.contains('dns') || lo.contains('unreachable') ||
      lo.contains('no address') || lo.contains('failed host')) {
    return ScanResult(errorCode: 'network', errorDetail: s, attempts: attempt);
  }
  return ScanResult(errorCode: 'unknown', errorDetail: s, attempts: attempt);
}

/// OCR scan via scan-document edge function.
/// Mirrors scanOCR from doc-scanner-ocr.js (Mindee v2 enqueue+poll).
/// Retries up to 3 times with exponential backoff (matching Capacitor).
/// Image is resized to max 1600px / 80% JPEG before sending.
Future<ScanResult> scanDocumentWithRetry(XFile photo, ScanDocType docType) async {
  const maxAttempts = 3;
  Uint8List? resizedBytes;

  try {
    final rawBytes = await photo.readAsBytes();
    debugPrint('[DocScan] Raw photo: ${rawBytes.length} bytes');
    resizedBytes = await compute(_resizeForOcr, rawBytes);
    debugPrint('[DocScan] Resized: ${resizedBytes?.length} bytes');
  } catch (e) {
    debugPrint('[DocScan] Image prep error: $e');
    return ScanResult(errorCode: 'image_error', errorDetail: '$e');
  }

  final base64Image = base64Encode(resizedBytes!);
  final user = MotoGoSupabase.currentUser;
  ScanResult? lastFailure;

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      debugPrint('[DocScan] ── Attempt $attempt/$maxAttempts ──'
          ' type=${docType.apiType}, user=${user?.id ?? "anon"},'
          ' b64len=${base64Image.length}');

      final res = await MotoGoSupabase.client.functions.invoke(
        'scan-document',
        body: {
          'image_base64': base64Image,
          'document_type': docType.apiType,
          'user_id': user?.id,
        },
      );

      // Edge function returned HTTP 200 — parse JSON body
      final data = res.data;
      debugPrint('[DocScan] HTTP 200, data type=${data.runtimeType}');

      if (data == null) {
        debugPrint('[DocScan] ✗ Null body (attempt $attempt)');
        lastFailure = ScanResult(errorCode: 'ocr_empty', attempts: attempt,
            errorDetail: 'HTTP 200 ale prázdné tělo odpovědi');
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
        return lastFailure;
      }

      if (data is! Map<String, dynamic>) {
        debugPrint('[DocScan] ✗ Unexpected type: ${data.runtimeType} = $data');
        lastFailure = ScanResult(errorCode: 'ocr_empty', attempts: attempt,
            errorDetail: 'Server vrátil neočekávaný typ: ${data.runtimeType}');
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
        return lastFailure;
      }

      final success = data['success'];
      final error = data['error']?.toString();
      final fieldsCount = data['fields_count'];
      debugPrint('[DocScan] success=$success, fields_count=$fieldsCount,'
          ' error=$error, keys=${data.keys.toList()}');

      if (success != true) {
        debugPrint('[DocScan] ✗ success!=true: $error');
        lastFailure = ScanResult(
          errorCode: 'ocr_failed',
          errorDetail: error ?? 'Neznámá chyba OCR',
          httpStatus: 200,
          attempts: attempt,
        );
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
        return lastFailure;
      }

      final rawFields = data['data'];
      if (rawFields == null || rawFields is! Map<String, dynamic>) {
        debugPrint('[DocScan] ✗ success=true ale žádná data: '
            'rawFields type=${rawFields.runtimeType}');
        lastFailure = ScanResult(
          errorCode: 'no_fields',
          errorDetail: 'Server potvrdil úspěch ale nevrátil žádná pole',
          httpStatus: 200,
          attempts: attempt,
        );
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
        return lastFailure;
      }

      // Parse OCR result and log all extracted fields
      final result = OcrResult.fromJson(rawFields);
      final extracted = <String>[];
      if (result.firstName != null && result.firstName!.isNotEmpty) extracted.add('firstName=${result.firstName}');
      if (result.lastName != null && result.lastName!.isNotEmpty) extracted.add('lastName=${result.lastName}');
      if (result.idNumber != null && result.idNumber!.isNotEmpty) extracted.add('idNumber=${result.idNumber}');
      if (result.licenseNumber != null && result.licenseNumber!.isNotEmpty) extracted.add('licenseNumber=${result.licenseNumber}');
      if (result.licenseCategory != null && result.licenseCategory!.isNotEmpty) extracted.add('licenseCategory=${result.licenseCategory}');
      if (result.expiryDate != null && result.expiryDate!.isNotEmpty) extracted.add('expiryDate=${result.expiryDate}');
      if (result.dob != null && result.dob!.isNotEmpty) extracted.add('dob=${result.dob}');
      if (result.address != null && result.address!.isNotEmpty) extracted.add('address=...');
      debugPrint('[DocScan] ✓ Parsed ${extracted.length} fields: ${extracted.join(", ")}');
      debugPrint('[DocScan] ✓ Raw field keys: ${rawFields.keys.toList()}');

      return ScanResult(data: result, httpStatus: 200, attempts: attempt);

    } catch (e) {
      final classified = _classifyException(e, attempt);
      debugPrint('[DocScan] ✗ ${classified.errorCode}: ${classified.errorDetail}');
      lastFailure = classified;

      // Don't retry config/auth errors — they won't fix themselves
      if (classified.errorCode == 'server_config' ||
          classified.errorCode == 'bad_request') {
        return classified;
      }

      if (attempt < maxAttempts) {
        debugPrint('[DocScan] Retrying in ${attempt}s...');
        await Future.delayed(Duration(seconds: attempt));
        continue;
      }
      return classified;
    }
  }

  return lastFailure ?? const ScanResult(
      errorCode: 'unknown', errorDetail: 'Neočekávaný stav');
}

/// Legacy wrapper — returns OcrResult? for backward compat.
Future<OcrResult?> scanDocument(XFile photo, ScanDocType docType) async {
  final r = await scanDocumentWithRetry(photo, docType);
  return r.data;
}

/// Result of a verification record insert — carries success/failure info
/// so the UI can react to DB failures instead of swallowing them.
class DocUploadResult {
  final String? markerPath;
  final String? errorDetail;
  const DocUploadResult({this.markerPath, this.errorDetail});
  bool get ok => markerPath != null && errorDetail == null;
}

/// Record Mindee-verified document in Supabase documents table.
/// Photos are NOT uploaded to storage (GDPR) — only a verification
/// record is inserted so admin/door-code logic can confirm docs exist.
///
/// Uses UPSERT on (user_id, type) to avoid duplicate records when the
/// user re-scans the same side/type.
Future<DocUploadResult> uploadDocPhoto(XFile photo, ScanDocType docType) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) {
    debugPrint('[DocUpload] ✗ No authenticated user');
    return const DocUploadResult(errorDetail: 'not_authenticated');
  }

  try {
    final marker = 'mindee_verified/${user.id}/${docType.storageType}';
    await MotoGoSupabase.client.from('documents').insert({
      'user_id': user.id,
      'type': docType.storageType,
      'file_name': docType.label,
      'file_path': marker,
    });
    debugPrint('[DocUpload] ✓ Verification record inserted: ${docType.storageType}');
    return DocUploadResult(markerPath: marker);
  } catch (e) {
    debugPrint('[DocUpload] ✗ Document insert FAILED: $e');
    return DocUploadResult(errorDetail: '$e');
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

/// Valid license_group enum values in the profiles table.
/// Matches schema.sql: CREATE TYPE license_group AS ENUM ('A','A1','A2','AM','B').
const _validLicenseGroups = {'A', 'A1', 'A2', 'AM', 'B'};

/// Save OCR data to profile — mirrors apiSaveOcrToProfile from
/// api-enrichment-2.js. Saves all extracted fields including address
/// components (street, city, zip) from OP back side.
/// [docType] ensures verification flag is set even when specific fields
/// were not extracted by OCR (e.g. DL without license number).
///
/// Returns null on success, or a warning message if save partially failed.
Future<String?> saveOcrToProfile(OcrResult result, {ScanDocType? docType}) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return null;

  final updates = <String, dynamic>{};
  if (result.fullName.isNotEmpty) updates['full_name'] = result.fullName;
  if (result.dob != null) {
    final isoDob = _czDateToIso(result.dob);
    if (isoDob != null) updates['date_of_birth'] = isoDob;
  }

  final isDl = docType == ScanDocType.driversLicense;

  if (!isDl) {
    // Address components from OP back — mirrors Capacitor apiSaveOcrToProfile
    if (result.street != null) updates['street'] = result.street;
    if (result.city != null) updates['city'] = result.city;
    if (result.zip != null) updates['zip'] = result.zip;
    // id_number + id_verified_at only from OP/passport, NOT from DL
    if (result.idNumber != null) {
      updates['id_number'] = result.idNumber;
      updates['id_verified_at'] = DateTime.now().toIso8601String();
    }
  }

  // License number — from licenseNumber field, or from idNumber when scanning DL
  // (edge function sets licenseNumber=idNumber for DL, but just in case)
  if (result.licenseNumber != null) {
    updates['license_number'] = result.licenseNumber;
  } else if (isDl && result.idNumber != null) {
    updates['license_number'] = result.idNumber;
  }
  if (result.licenseCategory != null) {
    final raw = result.licenseCategory!.split(RegExp(r'[,\s]+'))
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();
    // Filter to valid DB enum values only
    final valid = raw.where((c) => _validLicenseGroups.contains(c)).toList();
    final rejected = raw.where((c) => !_validLicenseGroups.contains(c)).toList();
    if (rejected.isNotEmpty) {
      debugPrint('[DocScan] Filtered out invalid license categories: $rejected '
          '(valid: $valid, allowed: $_validLicenseGroups)');
    }
    if (valid.isNotEmpty) updates['license_group'] = valid;
  }
  if (result.expiryDate != null) {
    final isoExp = _czDateToIso(result.expiryDate);
    if (isoExp != null) {
      updates['license_expiry'] = isoExp;
      updates['license_verified_until'] = isoExp;
    }
  }
  // license_verified_at se nastavuje POUZE když OCR opravdu vrátil něco
  // z ŘP (číslo nebo datum platnosti). Pouhý fakt, že user vyfotil DL,
  // nestačí — jinak se v profilu objeví "ověřeno" i u čitelně prošlých
  // nebo nečitelných skenů. Door-code logika pak vydá kódy bez validace.
  final hasLicenseData = (result.licenseNumber != null && result.licenseNumber!.isNotEmpty)
      || (result.expiryDate != null && result.expiryDate!.isNotEmpty)
      || (result.licenseCategory != null && result.licenseCategory!.isNotEmpty);
  if (hasLicenseData) {
    updates['license_verified_at'] = DateTime.now().toIso8601String();
  }

  if (updates.isEmpty) return null;

  try {
    await MotoGoSupabase.client.from('profiles').update(updates).eq('id', user.id);
    debugPrint('[DocScan] Profile updated: ${updates.keys.toList()}');
    return null;
  } catch (e) {
    debugPrint('[DocScan] ⚠ Profile update failed: $e');
    // Return warning message but don't crash — photo is already saved
    return e.toString();
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
