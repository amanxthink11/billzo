import 'package:billzo/domain/recurring/recurring_execution_status.dart';

/// Single log entry recording an execution milestone for a recurring invoice.
/// Guarantees idempotency via UNIQUE(recurring_invoice_id, scheduled_for_date).
class RecurringInvoiceExecution {
  final String id;
  final String recurringInvoiceId;
  final String? invoiceId;
  final DateTime scheduledForDate;
  final DateTime executedAt;
  final RecurringExecutionStatus executionStatus;
  final String? notes;
  final DateTime createdAt;

  const RecurringInvoiceExecution({
    required this.id,
    required this.recurringInvoiceId,
    this.invoiceId,
    required this.scheduledForDate,
    required this.executedAt,
    required this.executionStatus,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recurring_invoice_id': recurringInvoiceId,
      'invoice_id': invoiceId,
      'scheduled_for_date': scheduledForDate.toIso8601String().substring(0, 10),
      'executed_at': executedAt.toIso8601String(),
      'execution_status': executionStatus.toDbString(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory RecurringInvoiceExecution.fromMap(Map<String, dynamic> map) {
    return RecurringInvoiceExecution(
      id: map['id'] as String,
      recurringInvoiceId: map['recurring_invoice_id'] as String,
      invoiceId: map['invoice_id'] as String?,
      scheduledForDate: DateTime.parse(map['scheduled_for_date'] as String),
      executedAt: DateTime.parse(map['executed_at'] as String),
      executionStatus: RecurringExecutionStatus.fromDbString(map['execution_status'] as String),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
