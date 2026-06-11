/// Document from Supabase documents table.
/// DB columns: id, booking_id, user_id, type, file_path, file_name, file_size, created_at
class UserDocument {
  final String id;
  final String type;
  final String? fileName;
  final String? filePath;
  final int? fileSize;
  final String? bookingId;
  final DateTime createdAt;

  const UserDocument({
    required this.id,
    required this.type,
    this.fileName,
    this.filePath,
    this.fileSize,
    this.bookingId,
    required this.createdAt,
  });

  factory UserDocument.fromJson(Map<String, dynamic> json) => UserDocument(
    id: json['id'] as String,
    type: json['type'] as String? ?? '',
    fileName: json['file_name'] as String?,
    filePath: json['file_path'] as String?,
    fileSize: (json['file_size'] as num?)?.toInt(),
    bookingId: json['booking_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  /// For backward compat — alias used in contracts_screen / invoices_screen.
  String? get storagePath => filePath;
  String? get name => fileName;

  // TODO: Move typeLabel to UI layer where BuildContext is available,
  // then use i18n keys: docContract, docProformaInvoice, docPaymentReceipt,
  // docFinalInvoice, docHandoverProtocol.
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
  final String? status; // paid, issued, cancelled, draft
  final double? total;
  final double? subtotal;
  final double? taxAmount;
  final String? pdfPath;
  final String? bookingId;
  final String? orderId;
  final String? variableSymbol;
  final String? notes;
  final DateTime? issuedAt;
  final DateTime? dueDate;
  final DateTime createdAt;
  final List<InvoiceItem> items;

  const UserInvoice({
    required this.id,
    this.number,
    required this.type,
    this.status,
    this.total,
    this.subtotal,
    this.taxAmount,
    this.pdfPath,
    this.bookingId,
    this.orderId,
    this.variableSymbol,
    this.notes,
    this.issuedAt,
    this.dueDate,
    required this.createdAt,
    this.items = const [],
  });

  factory UserInvoice.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final itemsList = <InvoiceItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          itemsList.add(InvoiceItem.fromJson(item));
        }
      }
    }
    return UserInvoice(
      id: json['id'] as String,
      number: json['number'] as String?,
      type: json['type'] as String? ?? '',
      status: json['status'] as String?,
      total: (json['total'] as num?)?.toDouble(),
      subtotal: (json['subtotal'] as num?)?.toDouble(),
      taxAmount: (json['tax_amount'] as num?)?.toDouble(),
      pdfPath: json['pdf_path'] as String?,
      bookingId: json['booking_id'] as String?,
      orderId: json['order_id'] as String?,
      variableSymbol: json['variable_symbol'] as String?,
      notes: json['notes'] as String?,
      issuedAt: json['issue_date'] != null ? DateTime.parse(json['issue_date'] as String) : null,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      items: itemsList,
    );
  }

  String get typeLabel => switch (type) {
    'proforma' || 'advance' => 'Zálohová faktura',
    'final' => 'Konečná faktura',
    'shop_final' => 'Shop faktura',
    'shop_proforma' => 'Shop zálohová faktura',
    'payment_receipt' => 'Doklad k platbě',
    'credit_note' => 'Dobropis',
    _ => type,
  };

  bool get isCreditNote => type == 'credit_note';
  bool get isPaid => status == 'paid';
}

/// Single line item in an invoice.
class InvoiceItem {
  final String description;
  final int qty;
  final double unitPrice;

  const InvoiceItem({
    required this.description,
    required this.qty,
    required this.unitPrice,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> json) => InvoiceItem(
    description: json['description'] as String? ?? '',
    qty: (json['qty'] as num?)?.toInt() ?? 1,
    unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
  );

  double get lineTotal => qty * unitPrice;
  bool get isSectionHeader => description.startsWith('──') && unitPrice == 0;
  bool get isNegative => unitPrice < 0;
}

/// OCR scan result from Mindee v2 via scan-document edge function.
/// Fields mirror Capacitor doc-parser-id.js / doc-parser-dl.js output.
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
  // Address components from ID back — mirrors doc-parser-id.js parseIdBack
  final String? street;
  final String? city;
  final String? zip;

  const OcrResult({
    this.firstName, this.lastName, this.dob,
    this.idNumber, this.licenseNumber, this.licenseCategory,
    this.issuedDate, this.expiryDate, this.address,
    this.street, this.city, this.zip,
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
    street: json['street'] as String?,
    city: json['city'] as String?,
    zip: json['zip'] as String?,
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
