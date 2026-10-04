import 'package:billzo/core/money/money.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';

/// Aggregate root representing a recurring invoicing profile and billing schedule.
class RecurringInvoice {
  final String id;
  final String businessId;
  final String customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerGstin;
  final String profileName;
  final RecurringFrequency frequency;
  final int? customIntervalDays;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextRunDate;
  final DateTime? lastRunDate;
  final int paymentTermsDays;
  final bool autoGenerate;
  final bool requireReview;
  final RecurringInvoiceStatus status;
  final String? notes;
  final List<RecurringInvoiceItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RecurringInvoice({
    required this.id,
    required this.businessId,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerGstin,
    required this.profileName,
    required this.frequency,
    this.customIntervalDays,
    required this.startDate,
    this.endDate,
    required this.nextRunDate,
    this.lastRunDate,
    this.paymentTermsDays = 15,
    this.autoGenerate = false,
    this.requireReview = true,
    this.status = RecurringInvoiceStatus.active,
    this.notes,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  int get subtotalPaise =>
      items.fold<int>(0, (sum, item) => sum + item.taxableAmountPaise);
  Money get subtotal => Money.fromPaise(subtotalPaise);

  int get totalAmountPaise => subtotalPaise;
  Money get totalAmount => Money.fromPaise(totalAmountPaise);

  int get anchorDayOfMonth => startDate.day;
  bool get isDueTodayOrOverdue => isDue(DateTime.now());
  bool get autoSendEmail => autoGenerate;
  bool get generateAsDraft => requireReview;

  int get itemsCount => items.length;

  bool get isActive => status == RecurringInvoiceStatus.active;
  bool get isPaused => status == RecurringInvoiceStatus.paused;
  bool get isCompleted => status == RecurringInvoiceStatus.completed;
  bool get isCancelled => status == RecurringInvoiceStatus.cancelled;

  /// Returns whether this profile is currently due for execution on or before [asOfDate].
  bool isDue(DateTime asOfDate) {
    if (!isActive) return false;
    final asOfDay = DateTime(asOfDate.year, asOfDate.month, asOfDate.day, 23, 59, 59);
    final isPastNextRun = !nextRunDate.isAfter(asOfDay);
    if (!isPastNextRun) return false;

    if (endDate != null) {
      final endDay = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);
      return !nextRunDate.isAfter(endDay);
    }
    return true;
  }

  RecurringInvoice copyWith({
    String? id,
    String? businessId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerGstin,
    String? profileName,
    RecurringFrequency? frequency,
    int? customIntervalDays,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? nextRunDate,
    DateTime? lastRunDate,
    int? paymentTermsDays,
    bool? autoGenerate,
    bool? requireReview,
    RecurringInvoiceStatus? status,
    String? notes,
    List<RecurringInvoiceItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RecurringInvoice(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerGstin: customerGstin ?? this.customerGstin,
      profileName: profileName ?? this.profileName,
      frequency: frequency ?? this.frequency,
      customIntervalDays: customIntervalDays ?? this.customIntervalDays,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      nextRunDate: nextRunDate ?? this.nextRunDate,
      lastRunDate: lastRunDate ?? this.lastRunDate,
      paymentTermsDays: paymentTermsDays ?? this.paymentTermsDays,
      autoGenerate: autoGenerate ?? this.autoGenerate,
      requireReview: requireReview ?? this.requireReview,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'customer_id': customerId,
      'profile_name': profileName,
      'frequency': frequency.toDbString(),
      'custom_interval_days': customIntervalDays,
      'start_date': startDate.toIso8601String().substring(0, 10),
      'end_date': endDate?.toIso8601String().substring(0, 10),
      'next_run_date': nextRunDate.toIso8601String().substring(0, 10),
      'last_run_date': lastRunDate?.toIso8601String().substring(0, 10),
      'payment_terms_days': paymentTermsDays,
      'auto_generate': autoGenerate ? 1 : 0,
      'require_review': requireReview ? 1 : 0,
      'status': status.toDbString(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory RecurringInvoice.fromMap(Map<String, dynamic> map, {List<RecurringInvoiceItem> items = const []}) {
    return RecurringInvoice(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      customerId: map['customer_id'] as String,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      customerGstin: map['customer_gstin'] as String?,
      profileName: map['profile_name'] as String,
      frequency: RecurringFrequency.fromDbString(map['frequency'] as String),
      customIntervalDays: map['custom_interval_days'] as int?,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date'] as String) : null,
      nextRunDate: DateTime.parse(map['next_run_date'] as String),
      lastRunDate: map['last_run_date'] != null ? DateTime.parse(map['last_run_date'] as String) : null,
      paymentTermsDays: ((map['payment_terms_days'] as num?) ?? 15).toInt(),
      autoGenerate: ((map['auto_generate'] as num?) ?? 0).toInt() == 1,
      requireReview: ((map['require_review'] as num?) ?? 1).toInt() == 1,
      status: RecurringInvoiceStatus.fromDbString((map['status'] as String?) ?? 'ACTIVE'),
      notes: map['notes'] as String?,
      items: items,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
