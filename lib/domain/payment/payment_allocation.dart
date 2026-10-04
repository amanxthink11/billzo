import 'package:billzo/core/money/money.dart';

/// Represents the monetary allocation of a customer payment towards an outstanding sales invoice.
class PaymentAllocation {
  final String id;
  final String paymentId;
  final String documentId; // Sales Invoice ID
  final String documentType; // 'TAX_INVOICE'
  final int allocatedAmountPaise;

  // Snapshot / presentation helper fields (optional / joined from invoice or purchase)
  final String? invoiceNumber;
  final DateTime? invoiceDate;
  final int? invoiceTotalPaise;
  final int? invoiceOutstandingBeforePaise;

  // Purchase snapshot aliases
  String? get purchaseNumber => invoiceNumber;
  DateTime? get purchaseDate => invoiceDate;
  int? get purchaseTotalPaise => invoiceTotalPaise;
  int? get purchaseOutstandingBeforePaise => invoiceOutstandingBeforePaise;

  final DateTime createdAt;
  final DateTime updatedAt;

  PaymentAllocation({
    required this.id,
    required this.paymentId,
    required this.documentId,
    this.documentType = 'TAX_INVOICE',
    required this.allocatedAmountPaise,
    this.invoiceNumber,
    this.invoiceDate,
    this.invoiceTotalPaise,
    this.invoiceOutstandingBeforePaise,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Money get allocatedAmount => Money.fromPaise(allocatedAmountPaise);
  bool get isInvoiceAllocation => documentType == 'TAX_INVOICE' || documentType == 'INVOICE';
  bool get isPurchaseAllocation => documentType == 'PURCHASE';

  PaymentAllocation copyWith({
    String? id,
    String? paymentId,
    String? documentId,
    String? documentType,
    int? allocatedAmountPaise,
    String? invoiceNumber,
    DateTime? invoiceDate,
    int? invoiceTotalPaise,
    int? invoiceOutstandingBeforePaise,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentAllocation(
      id: id ?? this.id,
      paymentId: paymentId ?? this.paymentId,
      documentId: documentId ?? this.documentId,
      documentType: documentType ?? this.documentType,
      allocatedAmountPaise: allocatedAmountPaise ?? this.allocatedAmountPaise,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      invoiceTotalPaise: invoiceTotalPaise ?? this.invoiceTotalPaise,
      invoiceOutstandingBeforePaise: invoiceOutstandingBeforePaise ?? this.invoiceOutstandingBeforePaise,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'payment_id': paymentId,
      'document_id': documentId,
      'document_type': documentType,
      'allocated_amount_paise': allocatedAmountPaise,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PaymentAllocation.fromMap(Map<String, dynamic> map) {
    return PaymentAllocation(
      id: map['id'] as String,
      paymentId: map['payment_id'] as String,
      documentId: map['document_id'] as String,
      documentType: map['document_type'] as String? ?? 'TAX_INVOICE',
      allocatedAmountPaise: (map['allocated_amount_paise'] as num? ?? 0).toInt(),
      invoiceNumber: (map['invoice_number'] ?? map['purchase_number']) as String?,
      invoiceDate: map['invoice_date'] != null
          ? DateTime.tryParse(map['invoice_date'] as String)
          : (map['purchase_date'] != null ? DateTime.tryParse(map['purchase_date'] as String) : null),
      invoiceTotalPaise: (map['invoice_total_paise'] ?? map['purchase_total_paise'] as num?)?.toInt(),
      invoiceOutstandingBeforePaise: (map['invoice_outstanding_before_paise'] ?? map['purchase_outstanding_before_paise'] as num?)?.toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
