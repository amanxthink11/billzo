import 'package:flutter/foundation.dart';
import 'package:billzo/core/money/money.dart';

/// Line item in an invoice.
@immutable
class InvoiceItem {
  final String id;
  final String invoiceId;
  final String productId;
  final String taxRateId;
  final String productName;
  final String? hsnSac;
  final int quantityScaled; // e.g. 1.250 units = 1250
  final String unitCode;
  final int ratePaise;
  final int mrpPaise;
  final int discountPaise;
  final int taxableAmountPaise;
  final int cgstRateBasisPoints;
  final int cgstAmountPaise;
  final int sgstRateBasisPoints;
  final int sgstAmountPaise;
  final int igstRateBasisPoints;
  final int igstAmountPaise;
  final int cessRateBasisPoints;
  final int cessAmountPaise;
  final int totalAmountPaise;
  final bool isTaxInclusive;
  final bool trackInventory; // True for physical goods, false for services
  final DateTime createdAt;
  final DateTime updatedAt;

  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.taxRateId,
    required this.productName,
    this.hsnSac,
    required this.quantityScaled,
    required this.unitCode,
    required this.ratePaise,
    this.mrpPaise = 0,
    this.discountPaise = 0,
    required this.taxableAmountPaise,
    this.cgstRateBasisPoints = 0,
    this.cgstAmountPaise = 0,
    this.sgstRateBasisPoints = 0,
    this.sgstAmountPaise = 0,
    this.igstRateBasisPoints = 0,
    this.igstAmountPaise = 0,
    this.cessRateBasisPoints = 0,
    this.cessAmountPaise = 0,
    required this.totalAmountPaise,
    this.isTaxInclusive = false,
    this.trackInventory = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Quantity as decimal (e.g. 1.250).
  double get quantity => quantityScaled / 1000.0;

  Money get rate => Money.fromPaise(ratePaise);
  Money get mrp => Money.fromPaise(mrpPaise);
  Money get discount => Money.fromPaise(discountPaise);
  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgstAmount => Money.fromPaise(cgstAmountPaise);
  Money get sgstAmount => Money.fromPaise(sgstAmountPaise);
  Money get igstAmount => Money.fromPaise(igstAmountPaise);
  Money get cessAmount => Money.fromPaise(cessAmountPaise);
  Money get totalTaxAmount =>
      Money.fromPaise(cgstAmountPaise + sgstAmountPaise + igstAmountPaise + cessAmountPaise);
  int get taxAmountPaise => cgstAmountPaise + sgstAmountPaise + igstAmountPaise + cessAmountPaise;
  Money get totalAmount => Money.fromPaise(totalAmountPaise);

  InvoiceItem copyWith({
    String? id,
    String? invoiceId,
    String? productId,
    String? taxRateId,
    String? productName,
    String? hsnSac,
    int? quantityScaled,
    String? unitCode,
    int? ratePaise,
    int? mrpPaise,
    int? discountPaise,
    int? taxableAmountPaise,
    int? cgstRateBasisPoints,
    int? cgstAmountPaise,
    int? sgstRateBasisPoints,
    int? sgstAmountPaise,
    int? igstRateBasisPoints,
    int? igstAmountPaise,
    int? cessRateBasisPoints,
    int? cessAmountPaise,
    int? totalAmountPaise,
    bool? isTaxInclusive,
    bool? trackInventory,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      taxRateId: taxRateId ?? this.taxRateId,
      productName: productName ?? this.productName,
      hsnSac: hsnSac ?? this.hsnSac,
      quantityScaled: quantityScaled ?? this.quantityScaled,
      unitCode: unitCode ?? this.unitCode,
      ratePaise: ratePaise ?? this.ratePaise,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      discountPaise: discountPaise ?? this.discountPaise,
      taxableAmountPaise: taxableAmountPaise ?? this.taxableAmountPaise,
      cgstRateBasisPoints: cgstRateBasisPoints ?? this.cgstRateBasisPoints,
      cgstAmountPaise: cgstAmountPaise ?? this.cgstAmountPaise,
      sgstRateBasisPoints: sgstRateBasisPoints ?? this.sgstRateBasisPoints,
      sgstAmountPaise: sgstAmountPaise ?? this.sgstAmountPaise,
      igstRateBasisPoints: igstRateBasisPoints ?? this.igstRateBasisPoints,
      igstAmountPaise: igstAmountPaise ?? this.igstAmountPaise,
      cessRateBasisPoints: cessRateBasisPoints ?? this.cessRateBasisPoints,
      cessAmountPaise: cessAmountPaise ?? this.cessAmountPaise,
      totalAmountPaise: totalAmountPaise ?? this.totalAmountPaise,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      trackInventory: trackInventory ?? this.trackInventory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'tax_rate_id': taxRateId,
      'product_name': productName,
      'hsn_sac': hsnSac,
      'quantity': quantityScaled,
      'unit_code': unitCode,
      'rate_paise': ratePaise,
      'mrp_paise': mrpPaise,
      'discount_paise': discountPaise,
      'taxable_amount_paise': taxableAmountPaise,
      'cgst_rate_basis_points': cgstRateBasisPoints,
      'cgst_amount_paise': cgstAmountPaise,
      'sgst_rate_basis_points': sgstRateBasisPoints,
      'sgst_amount_paise': sgstAmountPaise,
      'igst_rate_basis_points': igstRateBasisPoints,
      'igst_amount_paise': igstAmountPaise,
      'cess_rate_basis_points': cessRateBasisPoints,
      'cess_amount_paise': cessAmountPaise,
      'total_amount_paise': totalAmountPaise,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory InvoiceItem.fromMap(Map<String, dynamic> map, {bool trackInventory = true, bool isTaxInclusive = false}) {
    return InvoiceItem(
      id: map['id'] as String,
      invoiceId: map['invoice_id'] as String,
      productId: map['product_id'] as String,
      taxRateId: map['tax_rate_id'] as String,
      productName: map['product_name'] as String,
      hsnSac: map['hsn_sac'] as String?,
      quantityScaled: map['quantity'] as int,
      unitCode: map['unit_code'] as String,
      ratePaise: map['rate_paise'] as int,
      mrpPaise: map['mrp_paise'] as int? ?? 0,
      discountPaise: map['discount_paise'] as int? ?? 0,
      taxableAmountPaise: map['taxable_amount_paise'] as int,
      cgstRateBasisPoints: map['cgst_rate_basis_points'] as int? ?? 0,
      cgstAmountPaise: map['cgst_amount_paise'] as int? ?? 0,
      sgstRateBasisPoints: map['sgst_rate_basis_points'] as int? ?? 0,
      sgstAmountPaise: map['sgst_amount_paise'] as int? ?? 0,
      igstRateBasisPoints: map['igst_rate_basis_points'] as int? ?? 0,
      igstAmountPaise: map['igst_amount_paise'] as int? ?? 0,
      cessRateBasisPoints: map['cess_rate_basis_points'] as int? ?? 0,
      cessAmountPaise: map['cess_amount_paise'] as int? ?? 0,
      totalAmountPaise: map['total_amount_paise'] as int,
      isTaxInclusive: isTaxInclusive,
      trackInventory: trackInventory,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
