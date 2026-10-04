import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/utils/number_to_words.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';

/// Payment aggregate root representing funds received from customers or paid to suppliers.
class Payment {
  final String id;
  final String businessId;
  final String customerId; // Stored in DB as party_id (holds customerId or supplierId)
  final String? customerName;
  final String? customerPhone;
  final PartyType partyType;

  final String paymentNumber; // e.g. 'PAY-2026-0001', 'REC-2026-0001' or 'DRAFT'
  final DateTime paymentDate;
  final PaymentMethod paymentMethod;
  final int amountPaise;

  final String? accountId; // References cash_bank_accounts.id
  final String? accountName;
  final String? referenceNumber; // UTR, Cheque No, Transaction ID
  final String? notes;

  final PaymentStatus status;
  final List<PaymentAllocation> allocations;

  final DateTime? cancelledAt;
  final String? cancellationReason;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncVersion;
  final String syncStatus;

  const Payment({
    required this.id,
    required this.businessId,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    this.partyType = PartyType.customer,
    required this.paymentNumber,
    required this.paymentDate,
    required this.paymentMethod,
    required this.amountPaise,
    this.accountId,
    this.accountName,
    this.referenceNumber,
    this.notes,
    this.status = PaymentStatus.posted,
    this.allocations = const [],
    this.cancelledAt,
    this.cancellationReason,
    required this.createdAt,
    required this.updatedAt,
    this.syncVersion = 1,
    this.syncStatus = 'synced',
  });

  String get supplierId => customerId;
  String? get supplierName => customerName;
  String? get supplierPhone => customerPhone;
  String get partyId => customerId;
  bool get isCustomerPayment => partyType == PartyType.customer;
  bool get isSupplierPayment => partyType == PartyType.supplier;

  Money get amount => Money.fromPaise(amountPaise);

  int get allocatedAmountPaise =>
      allocations.fold(0, (sum, a) => sum + a.allocatedAmountPaise);

  int get unallocatedAmountPaise => amountPaise - allocatedAmountPaise;

  Money get allocatedAmount => Money.fromPaise(allocatedAmountPaise);
  Money get unallocatedAmount => Money.fromPaise(unallocatedAmountPaise);

  bool get isFullyAllocated => allocatedAmountPaise == amountPaise;
  bool get isPartiallyAllocated =>
      allocatedAmountPaise > 0 && allocatedAmountPaise < amountPaise;
  bool get hasUnallocatedFunds => unallocatedAmountPaise > 0;

  bool get isDraft => status == PaymentStatus.draft;
  bool get isPosted => status == PaymentStatus.posted;
  bool get isCancelled => status == PaymentStatus.cancelled;

  String get amountInWords =>
      amount.isZero ? 'Rupees Zero Only' : IndianNumberToWords.convert(amount);

  Payment copyWith({
    String? id,
    String? businessId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    PartyType? partyType,
    String? paymentNumber,
    DateTime? paymentDate,
    PaymentMethod? paymentMethod,
    int? amountPaise,
    String? accountId,
    String? accountName,
    String? referenceNumber,
    String? notes,
    PaymentStatus? status,
    List<PaymentAllocation>? allocations,
    DateTime? cancelledAt,
    String? cancellationReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncVersion,
    String? syncStatus,
  }) {
    return Payment(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      partyType: partyType ?? this.partyType,
      paymentNumber: paymentNumber ?? this.paymentNumber,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amountPaise: amountPaise ?? this.amountPaise,
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      allocations: allocations ?? this.allocations,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
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
      'party_id': customerId,
      'party_type': partyType == PartyType.supplier ? 'SUPPLIER' : 'CUSTOMER',
      'payment_type': partyType == PartyType.supplier ? 'PAYMENT' : 'RECEIPT',
      'payment_number': paymentNumber,
      'payment_date': paymentDate.toIso8601String().substring(0, 10),
      'payment_mode': paymentMethod.dbValue,
      'amount_paise': amountPaise,
      'account_id': accountId,
      'reference_number': referenceNumber,
      'notes': notes,
      'status': status.dbValue,
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancellation_reason': cancellationReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_version': syncVersion,
      'sync_status': syncStatus,
    };
  }

  factory Payment.fromMap(
    Map<String, dynamic> map, {
    List<PaymentAllocation> allocations = const [],
  }) {
    final partyTypeStr = (map['party_type'] as String?)?.toUpperCase();
    final paymentTypeStr = (map['payment_type'] as String?)?.toUpperCase();
    final isSupplier = partyTypeStr == 'SUPPLIER' || paymentTypeStr == 'PAYMENT';

    return Payment(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      customerId: (map['party_id'] ?? map['customer_id'] ?? map['supplier_id']) as String,
      customerName: (map['customer_name'] ?? map['supplier_name'] ?? map['party_name']) as String?,
      customerPhone: (map['customer_phone'] ?? map['supplier_phone'] ?? map['party_phone']) as String?,
      partyType: isSupplier ? PartyType.supplier : PartyType.customer,
      paymentNumber: map['payment_number'] as String,
      paymentDate: DateTime.parse(map['payment_date'] as String),
      paymentMethod: PaymentMethod.fromDbValue(
        (map['payment_mode'] ?? map['payment_method']) as String? ?? 'CASH',
      ),
      amountPaise: (map['amount_paise'] as num).toInt(),
      accountId: map['account_id'] as String?,
      accountName: map['account_name'] as String?,
      referenceNumber: map['reference_number'] as String?,
      notes: map['notes'] as String?,
      status: PaymentStatus.fromDbValue(
        map['status'] as String? ?? 'POSTED',
      ),
      allocations: allocations,
      cancelledAt: map['cancelled_at'] != null
          ? DateTime.tryParse(map['cancelled_at'] as String)
          : null,
      cancellationReason: map['cancellation_reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncVersion: (map['sync_version'] as int? ?? 1),
      syncStatus: (map['sync_status'] as String? ?? 'synced'),
    );
  }
}
