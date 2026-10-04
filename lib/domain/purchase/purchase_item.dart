import 'package:flutter/foundation.dart';
import 'package:billzo/core/money/money.dart';

/// Individual line item in a Purchase bill.
@immutable
class PurchaseItem {
  final String id;
  final String purchaseId;
  final String productId;
  final String productName;
  final String? description;
  final String? hsnSac;

  /// Quantity stored as scaled integer (e.g. 1.250 units = 1250)
  final int quantityScaled;
  final String unitCode;

  /// Unit purchase cost in integer paise
  final int purchaseRatePaise;
  final int discountPaise;
  final int taxableAmountPaise;

  final String taxRateId;
  final int rateBasisPoints;
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
  final bool isItcEligible;
  final bool trackInventory; // True for physical goods, false for services

  final DateTime createdAt;
  final DateTime updatedAt;

  const PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.productName,
    this.description,
    this.hsnSac,
    required this.quantityScaled,
    required this.unitCode,
    required this.purchaseRatePaise,
    this.discountPaise = 0,
    required this.taxableAmountPaise,
    required this.taxRateId,
    this.rateBasisPoints = 0,
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
    this.isItcEligible = true,
    this.trackInventory = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Quantity as decimal (e.g. 1.250).
  double get quantity => quantityScaled / 1000.0;

  String get unit => unitCode;
  int get ratePaise => purchaseRatePaise;
  int get taxRateBasisPoints => rateBasisPoints;
  int get cgstPaise => cgstAmountPaise;
  int get sgstPaise => sgstAmountPaise;
  int get igstPaise => igstAmountPaise;
  int get cessPaise => cessAmountPaise;
  int get lineTotalPaise => totalAmountPaise;
  bool get itcEligibility => isItcEligible;

  Money get purchaseRate => Money.fromPaise(purchaseRatePaise);
  Money get discount => Money.fromPaise(discountPaise);
  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgstAmount => Money.fromPaise(cgstAmountPaise);
  Money get sgstAmount => Money.fromPaise(sgstAmountPaise);
  Money get igstAmount => Money.fromPaise(igstAmountPaise);
  Money get cessAmount => Money.fromPaise(cessAmountPaise);

  int get totalTaxPaise =>
      cgstAmountPaise + sgstAmountPaise + igstAmountPaise + cessAmountPaise;
  Money get totalTax => Money.fromPaise(totalTaxPaise);

  Money get totalAmount => Money.fromPaise(totalAmountPaise);

  /// Eligible ITC amounts for this line item
  int get inputCgstPaise => isItcEligible ? cgstAmountPaise : 0;
  int get inputSgstPaise => isItcEligible ? sgstAmountPaise : 0;
  int get inputIgstPaise => isItcEligible ? igstAmountPaise : 0;
  int get inputCessPaise => isItcEligible ? cessAmountPaise : 0;
  int get totalItcPaise =>
      inputCgstPaise + inputSgstPaise + inputIgstPaise + inputCessPaise;
  Money get totalItc => Money.fromPaise(totalItcPaise);

  PurchaseItem copyWith({
    String? id,
    String? purchaseId,
    String? productId,
    String? productName,
    String? description,
    String? hsnSac,
    int? quantityScaled,
    String? unitCode,
    int? purchaseRatePaise,
    int? discountPaise,
    int? taxableAmountPaise,
    String? taxRateId,
    int? rateBasisPoints,
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
    bool? isItcEligible,
    bool? trackInventory,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchaseItem(
      id: id ?? this.id,
      purchaseId: purchaseId ?? this.purchaseId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      description: description ?? this.description,
      hsnSac: hsnSac ?? this.hsnSac,
      quantityScaled: quantityScaled ?? this.quantityScaled,
      unitCode: unitCode ?? this.unitCode,
      purchaseRatePaise: purchaseRatePaise ?? this.purchaseRatePaise,
      discountPaise: discountPaise ?? this.discountPaise,
      taxableAmountPaise: taxableAmountPaise ?? this.taxableAmountPaise,
      taxRateId: taxRateId ?? this.taxRateId,
      rateBasisPoints: rateBasisPoints ?? this.rateBasisPoints,
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
      isItcEligible: isItcEligible ?? this.isItcEligible,
      trackInventory: trackInventory ?? this.trackInventory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'purchase_id': purchaseId,
      'product_id': productId,
      'product_name': productName,
      'description': description,
      'hsn_sac': hsnSac,
      'quantity': quantityScaled,
      'unit_code': unitCode,
      'purchase_rate_paise': purchaseRatePaise,
      'discount_paise': discountPaise,
      'taxable_amount_paise': taxableAmountPaise,
      'tax_rate_id': taxRateId,
      'rate_basis_points': rateBasisPoints,
      'cgst_rate_basis_points': cgstRateBasisPoints,
      'cgst_amount_paise': cgstAmountPaise,
      'sgst_rate_basis_points': sgstRateBasisPoints,
      'sgst_amount_paise': sgstAmountPaise,
      'igst_rate_basis_points': igstRateBasisPoints,
      'igst_amount_paise': igstAmountPaise,
      'cess_rate_basis_points': cessRateBasisPoints,
      'cess_amount_paise': cessAmountPaise,
      'total_amount_paise': totalAmountPaise,
      'is_tax_inclusive': isTaxInclusive ? 1 : 0,
      'is_itc_eligible': isItcEligible ? 1 : 0,
      'track_inventory': trackInventory ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PurchaseItem.fromMap(Map<String, dynamic> map) {
    return PurchaseItem(
      id: map['id'] as String,
      purchaseId: map['purchase_id'] as String,
      productId: map['product_id'] as String,
      productName: (map['product_name'] ?? map['name'] ?? 'Product') as String,
      description: map['description'] as String?,
      hsnSac: (map['hsn_sac'] ?? map['hsn_sac_code']) as String?,
      quantityScaled: (map['quantity'] as num).toInt(),
      unitCode: (map['unit_code'] ?? map['unit_name'] ?? 'PCS') as String,
      purchaseRatePaise: (map['purchase_rate_paise'] ?? map['unit_cost_paise'] ?? 0) as int,
      discountPaise: (map['discount_paise'] as num? ?? 0).toInt(),
      taxableAmountPaise: (map['taxable_amount_paise'] as num).toInt(),
      taxRateId: (map['tax_rate_id'] ?? '') as String,
      rateBasisPoints: (map['rate_basis_points'] as num? ?? 0).toInt(),
      cgstRateBasisPoints: (map['cgst_rate_basis_points'] as num? ?? 0).toInt(),
      cgstAmountPaise: (map['cgst_amount_paise'] ?? map['cgst_paise'] ?? 0) as int,
      sgstRateBasisPoints: (map['sgst_rate_basis_points'] as num? ?? 0).toInt(),
      sgstAmountPaise: (map['sgst_amount_paise'] ?? map['sgst_paise'] ?? 0) as int,
      igstRateBasisPoints: (map['igst_rate_basis_points'] as num? ?? 0).toInt(),
      igstAmountPaise: (map['igst_amount_paise'] ?? map['igst_paise'] ?? 0) as int,
      cessRateBasisPoints: (map['cess_rate_basis_points'] as num? ?? 0).toInt(),
      cessAmountPaise: (map['cess_amount_paise'] ?? map['cess_paise'] ?? 0) as int,
      totalAmountPaise: (map['total_amount_paise'] as num).toInt(),
      isTaxInclusive: (map['is_tax_inclusive'] as int? ?? 0) == 1,
      isItcEligible: (map['is_itc_eligible'] as int? ?? 1) == 1,
      trackInventory: (map['track_inventory'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
