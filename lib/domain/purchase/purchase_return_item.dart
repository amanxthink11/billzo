import 'package:flutter/foundation.dart';
import 'package:billzo/core/money/money.dart';

/// Line item for a purchase return / debit note.
@immutable
class PurchaseReturnItem {
  final String id;
  final String purchaseReturnId;
  final String? purchaseItemId;
  final String productId;
  final String productName;
  final String unitCode;

  /// Quantity returned stored as scaled integer (e.g. 1.250 = 1250)
  final int quantityScaled;
  final int ratePaise;
  final int taxableAmountPaise;
  final int cgstAmountPaise;
  final int sgstAmountPaise;
  final int igstAmountPaise;
  final int cessAmountPaise;
  final int totalAmountPaise;
  final int taxRateBasisPoints;
  final bool trackInventory;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PurchaseReturnItem({
    required this.id,
    required this.purchaseReturnId,
    this.purchaseItemId,
    required this.productId,
    required this.productName,
    this.unitCode = 'PCS',
    required this.quantityScaled,
    required this.ratePaise,
    required this.taxableAmountPaise,
    this.cgstAmountPaise = 0,
    this.sgstAmountPaise = 0,
    this.igstAmountPaise = 0,
    this.cessAmountPaise = 0,
    required this.totalAmountPaise,
    this.taxRateBasisPoints = 0,
    this.trackInventory = true,
    required this.createdAt,
    required this.updatedAt,
  });

  double get quantity => quantityScaled / 1000.0;
  Money get rate => Money.fromPaise(ratePaise);
  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgstAmount => Money.fromPaise(cgstAmountPaise);
  Money get sgstAmount => Money.fromPaise(sgstAmountPaise);
  Money get igstAmount => Money.fromPaise(igstAmountPaise);
  Money get cessAmount => Money.fromPaise(cessAmountPaise);
  int get totalTaxPaise =>
      cgstAmountPaise + sgstAmountPaise + igstAmountPaise + cessAmountPaise;
  int get cgstPaise => cgstAmountPaise;
  int get sgstPaise => sgstAmountPaise;
  int get igstPaise => igstAmountPaise;
  int get cessPaise => cessAmountPaise;
  int get lineTotalPaise => totalAmountPaise;
  Money get totalAmount => Money.fromPaise(totalAmountPaise);

  PurchaseReturnItem copyWith({
    String? id,
    String? purchaseReturnId,
    String? purchaseItemId,
    String? productId,
    String? productName,
    String? unitCode,
    int? quantityScaled,
    int? ratePaise,
    int? taxableAmountPaise,
    int? cgstAmountPaise,
    int? sgstAmountPaise,
    int? igstAmountPaise,
    int? cessAmountPaise,
    int? totalAmountPaise,
    int? taxRateBasisPoints,
    bool? trackInventory,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchaseReturnItem(
      id: id ?? this.id,
      purchaseReturnId: purchaseReturnId ?? this.purchaseReturnId,
      purchaseItemId: purchaseItemId ?? this.purchaseItemId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unitCode: unitCode ?? this.unitCode,
      quantityScaled: quantityScaled ?? this.quantityScaled,
      ratePaise: ratePaise ?? this.ratePaise,
      taxableAmountPaise: taxableAmountPaise ?? this.taxableAmountPaise,
      cgstAmountPaise: cgstAmountPaise ?? this.cgstAmountPaise,
      sgstAmountPaise: sgstAmountPaise ?? this.sgstAmountPaise,
      igstAmountPaise: igstAmountPaise ?? this.igstAmountPaise,
      cessAmountPaise: cessAmountPaise ?? this.cessAmountPaise,
      totalAmountPaise: totalAmountPaise ?? this.totalAmountPaise,
      taxRateBasisPoints: taxRateBasisPoints ?? this.taxRateBasisPoints,
      trackInventory: trackInventory ?? this.trackInventory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'purchase_return_id': purchaseReturnId,
      'purchase_item_id': purchaseItemId,
      'product_id': productId,
      'product_name': productName,
      'unit_code': unitCode,
      'quantity': quantityScaled,
      'rate_paise': ratePaise,
      'taxable_amount_paise': taxableAmountPaise,
      'cgst_amount_paise': cgstAmountPaise,
      'sgst_amount_paise': sgstAmountPaise,
      'igst_amount_paise': igstAmountPaise,
      'cess_amount_paise': cessAmountPaise,
      'total_amount_paise': totalAmountPaise,
      'tax_rate_basis_points': taxRateBasisPoints,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PurchaseReturnItem.fromMap(Map<String, dynamic> map) {
    return PurchaseReturnItem(
      id: map['id'] as String,
      purchaseReturnId: map['purchase_return_id'] as String,
      purchaseItemId: map['purchase_item_id'] as String?,
      productId: map['product_id'] as String,
      productName: (map['product_name'] ?? 'Product') as String,
      unitCode: (map['unit_code'] ?? 'PCS') as String,
      quantityScaled: (map['quantity'] as num).toInt(),
      ratePaise: (map['rate_paise'] as num).toInt(),
      taxableAmountPaise: (map['taxable_amount_paise'] as num? ?? 0).toInt(),
      cgstAmountPaise: (map['cgst_amount_paise'] as num? ?? 0).toInt(),
      sgstAmountPaise: (map['sgst_amount_paise'] as num? ?? 0).toInt(),
      igstAmountPaise: (map['igst_amount_paise'] as num? ?? 0).toInt(),
      cessAmountPaise: (map['cess_amount_paise'] as num? ?? 0).toInt(),
      totalAmountPaise: (map['total_amount_paise'] as num).toInt(),
      taxRateBasisPoints: (map['tax_rate_basis_points'] as num? ?? 0).toInt(),
      trackInventory: (map['track_inventory'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
