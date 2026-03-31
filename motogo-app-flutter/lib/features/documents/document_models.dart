/// Document from Supabase documents table.
class UserDocument {
  final String id;
  final String type; // contract, vop, invoice_advance, payment_receipt, invoice_final, protocol, id_card, drivers_license, passport
  final String? name;
  final String? url;
  final String? storagePath;
  final DateTime createdAt;

  const UserDocument({
    required this.id,
    required this.type,
    this.name,
    this.url,
    this.storagePath,
    required this.createdAt,
  });

  factory UserDocument.fromJson(Map<String, dynamic> json) => UserDocument(
    id: json['id'] as String,
    type: json['type'] as String? ?? '',
    name: json['name'] as String?,
    url: json['url'] as String?,
    storagePath: json['storage_path'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  String get typeLabel => switch (type) {
    'contract' => '📄 Smlouva',
    'vop' => '📋 VOP',
    'invoice_advance' => '🧾 Zálohová faktura',
    'payment_receipt' => '💰 Doklad k platbě',
    'invoice_final' => '🧾 Konečná faktura',
    'protocol' => '📝 Předávací protokol',
    'id_card' => '🪪 Občanský průkaz',
    'drivers_license' => '🏍️ Řidičský průkaz',
    'passport' => '📕 Pas',
    _ => '📄 $type',
  };
}

/// Invoice from Supabase invoices table.
class UserInvoice {
  final String id;
  final String? number;
  final String type; // proforma, advance, final, shop_final, payment_receipt, credit_note
  final double? total;
  final String? pdfPath;
  final String? bookingId;
  final String? orderId;
  final DateTime? issuedAt;
  final DateTime createdAt;

  const UserInvoice({
    required this.id,
    this.number,
    required this.type,
    this.total,
    this.pdfPath,
    this.bookingId,
    this.orderId,
    this.issuedAt,
    required this.createdAt,
  });

  factory UserInvoice.fromJson(Map<String, dynamic> json) => UserInvoice(
    id: json['id'] as String,
    number: json['number'] as String?,
    type: json['type'] as String? ?? '',
    total: (json['total'] as num?)?.toDouble(),
    pdfPath: json['pdf_path'] as String?,
    bookingId: json['booking_id'] as String?,
    orderId: json['order_id'] as String?,
    issuedAt: json['issued_at'] != null ? DateTime.parse(json['issued_at'] as String) : null,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  String get typeLabel => switch (type) {
    'proforma' || 'advance' => '📋 Zálohová faktura',
    'final' => '🧾 Konečná faktura',
    'shop_final' => '🛍️ Shop faktura',
    'payment_receipt' => '💰 Doklad k platbě',
    'credit_note' => '📕 Dobropis',
    _ => '📄 $type',
  };

  bool get isCreditNote => type == 'credit_note';
}

/// OCR scan result from Mindee v2 via scan-document edge function.
class OcrResult {
  final String? firstName;
  final String? lastName;
  final String? dob;
  final String? idNumber;
  final String? licenseNumber;
  final String? licenseCategory;
  final String? issuedDate;
  final String? expiryDate;
  final String? address;

  const OcrResult({
    this.firstName, this.lastName, this.dob,
    this.idNumber, this.licenseNumber, this.licenseCategory,
    this.issuedDate, this.expiryDate, this.address,
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) => OcrResult(
    firstName: json['firstName'] as String?,
    lastName: json['lastName'] as String?,
    dob: json['dob'] as String?,
    idNumber: json['idNumber'] as String?,
    licenseNumber: json['licenseNumber'] as String?,
    licenseCategory: json['licenseCategory'] as String?,
    issuedDate: json['issuedDate'] as String?,
    expiryDate: json['expiryDate'] as String?,
    address: json['address'] as String?,
  );

  String get fullName => [firstName, lastName].where((s) => s != null && s.isNotEmpty).join(' ');
}

/// Document scan type for scanner flow.
enum ScanDocType { idCard, driversLicense, passport }

extension ScanDocTypeExt on ScanDocType {
  String get apiType => switch (this) {
    ScanDocType.idCard => 'id',
    ScanDocType.driversLicense => 'dl',
    ScanDocType.passport => 'passport',
  };

  String get storageType => switch (this) {
    ScanDocType.idCard => 'id_card',
    ScanDocType.driversLicense => 'drivers_license',
    ScanDocType.passport => 'passport',
  };

  String get label => switch (this) {
    ScanDocType.idCard => '🪪 Občanský průkaz',
    ScanDocType.driversLicense => '🏍️ Řidičský průkaz',
    ScanDocType.passport => '📕 Cestovní pas',
  };
}
