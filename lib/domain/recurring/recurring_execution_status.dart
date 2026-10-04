/// Execution outcome of a scheduled recurring billing milestone.
enum RecurringExecutionStatus {
  success,
  skipped,
  reviewQueued;

  String get displayName {
    switch (this) {
      case RecurringExecutionStatus.success:
        return 'Success';
      case RecurringExecutionStatus.skipped:
        return 'Skipped';
      case RecurringExecutionStatus.reviewQueued:
        return 'Draft Review Queued';
    }
  }

  String toDbString() {
    switch (this) {
      case RecurringExecutionStatus.success:
        return 'SUCCESS';
      case RecurringExecutionStatus.skipped:
        return 'SKIPPED';
      case RecurringExecutionStatus.reviewQueued:
        return 'REVIEW_QUEUED';
    }
  }

  static RecurringExecutionStatus fromDbString(String val) {
    switch (val.toUpperCase().trim()) {
      case 'SUCCESS':
        return RecurringExecutionStatus.success;
      case 'SKIPPED':
        return RecurringExecutionStatus.skipped;
      case 'REVIEW_QUEUED':
      default:
        return RecurringExecutionStatus.reviewQueued;
    }
  }
}
