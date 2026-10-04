/// Represents the lifecycle status of an Expense.
enum ExpenseStatus {
  draft,
  posted,
  cancelled;

  String get dbValue {
    switch (this) {
      case ExpenseStatus.draft:
        return 'DRAFT';
      case ExpenseStatus.posted:
        return 'POSTED';
      case ExpenseStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static ExpenseStatus fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'POSTED':
        return ExpenseStatus.posted;
      case 'CANCELLED':
        return ExpenseStatus.cancelled;
      case 'DRAFT':
      default:
        return ExpenseStatus.draft;
    }
  }

  String get displayName {
    switch (this) {
      case ExpenseStatus.draft:
        return 'Draft';
      case ExpenseStatus.posted:
        return 'Posted';
      case ExpenseStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isDraft => this == ExpenseStatus.draft;
  bool get isPosted => this == ExpenseStatus.posted;
  bool get isCancelled => this == ExpenseStatus.cancelled;

  /// Returns true if the status transition from [this] to [next] is legally permitted.
  bool canTransitionTo(ExpenseStatus next) {
    if (this == next) return true;
    switch (this) {
      case ExpenseStatus.draft:
        return next == ExpenseStatus.posted;
      case ExpenseStatus.posted:
        return next == ExpenseStatus.cancelled;
      case ExpenseStatus.cancelled:
        return false;
    }
  }
}
