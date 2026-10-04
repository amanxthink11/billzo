import 'package:flutter/foundation.dart';

/// Immutable record of stock movement in the inventory ledger.
@immutable
class InventoryLedgerEntry {
  final String id;
  final String businessId;
  final String productId;
  final String? batchId;
  final String transactionType; // 'opening_stock', 'purchase', 'sale', etc.
  final String? referenceType;  // 'invoice', 'purchase', 'manual', etc.
  final String? referenceId;
  final double quantityChanged;
  final double stockBefore;
  final double stockAfter;
  final int costPerUnitPaise;
  final String? notes;
  final DateTime transactionDate;
  final DateTime createdAt;

  const InventoryLedgerEntry({
    required this.id,
    required this.businessId,
    required this.productId,
    this.batchId,
    required this.transactionType,
    this.referenceType,
    this.referenceId,
    required this.quantityChanged,
    required this.stockBefore,
    required this.stockAfter,
    this.costPerUnitPaise = 0,
    this.notes,
    required this.transactionDate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'product_id': productId,
      'batch_id': batchId,
      'transaction_type': transactionType,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'quantity_changed': quantityChanged,
      'stock_before': stockBefore,
      'stock_after': stockAfter,
      'cost_per_unit_paise': costPerUnitPaise,
      'notes': notes,
      'transaction_date': transactionDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory InventoryLedgerEntry.fromMap(Map<String, dynamic> map) {
    return InventoryLedgerEntry(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      productId: map['product_id'] as String,
      batchId: map['batch_id'] as String?,
      transactionType: map['transaction_type'] as String,
      referenceType: map['reference_type'] as String?,
      referenceId: map['reference_id'] as String?,
      quantityChanged: (map['quantity_changed'] as num).toDouble(),
      stockBefore: (map['stock_before'] as num).toDouble(),
      stockAfter: (map['stock_after'] as num).toDouble(),
      costPerUnitPaise: map['cost_per_unit_paise'] as int? ?? 0,
      notes: map['notes'] as String?,
      transactionDate: DateTime.parse(map['transaction_date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
