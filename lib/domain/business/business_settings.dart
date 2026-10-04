import 'dart:convert';

/// Configurable business operational settings and billing preferences.
class BusinessSettings {
  final String id;
  final String businessId;
  final String? defaultTaxRateId;
  final String? defaultInvoiceTerms;
  final String? defaultInvoiceNotes;
  final bool enableHsn;
  final bool enableMrp;
  final bool enableDiscounts;
  final bool enableRoundOff;
  final bool taxInclusivePricing;
  final int lowStockThreshold;
  final String thermalPrinterType; // 'A4', '80mm', '58mm'
  final bool printBusinessLogo;
  final bool printBankDetails;
  final bool printUpiQr;
  final bool autoBackupEnabled;
  final int autoBackupIntervalDays;
  final String? backupDirectoryPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncVersion;
  final String syncStatus;

  const BusinessSettings({
    required this.id,
    required this.businessId,
    this.defaultTaxRateId,
    this.defaultInvoiceTerms,
    this.defaultInvoiceNotes,
    this.enableHsn = true,
    this.enableMrp = true,
    this.enableDiscounts = true,
    this.enableRoundOff = true,
    this.taxInclusivePricing = false,
    this.lowStockThreshold = 5,
    this.thermalPrinterType = 'A4',
    this.printBusinessLogo = true,
    this.printBankDetails = true,
    this.printUpiQr = true,
    this.autoBackupEnabled = true,
    this.autoBackupIntervalDays = 1,
    this.backupDirectoryPath,
    required this.createdAt,
    required this.updatedAt,
    this.syncVersion = 1,
    this.syncStatus = 'synced',
  });

  BusinessSettings copyWith({
    String? id,
    String? businessId,
    String? defaultTaxRateId,
    String? defaultInvoiceTerms,
    String? defaultInvoiceNotes,
    bool? enableHsn,
    bool? enableMrp,
    bool? enableDiscounts,
    bool? enableRoundOff,
    bool? taxInclusivePricing,
    int? lowStockThreshold,
    String? thermalPrinterType,
    bool? printBusinessLogo,
    bool? printBankDetails,
    bool? printUpiQr,
    bool? autoBackupEnabled,
    int? autoBackupIntervalDays,
    String? backupDirectoryPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncVersion,
    String? syncStatus,
  }) {
    return BusinessSettings(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      defaultTaxRateId: defaultTaxRateId ?? this.defaultTaxRateId,
      defaultInvoiceTerms: defaultInvoiceTerms ?? this.defaultInvoiceTerms,
      defaultInvoiceNotes: defaultInvoiceNotes ?? this.defaultInvoiceNotes,
      enableHsn: enableHsn ?? this.enableHsn,
      enableMrp: enableMrp ?? this.enableMrp,
      enableDiscounts: enableDiscounts ?? this.enableDiscounts,
      enableRoundOff: enableRoundOff ?? this.enableRoundOff,
      taxInclusivePricing: taxInclusivePricing ?? this.taxInclusivePricing,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      thermalPrinterType: thermalPrinterType ?? this.thermalPrinterType,
      printBusinessLogo: printBusinessLogo ?? this.printBusinessLogo,
      printBankDetails: printBankDetails ?? this.printBankDetails,
      printUpiQr: printUpiQr ?? this.printUpiQr,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      autoBackupIntervalDays: autoBackupIntervalDays ?? this.autoBackupIntervalDays,
      backupDirectoryPath: backupDirectoryPath ?? this.backupDirectoryPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncVersion: syncVersion ?? this.syncVersion,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    String? serializedTerms;
    if (defaultInvoiceNotes != null && defaultInvoiceNotes!.isNotEmpty) {
      serializedTerms = jsonEncode({
        'terms': defaultInvoiceTerms ?? '',
        'notes': defaultInvoiceNotes ?? '',
      });
    } else {
      serializedTerms = defaultInvoiceTerms;
    }

    return {
      'id': id,
      'business_id': businessId,
      'default_tax_rate_id': defaultTaxRateId,
      'default_invoice_terms': serializedTerms,
      'enable_hsn': enableHsn ? 1 : 0,
      'enable_mrp': enableMrp ? 1 : 0,
      'enable_discounts': enableDiscounts ? 1 : 0,
      'enable_round_off': enableRoundOff ? 1 : 0,
      'tax_inclusive_pricing': taxInclusivePricing ? 1 : 0,
      'low_stock_threshold': lowStockThreshold,
      'thermal_printer_type': thermalPrinterType,
      'print_business_logo': printBusinessLogo ? 1 : 0,
      'print_bank_details': printBankDetails ? 1 : 0,
      'print_upi_qr': printUpiQr ? 1 : 0,
      'auto_backup_enabled': autoBackupEnabled ? 1 : 0,
      'auto_backup_interval_days': autoBackupIntervalDays,
      'backup_directory_path': backupDirectoryPath,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'sync_version': syncVersion,
      'sync_status': syncStatus,
    };
  }

  factory BusinessSettings.fromMap(Map<String, dynamic> map) {
    String? terms = map['default_invoice_terms'] as String?;
    String? notes;

    if (terms != null && terms.trim().startsWith('{') && terms.trim().endsWith('}')) {
      try {
        final decoded = jsonDecode(terms);
        if (decoded is Map<String, dynamic>) {
          terms = decoded['terms'] as String?;
          notes = decoded['notes'] as String?;
        }
      } catch (_) {
        // Fallback to plain string if JSON decoding fails
      }
    }

    return BusinessSettings(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      defaultTaxRateId: map['default_tax_rate_id'] as String?,
      defaultInvoiceTerms: terms,
      defaultInvoiceNotes: notes,
      enableHsn: (map['enable_hsn'] as int? ?? 1) == 1,
      enableMrp: (map['enable_mrp'] as int? ?? 1) == 1,
      enableDiscounts: (map['enable_discounts'] as int? ?? 1) == 1,
      enableRoundOff: (map['enable_round_off'] as int? ?? 1) == 1,
      taxInclusivePricing: (map['tax_inclusive_pricing'] as int? ?? 0) == 1,
      lowStockThreshold: map['low_stock_threshold'] as int? ?? 5,
      thermalPrinterType: map['thermal_printer_type'] as String? ?? 'A4',
      printBusinessLogo: (map['print_business_logo'] as int? ?? 1) == 1,
      printBankDetails: (map['print_bank_details'] as int? ?? 1) == 1,
      printUpiQr: (map['print_upi_qr'] as int? ?? 1) == 1,
      autoBackupEnabled: (map['auto_backup_enabled'] as int? ?? 1) == 1,
      autoBackupIntervalDays: map['auto_backup_interval_days'] as int? ?? 1,
      backupDirectoryPath: map['backup_directory_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncVersion: map['sync_version'] as int? ?? 1,
      syncStatus: map['sync_status'] as String? ?? 'synced',
    );
  }
}
