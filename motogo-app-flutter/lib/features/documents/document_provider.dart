import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import 'document_models.dart';

/// User documents from Supabase.
final documentsProvider = FutureProvider<List<UserDocument>>((ref) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return [];
  final res = await MotoGoSupabase.client
      .from('documents')
      .select()
      .eq('user_id', user.id)
      .order('created_at', ascending: false);
  return (res as List).map((e) => UserDocument.fromJson(e)).toList();
});

/// User invoices from Supabase.
final invoicesProvider = FutureProvider<List<UserInvoice>>((ref) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return [];
  final res = await MotoGoSupabase.client
      .from('invoices')
      .select()
      .eq('customer_id', user.id)
      .order('created_at', ascending: false);
  return (res as List).map((e) => UserInvoice.fromJson(e)).toList();
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
Future<OcrResult?> scanDocument(XFile photo, ScanDocType docType) async {
  try {
    final bytes = await photo.readAsBytes();
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
    if (data == null || data['success'] != true) return null;

    return OcrResult.fromJson(data['data'] as Map<String, dynamic>);
  } catch (_) {
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
      'name': docType.label,
      'storage_path': path,
    });

    return path;
  } catch (_) {
    return null;
  }
}

/// Save OCR data to profile — mirrors apiSaveOcrToProfile.
Future<void> saveOcrToProfile(OcrResult result) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return;

  final updates = <String, dynamic>{};
  if (result.fullName.isNotEmpty) updates['full_name'] = result.fullName;
  if (result.dob != null) updates['date_of_birth'] = result.dob;
  if (result.idNumber != null) {
    updates['id_number'] = result.idNumber;
    updates['id_verified_at'] = DateTime.now().toIso8601String();
  }
  if (result.licenseNumber != null) {
    updates['license_number'] = result.licenseNumber;
    updates['license_verified_at'] = DateTime.now().toIso8601String();
  }
  if (result.licenseCategory != null) {
    updates['license_group'] = [result.licenseCategory];
  }
  if (result.expiryDate != null) {
    updates['license_expiry'] = result.expiryDate;
    updates['license_verified_until'] = result.expiryDate;
  }

  if (updates.isNotEmpty) {
    await MotoGoSupabase.client.from('profiles').update(updates).eq('id', user.id);
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
