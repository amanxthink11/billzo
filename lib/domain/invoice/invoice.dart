import 'package:flutter/foundation.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/utils/number_to_words.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';

/// Sales Invoice aggregate entity.
@immutable
class Invoice {
  final String id;
  final String businessId;
  final String customerId;
  final String? recurringInvoiceId;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final DateTime dueDate;
  final String placeOfSupplyStateCode;
  final InvoiceType invoiceType;
  final InvoiceStatus status;

  // Financial totals (in integer paise)
  final int subtotalPaise;
  final int discountPaise;
  final int taxableAmountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int cessPaise;
  final int roundOffPaise;
  final int totalAmountPaise;
  final int paidAmountPaise;
  final int balanceAmountPaise;

  final String? notes;
  final String? termsAndConditions;
  final DateTime? finalizedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Line items belonging to this invoice
  final List<InvoiceItem> items;

  // Join metadata for UI convenience
  final String? customerName;
  final String? customerPhone;
  final String? customerGstin;
  final String? customerCompanyName;
  final String? customerAddress;

  const Invoice({
    required this.id,
    required this.businessId,
    required this.customerId,
    this.recurringInvoiceId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.dueDate,
    required this.placeOfSupplyStateCode,
    this.invoiceType = InvoiceType.taxInvoice,
    this.status = InvoiceStatus.draft,
    required this.subtotalPaise,
    this.discountPaise = 0,
    required this.taxableAmountPaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.cessPaise = 0,
    this.roundOffPaise = 0,
    required this.totalAmountPaise,
    this.paidAmountPaise = 0,
    required this.balanceAmountPaise,
    this.notes,
    this.termsAndConditions,
    this.finalizedAt,
    this.cancelledAt,
    this.cancellationReason,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.customerName,
    this.customerPhone,
    this.customerGstin,
    this.customerCompanyName,
    this.customerAddress,
  });

  InvoiceLifecycleStatus get lifecycleStatus {
    if (status == InvoiceStatus.cancelled) return InvoiceLifecycleStatus.cancelled;
    if (status == InvoiceStatus.draft) return InvoiceLifecycleStatus.draft;
    return InvoiceLifecycleStatus.finalized;
  }

  InvoicePaymentStatus get paymentStatus {
    if (paidAmountPaise <= 0) {
      return InvoicePaymentStatus.due;
    } else if (paidAmountPaise < totalAmountPaise) {
      return InvoicePaymentStatus.partiallyPaid;
    } else {
      return InvoicePaymentStatus.paid;
    }
  }

  bool get isDraft => status == InvoiceStatus.draft;
  bool get isFinalized => status != InvoiceStatus.draft && status != InvoiceStatus.cancelled;
  bool get isCancelled => status == InvoiceStatus.cancelled;
  bool get isPaid => paymentStatus == InvoicePaymentStatus.paid;
  bool get isPartiallyPaid => paymentStatus == InvoicePaymentStatus.partiallyPaid;
  bool get isDue => paymentStatus == InvoicePaymentStatus.due;

  Money get subtotal => Money.fromPaise(subtotalPaise);
  Money get discount => Money.fromPaise(discountPaise);
  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get cess => Money.fromPaise(cessPaise);
  Money get totalTax => Money.fromPaise(cgstPaise + sgstPaise + igstPaise + cessPaise);
  Money get roundOff => Money.fromPaise(roundOffPaise);
  Money get totalAmount => Money.fromPaise(totalAmountPaise);
  Money get paidAmount => Money.fromPaise(paidAmountPaise);
  Money get balanceAmount => Money.fromPaise(balanceAmountPaise);

  /// Grand total formatted in Indian Words (e.g. "Rupees One Lakh Twenty-Five Thousand Only").
  String get amountInWords => IndianNumberToWords.convert(totalAmount);

  Invoice copyWith({
    String? id,
    String? businessId,
    String? customerId,
    String? recurringInvoiceId,
    String? invoiceNumber,
    DateTime? invoiceDate,
    DateTime? dueDate,
    String? placeOfSupplyStateCode,
    InvoiceType? invoiceType,
    InvoiceStatus? status,
    int? subtotalPaise,
    int? discountPaise,
    int? taxableAmountPaise,
    int? cgstPaise,
    int? sgstPaise,
    int? igstPaise,
    int? cessPaise,
    int? roundOffPaise,
    int? totalAmountPaise,
    int? paidAmountPaise,
    int? balanceAmountPaise,
    String? notes,
    String? termsAndConditions,
    DateTime? finalizedAt,
    DateTime? cancelledAt,
    String? cancellationReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<InvoiceItem>? items,
    String? customerName,
    String? customerPhone,
    String? customerGstin,
    String? customerCompanyName,
    String? customerAddress,
  }) {
    return Invoice(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      recurringInvoiceId: recurringInvoiceId ?? this.recurringInvoiceId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      dueDate: dueDate ?? this.dueDate,
      placeOfSupplyStateCode: placeOfSupplyStateCode ?? this.placeOfSupplyStateCode,
      invoiceType: invoiceType ?? this.invoiceType,
      status: status ?? this.status,
      subtotalPaise: subtotalPaise ?? this.subtotalPaise,
      discountPaise: discountPaise ?? this.discountPaise,
      taxableAmountPaise: taxableAmountPaise ?? this.taxableAmountPaise,
      cgstPaise: cgstPaise ?? this.cgstPaise,
      sgstPaise: sgstPaise ?? this.sgstPaise,
      igstPaise: igstPaise ?? this.igstPaise,
      cessPaise: cessPaise ?? this.cessPaise,
      roundOffPaise: roundOffPaise ?? this.roundOffPaise,
      totalAmountPaise: totalAmountPaise ?? this.totalAmountPaise,
      paidAmountPaise: paidAmountPaise ?? this.paidAmountPaise,
      balanceAmountPaise: balanceAmountPaise ?? this.balanceAmountPaise,
      notes: notes ?? this.notes,
      termsAndConditions: termsAndConditions ?? this.termsAndConditions,
      finalizedAt: finalizedAt ?? this.finalizedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerGstin: customerGstin ?? this.customerGstin,
      customerCompanyName: customerCompanyName ?? this.customerCompanyName,
      customerAddress: customerAddress ?? this.customerAddress,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'customer_id': customerId,
      'recurring_invoice_id': recurringInvoiceId,
      'invoice_number': invoiceNumber,
      'invoice_date': invoiceDate.toIso8601String().substring(0, 10),
      'due_date': dueDate.toIso8601String().substring(0, 10),
      'place_of_supply_state_code': placeOfSupplyStateCode,
      'invoice_type': invoiceType.dbValue,
      'status': status.dbValue,
      'subtotal_paise': subtotalPaise,
      'discount_paise': discountPaise,
      'taxable_amount_paise': taxableAmountPaise,
      'cgst_paise': cgstPaise,
      'sgst_paise': sgstPaise,
      'igst_paise': igstPaise,
      'cess_paise': cessPaise,
      'round_off_paise': roundOffPaise,
      'total_amount_paise': totalAmountPaise,
      'paid_amount_paise': paidAmountPaise,
      'balance_amount_paise': balanceAmountPaise,
      'notes': notes,
      'terms_and_conditions': termsAndConditions,
      'finalized_at': finalizedAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancellation_reason': cancellationReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_version': 1,
      'sync_status': 'synced',
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map, {List<InvoiceItem> items = const []}) {
    return Invoice(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      customerId: map['customer_id'] as String,
      recurringInvoiceId: map['recurring_invoice_id'] as String?,
      invoiceNumber: map['invoice_number'] as String,
      invoiceDate: DateTime.parse(map['invoice_date'] as String),
      dueDate: DateTime.parse(map['due_date'] as String),
      placeOfSupplyStateCode: map['place_of_supply_state_code'] as String,
      invoiceType: InvoiceType.fromDbValue(map['invoice_type'] as String? ?? 'TAX_INVOICE'),
      status: InvoiceStatus.fromDbValue(map['status'] as String? ?? 'DRAFT'),
      subtotalPaise: map['subtotal_paise'] as int,
      discountPaise: map['discount_paise'] as int? ?? 0,
      taxableAmountPaise: map['taxable_amount_paise'] as int,
      cgstPaise: map['cgst_paise'] as int? ?? 0,
      sgstPaise: map['sgst_paise'] as int? ?? 0,
      igstPaise: map['igst_paise'] as int? ?? 0,
      cessPaise: map['cess_paise'] as int? ?? 0,
      roundOffPaise: map['round_off_paise'] as int? ?? 0,
      totalAmountPaise: map['total_amount_paise'] as int,
      paidAmountPaise: map['paid_amount_paise'] as int? ?? 0,
      balanceAmountPaise: map['balance_amount_paise'] as int,
      notes: map['notes'] as String?,
      termsAndConditions: map['terms_and_conditions'] as String?,
      finalizedAt: map['finalized_at'] != null ? DateTime.parse(map['finalized_at'] as String) : null,
      cancelledAt: map['cancelled_at'] != null ? DateTime.parse(map['cancelled_at'] as String) : null,
      cancellationReason: map['cancellation_reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      items: items,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      customerGstin: map['customer_gstin'] as String?,
      customerCompanyName: map['customer_company_name'] as String?,
      customerAddress: map['customer_address'] as String?,
    );
  }
}

/// Payment status for sales invoices derived from authoritative financial balance.
enum InvoicePaymentStatus {
  due,
  partiallyPaid,
  paid;

  String get displayName {
    switch (this) {
      case InvoicePaymentStatus.due:
        return 'Due';
      case InvoicePaymentStatus.partiallyPaid:
        return 'Partially Paid';
      case InvoicePaymentStatus.paid:
        return 'Paid';
    }
  }

  String get code {
    switch (this) {
      case InvoicePaymentStatus.due:
        return 'DUE';
      case InvoicePaymentStatus.partiallyPaid:
        return 'PARTIALLY PAID';
      case InvoicePaymentStatus.paid:
        return 'PAID';
    }
  }
}

/// Lifecycle status for sales invoices.
enum InvoiceLifecycleStatus {
  draft,
  finalized,
  cancelled;

  String get displayName {
    switch (this) {
      case InvoiceLifecycleStatus.draft:
        return 'Draft';
      case InvoiceLifecycleStatus.finalized:
        return 'Finalized';
      case InvoiceLifecycleStatus.cancelled:
        return 'Cancelled';
    }
  }
}
