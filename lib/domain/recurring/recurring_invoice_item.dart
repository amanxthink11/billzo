import 'package:billzo/core/money/money.dart';

/// Single item template in a recurring invoice profile.
class RecurringInvoiceItem {
  final String id;
  final String recurringInvoiceId;
  final String productId;
  final String taxRateId;
  final String productName;
  final String? hsnSac;
  final int quantity;
  final String unitCode;
  final int ratePaise;
  final int discountPaise;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RecurringInvoiceItem({
    required this.id,
    required this.recurringInvoiceId,
    required this.productId,
    required this.taxRateId,
    required this.productName,
    this.hsnSac,
    required this.quantity,
    required this.unitCode,
    required this.ratePaise,
    this.discountPaise = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Money get rate => Money.fromPaise(ratePaise);
  Money get discount => Money.fromPaise(discountPaise);

  int get grossAmountPaise => ratePaise * quantity;
  Money get grossAmount => Money.fromPaise(grossAmountPaise);

  int get taxableAmountPaise {
    final net = grossAmountPaise - discountPaise;
    return net > 0 ? net : 0;
  }

  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);

  RecurringInvoiceItem copyWith({
    String? id,
    String? recurringInvoiceId,
    String? productId,
    String? taxRateId,
    String? productName,
    String? hsnSac,
    int? quantity,
    String? unitCode,
    int? ratePaise,
    int? discountPaise,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RecurringInvoiceItem(
      id: id ?? this.id,
      recurringInvoiceId: recurringInvoiceId ?? this.recurringInvoiceId,
      productId: productId ?? this.productId,
      taxRateId: taxRateId ?? this.taxRateId,
      productName: productName ?? this.productName,
      hsnSac: hsnSac ?? this.hsnSac,
      quantity: quantity ?? this.quantity,
      unitCode: unitCode ?? this.unitCode,
      ratePaise: ratePaise ?? this.ratePaise,
      discountPaise: discountPaise ?? this.discountPaise,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recurring_invoice_id': recurringInvoiceId,
      'product_id': productId,
      'tax_rate_id': taxRateId,
      'product_name': productName,
      'hsn_sac': hsnSac,
      'quantity': quantity,
      'unit_code': unitCode,
      'rate_paise': ratePaise,
      'discount_paise': discountPaise,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory RecurringInvoiceItem.fromMap(Map<String, dynamic> map) {
    return RecurringInvoiceItem(
      id: map['id'] as String,
      recurringInvoiceId: map['recurring_invoice_id'] as String,
      productId: map['product_id'] as String,
      taxRateId: map['tax_rate_id'] as String,
      productName: (map['product_name'] as String?) ?? 'Item',
      hsnSac: map['hsn_sac'] as String?,
      quantity: (map['quantity'] as num).toInt(),
      unitCode: map['unit_code'] as String,
      ratePaise: (map['rate_paise'] as num).toInt(),
      discountPaise: ((map['discount_paise'] as num?) ?? 0).toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
