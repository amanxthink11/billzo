import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/payment/payment_method.dart';

/// Domain Aggregate representing an operational or indirect business Expense.
class Expense {
  final String id;
  final String businessId;
  final String? expenseNumber;
  final String categoryId;
  final String? categoryName;
  final DateTime expenseDate;
  final String payee;
  final String description;
  final int taxableAmountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalGstPaise;
  final int totalAmountPaise;
  final String? paymentAccountId;
  final String? paymentAccountName;
  final PaymentMethod paymentMethod;
  final String? referenceNumber;
  final String? notes;
  final ExpenseStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? postedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final int syncVersion;
  final String syncStatus;
  final DateTime? deletedAt;

  const Expense({
    required this.id,
    required this.businessId,
    this.expenseNumber,
    required this.categoryId,
    this.categoryName,
    required this.expenseDate,
    required this.payee,
    required this.description,
    required this.taxableAmountPaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    required this.totalGstPaise,
    required this.totalAmountPaise,
    this.paymentAccountId,
    this.paymentAccountName,
    this.paymentMethod = PaymentMethod.cash,
    this.referenceNumber,
    this.notes,
    this.status = ExpenseStatus.draft,
    required this.createdAt,
    required this.updatedAt,
    this.postedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.syncVersion = 1,
    this.syncStatus = 'synced',
    this.deletedAt,
  });

  // Money accessors
  Money get taxableAmount => Money.fromPaise(taxableAmountPaise);
  Money get cgst => Money.fromPaise(cgstPaise);
  Money get sgst => Money.fromPaise(sgstPaise);
  Money get igst => Money.fromPaise(igstPaise);
  Money get totalGst => Money.fromPaise(totalGstPaise);
  Money get totalAmount => Money.fromPaise(totalAmountPaise);

  bool get isDraft => status == ExpenseStatus.draft;
  bool get isPosted => status == ExpenseStatus.posted;
  bool get isCancelled => status == ExpenseStatus.cancelled;

  bool get canEdit => status.isDraft;
  bool get canPost => status.isDraft;
  bool get canCancel => status.isPosted;
  bool get isInterState => igstPaise > 0;

  Expense copyWith({
    String? id,
    String? businessId,
    String? expenseNumber,
    String? categoryId,
    String? categoryName,
    DateTime? expenseDate,
    String? payee,
    String? description,
    int? taxableAmountPaise,
    int? cgstPaise,
    int? sgstPaise,
    int? igstPaise,
    int? totalGstPaise,
    int? totalAmountPaise,
    String? paymentAccountId,
    String? paymentAccountName,
    PaymentMethod? paymentMethod,
    String? referenceNumber,
    String? notes,
    ExpenseStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? postedAt,
    DateTime? cancelledAt,
    String? cancellationReason,
    int? syncVersion,
    String? syncStatus,
    DateTime? deletedAt,
  }) {
    return Expense(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      expenseNumber: expenseNumber ?? this.expenseNumber,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      expenseDate: expenseDate ?? this.expenseDate,
      payee: payee ?? this.payee,
      description: description ?? this.description,
      taxableAmountPaise: taxableAmountPaise ?? this.taxableAmountPaise,
      cgstPaise: cgstPaise ?? this.cgstPaise,
      sgstPaise: sgstPaise ?? this.sgstPaise,
      igstPaise: igstPaise ?? this.igstPaise,
      totalGstPaise: totalGstPaise ?? this.totalGstPaise,
      totalAmountPaise: totalAmountPaise ?? this.totalAmountPaise,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      paymentAccountName: paymentAccountName ?? this.paymentAccountName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      postedAt: postedAt ?? this.postedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      syncVersion: syncVersion ?? this.syncVersion,
      syncStatus: syncStatus ?? this.syncStatus,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'expense_number': expenseNumber,
      'category_id': categoryId,
      'category': categoryName ?? '',
      'expense_date': expenseDate.toIso8601String(),
      'payee': payee,
      'description': description,
      'taxable_amount_paise': taxableAmountPaise,
      'cgst_paise': cgstPaise,
      'sgst_paise': sgstPaise,
      'igst_paise': igstPaise,
      'total_gst_paise': totalGstPaise,
      'total_amount_paise': totalAmountPaise,
      'amount_paise': totalAmountPaise,
      'payment_account_id': paymentAccountId,
      'payment_method': paymentMethod.dbValue,
      'payment_mode': paymentMethod.dbValue,
      'reference_number': referenceNumber,
      'notes': notes,
      'status': status.dbValue,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'posted_at': postedAt?.toUtc().toIso8601String(),
      'cancelled_at': cancelledAt?.toUtc().toIso8601String(),
      'cancellation_reason': cancellationReason,
      'sync_version': syncVersion,
      'sync_status': syncStatus,
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      expenseNumber: map['expense_number'] as String?,
      categoryId: map['category_id'] as String? ?? '',
      categoryName: map['category_name'] as String? ?? map['category'] as String?,
      expenseDate: DateTime.parse(map['expense_date'] as String),
      payee: map['payee'] as String? ?? '',
      description: map['description'] as String? ?? '',
      taxableAmountPaise: (map['taxable_amount_paise'] as num? ?? map['amount_paise'] as num? ?? 0).toInt(),
      cgstPaise: (map['cgst_paise'] as num? ?? 0).toInt(),
      sgstPaise: (map['sgst_paise'] as num? ?? 0).toInt(),
      igstPaise: (map['igst_paise'] as num? ?? 0).toInt(),
      totalGstPaise: (map['total_gst_paise'] as num? ?? 0).toInt(),
      totalAmountPaise: (map['total_amount_paise'] as num? ?? map['amount_paise'] as num? ?? 0).toInt(),
      paymentAccountId: map['payment_account_id'] as String?,
      paymentAccountName: map['payment_account_name'] as String?,
      paymentMethod: PaymentMethod.fromDbValue(map['payment_method'] as String? ?? map['payment_mode'] as String? ?? 'CASH'),
      referenceNumber: map['reference_number'] as String?,
      notes: map['notes'] as String?,
      status: ExpenseStatus.fromDbValue(map['status'] as String? ?? 'DRAFT'),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      postedAt: map['posted_at'] != null ? DateTime.tryParse(map['posted_at'] as String) : null,
      cancelledAt: map['cancelled_at'] != null ? DateTime.tryParse(map['cancelled_at'] as String) : null,
      cancellationReason: map['cancellation_reason'] as String?,
      syncVersion: (map['sync_version'] as num? ?? 1).toInt(),
      syncStatus: map['sync_status'] as String? ?? 'synced',
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'] as String) : null,
    );
  }
}
