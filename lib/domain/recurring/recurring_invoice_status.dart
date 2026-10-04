/// Lifecycle status of a recurring invoice template.
enum RecurringInvoiceStatus {
  active,
  paused,
  completed,
  cancelled;

  String get displayName {
    switch (this) {
      case RecurringInvoiceStatus.active:
        return 'Active';
      case RecurringInvoiceStatus.paused:
        return 'Paused';
      case RecurringInvoiceStatus.completed:
        return 'Completed';
      case RecurringInvoiceStatus.cancelled:
        return 'Cancelled';
    }
  }

  String toDbString() {
    switch (this) {
      case RecurringInvoiceStatus.active:
        return 'ACTIVE';
      case RecurringInvoiceStatus.paused:
        return 'PAUSED';
      case RecurringInvoiceStatus.completed:
        return 'COMPLETED';
      case RecurringInvoiceStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static RecurringInvoiceStatus fromDbString(String val) {
    switch (val.toUpperCase().trim()) {
      case 'ACTIVE':
        return RecurringInvoiceStatus.active;
      case 'PAUSED':
        return RecurringInvoiceStatus.paused;
      case 'COMPLETED':
        return RecurringInvoiceStatus.completed;
      case 'CANCELLED':
      default:
        return RecurringInvoiceStatus.cancelled;
    }
  }

  bool get canPause => this == RecurringInvoiceStatus.active;
  bool get canResume => this == RecurringInvoiceStatus.paused;
  bool get canCancel => this == RecurringInvoiceStatus.active || this == RecurringInvoiceStatus.paused;
  bool get canEdit => this == RecurringInvoiceStatus.active || this == RecurringInvoiceStatus.paused;
  bool get canExecute => this == RecurringInvoiceStatus.active;
}
