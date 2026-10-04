import 'package:flutter/foundation.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/purchase/purchase_return_item.dart';

/// Purchase return / Debit Note aggregate entity.
@immutable
class PurchaseReturn {
  final String id;
  final String businessId;
  final String supplierId;
  final String originalPurchaseId;
  final String returnNumber; // e.g. 'DN-2026-0001'
  final DateTime returnDate;

  final int taxableAmountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int cessPaise;
  final int totalAmountPaise;

  final String? reason;
  final String status; // 'FINALIZED', 'CANCELLED'

  final List<PurchaseReturnItem> items;

  // Joined metadata
  final String? supplierName;
  final String? originalPurchaseNumber;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncVersion;
  final String syncStatus;

  const PurchaseReturn({
    required this.id,
    required this.businessId,
    required this.supplierId,
    required this.originalPurchaseId,
    required this.returnNumber,
    required this.returnDate,
    required this.taxableAmountPaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.cessPaise = 0,
    required this.totalAmountPaise,
    this.reason,
    this.status = 'FINALIZED',
    this.items = const [],
    this.supplierName,
    this.originalPurchaseNumber,
    required this.createdAt,
    required this.updatedAt,
    this.syncVersion = 1,
    this.syncStatus = 'synced',
  });

  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get cess => Money.fromPaise(cessPaise);
  int get totalTaxPaise => cgstPaise + sgstPaise + igstPaise + cessPaise;
  Money get totalTax => Money.fromPaise(totalTaxPaise);
  Money get totalAmount => Money.fromPaise(totalAmountPaise);

  PurchaseReturn copyWith({
    String? id,
    String? businessId,
    String? supplierId,
    String? originalPurchaseId,
    String? returnNumber,
    DateTime? returnDate,
    int? taxableAmountPaise,
    int? cgstPaise,
    int? sgstPaise,
    int? igstPaise,
    int? cessPaise,
    int? totalAmountPaise,
    String? reason,
    String? status,
    List<PurchaseReturnItem>? items,
    String? supplierName,
    String? originalPurchaseNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncVersion,
    String? syncStatus,
  }) {
    return PurchaseReturn(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      supplierId: supplierId ?? this.supplierId,
      originalPurchaseId: originalPurchaseId ?? this.originalPurchaseId,
      returnNumber: returnNumber ?? this.returnNumber,
      returnDate: returnDate ?? this.returnDate,
      taxableAmountPaise: taxableAmountPaise ?? this.taxableAmountPaise,
      cgstPaise: cgstPaise ?? this.cgstPaise,
      sgstPaise: sgstPaise ?? this.sgstPaise,
      igstPaise: igstPaise ?? this.igstPaise,
      cessPaise: cessPaise ?? this.cessPaise,
      totalAmountPaise: totalAmountPaise ?? this.totalAmountPaise,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      items: items ?? this.items,
      supplierName: supplierName ?? this.supplierName,
      originalPurchaseNumber: originalPurchaseNumber ?? this.originalPurchaseNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncVersion: syncVersion ?? this.syncVersion,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'supplier_id': supplierId,
      'original_purchase_id': originalPurchaseId,
      'return_number': returnNumber,
      'return_date': returnDate.toIso8601String().substring(0, 10),
      'taxable_amount_paise': taxableAmountPaise,
      'cgst_paise': cgstPaise,
      'sgst_paise': sgstPaise,
      'igst_paise': igstPaise,
      'cess_paise': cessPaise,
      'total_amount_paise': totalAmountPaise,
      'reason': reason,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_version': syncVersion,
      'sync_status': syncStatus,
    };
  }

  factory PurchaseReturn.fromMap(
    Map<String, dynamic> map, {
    List<PurchaseReturnItem> items = const [],
  }) {
    return PurchaseReturn(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      supplierId: map['supplier_id'] as String,
      originalPurchaseId: map['original_purchase_id'] as String,
      returnNumber: map['return_number'] as String,
      returnDate: DateTime.parse(map['return_date'] as String),
      taxableAmountPaise: (map['taxable_amount_paise'] as num? ?? 0).toInt(),
      cgstPaise: (map['cgst_paise'] as num? ?? 0).toInt(),
      sgstPaise: (map['sgst_paise'] as num? ?? 0).toInt(),
      igstPaise: (map['igst_paise'] as num? ?? 0).toInt(),
      cessPaise: (map['cess_paise'] as num? ?? 0).toInt(),
      totalAmountPaise: (map['total_amount_paise'] as num).toInt(),
      reason: map['reason'] as String?,
      status: (map['status'] as String? ?? 'FINALIZED'),
      items: items,
      supplierName: map['supplier_name'] as String?,
      originalPurchaseNumber: map['original_purchase_number'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncVersion: (map['sync_version'] as int? ?? 1),
      syncStatus: (map['sync_status'] as String? ?? 'synced'),
    );
  }
}
