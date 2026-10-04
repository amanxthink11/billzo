/// Supported billing frequencies for recurring invoices.
enum RecurringFrequency {
  daily,
  weekly,
  biWeekly,
  monthly,
  quarterly,
  halfYearly,
  yearly,
  custom;

  String get displayName {
    switch (this) {
      case RecurringFrequency.daily:
        return 'Daily';
      case RecurringFrequency.weekly:
        return 'Weekly';
      case RecurringFrequency.biWeekly:
        return 'Bi-Weekly (Every 2 Weeks)';
      case RecurringFrequency.monthly:
        return 'Monthly';
      case RecurringFrequency.quarterly:
        return 'Quarterly (Every 3 Months)';
      case RecurringFrequency.halfYearly:
        return 'Half-Yearly (Every 6 Months)';
      case RecurringFrequency.yearly:
        return 'Yearly';
      case RecurringFrequency.custom:
        return 'Custom Interval';
    }
  }

  String toDbString() {
    switch (this) {
      case RecurringFrequency.daily:
        return 'DAILY';
      case RecurringFrequency.weekly:
        return 'WEEKLY';
      case RecurringFrequency.biWeekly:
        return 'BI_WEEKLY';
      case RecurringFrequency.monthly:
        return 'MONTHLY';
      case RecurringFrequency.quarterly:
        return 'QUARTERLY';
      case RecurringFrequency.halfYearly:
        return 'HALF_YEARLY';
      case RecurringFrequency.yearly:
        return 'YEARLY';
      case RecurringFrequency.custom:
        return 'CUSTOM';
    }
  }

  static RecurringFrequency fromDbString(String val) {
    switch (val.toUpperCase().trim()) {
      case 'DAILY':
        return RecurringFrequency.daily;
      case 'WEEKLY':
        return RecurringFrequency.weekly;
      case 'BI_WEEKLY':
      case 'BIWEEKLY':
        return RecurringFrequency.biWeekly;
      case 'MONTHLY':
        return RecurringFrequency.monthly;
      case 'QUARTERLY':
        return RecurringFrequency.quarterly;
      case 'HALF_YEARLY':
      case 'HALFYEARLY':
        return RecurringFrequency.halfYearly;
      case 'YEARLY':
        return RecurringFrequency.yearly;
      case 'CUSTOM':
      default:
        return RecurringFrequency.custom;
    }
  }

  /// Calculates next execution date preserving month-end anchor days (e.g. Jan 31 -> Feb 28 -> Mar 31).
  DateTime calculateNextRunDate(
    DateTime currentRunDate, {
    int? customIntervalDays,
    int? anchorDay,
  }) {
    final effectiveAnchor = anchorDay ?? currentRunDate.day;

    switch (this) {
      case RecurringFrequency.daily:
        return currentRunDate.add(const Duration(days: 1));

      case RecurringFrequency.weekly:
        return currentRunDate.add(const Duration(days: 7));

      case RecurringFrequency.biWeekly:
        return currentRunDate.add(const Duration(days: 14));

      case RecurringFrequency.monthly:
        return _addMonthsWithAnchor(currentRunDate, 1, effectiveAnchor);

      case RecurringFrequency.quarterly:
        return _addMonthsWithAnchor(currentRunDate, 3, effectiveAnchor);

      case RecurringFrequency.halfYearly:
        return _addMonthsWithAnchor(currentRunDate, 6, effectiveAnchor);

      case RecurringFrequency.yearly:
        return _addYearsWithAnchor(currentRunDate, 1, effectiveAnchor);

      case RecurringFrequency.custom:
        final days = (customIntervalDays != null && customIntervalDays > 0) ? customIntervalDays : 30;
        return currentRunDate.add(Duration(days: days));
    }
  }

  /// Adds N months while honoring anchor day (clamping to last day of target month if needed).
  static DateTime _addMonthsWithAnchor(DateTime date, int monthsToAdd, int anchorDay) {
    final targetTotalMonths = date.year * 12 + (date.month - 1) + monthsToAdd;
    final targetYear = targetTotalMonths ~/ 12;
    final targetMonth = (targetTotalMonths % 12) + 1;

    final daysInTargetMonth = _daysInMonth(targetYear, targetMonth);
    final clampedDay = anchorDay > daysInTargetMonth ? daysInTargetMonth : anchorDay;

    return DateTime(
      targetYear,
      targetMonth,
      clampedDay,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  /// Adds N years while honoring anchor day and February 29 leap years.
  static DateTime _addYearsWithAnchor(DateTime date, int yearsToAdd, int anchorDay) {
    final targetYear = date.year + yearsToAdd;
    final daysInTargetMonth = _daysInMonth(targetYear, date.month);
    final clampedDay = anchorDay > daysInTargetMonth ? daysInTargetMonth : anchorDay;

    return DateTime(
      targetYear,
      date.month,
      clampedDay,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  static int _daysInMonth(int year, int month) {
    // 0th day of next month is last day of requested month
    return DateTime(year, month + 1, 0).day;
  }
}
