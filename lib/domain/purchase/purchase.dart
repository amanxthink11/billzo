import 'package:flutter/foundation.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/utils/number_to_words.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';

/// Purchase bill aggregate root representing inward goods/services procurement from a supplier.
@immutable
class Purchase {
  final String id;
  final String businessId;
  final String supplierId;
  final String purchaseNumber; // Internal serial e.g. 'PUR-2026-0001' or 'DRAFT'
  final String? supplierInvoiceNumber; // Vendor's tax invoice/bill number
  final DateTime? supplierInvoiceDate; // Vendor's billing date
  final DateTime purchaseDate; // Inward recording date
  final DateTime dueDate;
  final String placeOfSupplyStateCode;
  final PurchaseStatus status;

  // Financial totals in integer paise
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

  // Input Tax Credit (ITC) tracking
  final ItcEligibility itcEligibility;
  final int inputCgstPaise;
  final int inputSgstPaise;
  final int inputIgstPaise;
  final int inputCessPaise;

  final String? notes;
  final DateTime? finalizedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  final List<PurchaseItem> items;

  // Presentation & joined metadata
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierGstin;
  final String? supplierCompanyName;
  final String? supplierAddress;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncVersion;
  final String syncStatus;

  const Purchase({
    required this.id,
    required this.businessId,
    required this.supplierId,
    required this.purchaseNumber,
    this.supplierInvoiceNumber,
    this.supplierInvoiceDate,
    required this.purchaseDate,
    required this.dueDate,
    required this.placeOfSupplyStateCode,
    this.status = PurchaseStatus.draft,
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
    this.itcEligibility = ItcEligibility.eligible,
    this.inputCgstPaise = 0,
    this.inputSgstPaise = 0,
    this.inputIgstPaise = 0,
    this.inputCessPaise = 0,
    this.notes,
    this.finalizedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.items = const [],
    this.supplierName,
    this.supplierPhone,
    this.supplierGstin,
    this.supplierCompanyName,
    this.supplierAddress,
    required this.createdAt,
    required this.updatedAt,
    this.syncVersion = 1,
    this.syncStatus = 'synced',
  });

  bool get isDraft => status == PurchaseStatus.draft;
  bool get isFinalized => status == PurchaseStatus.finalized;
  bool get isPartiallyPaid => status == PurchaseStatus.partiallyPaid;
  bool get isPaid => status == PurchaseStatus.paid;
  bool get isCancelled => status == PurchaseStatus.cancelled;

  Money get subtotal => Money.fromPaise(subtotalPaise);
  Money get discount => Money.fromPaise(discountPaise);
  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get cess => Money.fromPaise(cessPaise);
  int get totalTaxPaise => cgstPaise + sgstPaise + igstPaise + cessPaise;
  Money get totalTax => Money.fromPaise(totalTaxPaise);

  Money get roundOff => Money.fromPaise(roundOffPaise);
  Money get totalAmount => Money.fromPaise(totalAmountPaise);
  Money get paidAmount => Money.fromPaise(paidAmountPaise);
  Money get balanceAmount => Money.fromPaise(balanceAmountPaise);

  // Eligible ITC getters
  Money get inputCgst => Money.fromPaise(inputCgstPaise);
  Money get inputSgst => Money.fromPaise(inputSgstPaise);
  Money get inputIgst => Money.fromPaise(inputIgstPaise);
  Money get inputCess => Money.fromPaise(inputCessPaise);
  int get totalGstPaise => cgstPaise + sgstPaise + igstPaise + cessPaise;
  int get totalItcPaise => itcEligibility == ItcEligibility.eligible
      ? ((inputCgstPaise + inputSgstPaise + inputIgstPaise + inputCessPaise > 0)
          ? inputCgstPaise + inputSgstPaise + inputIgstPaise + inputCessPaise
          : totalGstPaise)
      : 0;
  Money get totalItc => Money.fromPaise(totalItcPaise);

  String get placeOfSupply => placeOfSupplyStateCode;
  int get eligibleItcPaise => totalItcPaise;
  int get ineligibleItcPaise =>
      itcEligibility == ItcEligibility.ineligible ? totalGstPaise : 0;
  Money get eligibleItc => Money.fromPaise(eligibleItcPaise);
  Money get ineligibleItc => Money.fromPaise(ineligibleItcPaise);

  String get amountInWords => totalAmount.isZero
      ? 'Rupees Zero Only'
      : IndianNumberToWords.convert(totalAmount);

  Purchase copyWith({
    String? id,
    String? businessId,
    String? supplierId,
    String? purchaseNumber,
    String? supplierInvoiceNumber,
    DateTime? supplierInvoiceDate,
    DateTime? purchaseDate,
    DateTime? dueDate,
    String? placeOfSupplyStateCode,
    PurchaseStatus? status,
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
    ItcEligibility? itcEligibility,
    int? inputCgstPaise,
    int? inputSgstPaise,
    int? inputIgstPaise,
    int? inputCessPaise,
    String? notes,
    DateTime? finalizedAt,
    DateTime? cancelledAt,
    String? cancellationReason,
    List<PurchaseItem>? items,
    String? supplierName,
    String? supplierPhone,
    String? supplierGstin,
    String? supplierCompanyName,
    String? supplierAddress,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncVersion,
    String? syncStatus,
  }) {
    return Purchase(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      supplierId: supplierId ?? this.supplierId,
      purchaseNumber: purchaseNumber ?? this.purchaseNumber,
      supplierInvoiceNumber: supplierInvoiceNumber ?? this.supplierInvoiceNumber,
      supplierInvoiceDate: supplierInvoiceDate ?? this.supplierInvoiceDate,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      dueDate: dueDate ?? this.dueDate,
      placeOfSupplyStateCode: placeOfSupplyStateCode ?? this.placeOfSupplyStateCode,
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
      itcEligibility: itcEligibility ?? this.itcEligibility,
      inputCgstPaise: inputCgstPaise ?? this.inputCgstPaise,
      inputSgstPaise: inputSgstPaise ?? this.inputSgstPaise,
      inputIgstPaise: inputIgstPaise ?? this.inputIgstPaise,
      inputCessPaise: inputCessPaise ?? this.inputCessPaise,
      notes: notes ?? this.notes,
      finalizedAt: finalizedAt ?? this.finalizedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      items: items ?? this.items,
      supplierName: supplierName ?? this.supplierName,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      supplierGstin: supplierGstin ?? this.supplierGstin,
      supplierCompanyName: supplierCompanyName ?? this.supplierCompanyName,
      supplierAddress: supplierAddress ?? this.supplierAddress,
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
      'purchase_number': purchaseNumber,
      'vendor_invoice_number': supplierInvoiceNumber,
      'supplier_invoice_number': supplierInvoiceNumber,
      'supplier_invoice_date': supplierInvoiceDate?.toIso8601String().substring(0, 10),
      'purchase_date': purchaseDate.toIso8601String().substring(0, 10),
      'due_date': dueDate.toIso8601String().substring(0, 10),
      'place_of_supply_state_code': placeOfSupplyStateCode,
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
      'itc_eligibility': itcEligibility.dbValue,
      'input_cgst_paise': inputCgstPaise,
      'input_sgst_paise': inputSgstPaise,
      'input_igst_paise': inputIgstPaise,
      'input_cess_paise': inputCessPaise,
      'notes': notes,
      'finalized_at': finalizedAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancellation_reason': cancellationReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_version': syncVersion,
      'sync_status': syncStatus,
    };
  }

  factory Purchase.fromMap(
    Map<String, dynamic> map, {
    List<PurchaseItem> items = const [],
  }) {
    return Purchase(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      supplierId: map['supplier_id'] as String,
      purchaseNumber: map['purchase_number'] as String,
      supplierInvoiceNumber: (map['supplier_invoice_number'] ?? map['vendor_invoice_number']) as String?,
      supplierInvoiceDate: map['supplier_invoice_date'] != null
          ? DateTime.tryParse(map['supplier_invoice_date'] as String)
          : null,
      purchaseDate: DateTime.parse(map['purchase_date'] as String),
      dueDate: DateTime.parse(map['due_date'] as String),
      placeOfSupplyStateCode: (map['place_of_supply_state_code'] ?? '27') as String,
      status: PurchaseStatus.fromDbValue(map['status'] as String? ?? 'DRAFT'),
      subtotalPaise: (map['subtotal_paise'] as num).toInt(),
      discountPaise: (map['discount_paise'] as num? ?? 0).toInt(),
      taxableAmountPaise: (map['taxable_amount_paise'] as num).toInt(),
      cgstPaise: (map['cgst_paise'] as num? ?? 0).toInt(),
      sgstPaise: (map['sgst_paise'] as num? ?? 0).toInt(),
      igstPaise: (map['igst_paise'] as num? ?? 0).toInt(),
      cessPaise: (map['cess_paise'] as num? ?? 0).toInt(),
      roundOffPaise: (map['round_off_paise'] as num? ?? 0).toInt(),
      totalAmountPaise: (map['total_amount_paise'] as num).toInt(),
      paidAmountPaise: (map['paid_amount_paise'] as num? ?? 0).toInt(),
      balanceAmountPaise: (map['balance_amount_paise'] as num).toInt(),
      itcEligibility: ItcEligibility.fromDbValue(map['itc_eligibility'] as String?),
      inputCgstPaise: (map['input_cgst_paise'] as num? ?? 0).toInt(),
      inputSgstPaise: (map['input_sgst_paise'] as num? ?? 0).toInt(),
      inputIgstPaise: (map['input_igst_paise'] as num? ?? 0).toInt(),
      inputCessPaise: (map['input_cess_paise'] as num? ?? 0).toInt(),
      notes: map['notes'] as String?,
      finalizedAt: map['finalized_at'] != null ? DateTime.tryParse(map['finalized_at'] as String) : null,
      cancelledAt: map['cancelled_at'] != null ? DateTime.tryParse(map['cancelled_at'] as String) : null,
      cancellationReason: map['cancellation_reason'] as String?,
      items: items,
      supplierName: map['supplier_name'] as String?,
      supplierPhone: map['supplier_phone'] as String?,
      supplierGstin: map['supplier_gstin'] as String?,
      supplierCompanyName: map['supplier_company_name'] as String?,
      supplierAddress: map['supplier_address'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncVersion: (map['sync_version'] as int? ?? 1),
      syncStatus: (map['sync_status'] as String? ?? 'synced'),
    );
  }
}
