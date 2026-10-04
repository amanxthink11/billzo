import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';

void main() {
  group('RecurringFrequency Tests', () {
    test('Daily frequency advances by 1 day', () {
      final start = DateTime(2026, 3, 15);
      final next = RecurringFrequency.daily.calculateNextRunDate(start);
      expect(next, equals(DateTime(2026, 3, 16)));
    });

    test('Weekly frequency advances by 7 days', () {
      final start = DateTime(2026, 3, 10);
      final next = RecurringFrequency.weekly.calculateNextRunDate(start);
      expect(next, equals(DateTime(2026, 3, 17)));
    });

    test('BiWeekly frequency advances by 14 days', () {
      final start = DateTime(2026, 3, 1);
      final next = RecurringFrequency.biWeekly.calculateNextRunDate(start);
      expect(next, equals(DateTime(2026, 3, 15)));
    });

    test('Monthly frequency preserves anchor day at month ends (Jan 31 -> Feb 28 -> Mar 31)', () {
      final jan31 = DateTime(2026, 1, 31);
      
      // Jan 31 -> Feb 28 (2026 is non-leap year)
      final feb = RecurringFrequency.monthly.calculateNextRunDate(jan31, anchorDay: 31);
      expect(feb, equals(DateTime(2026, 2, 28)));

      // Feb 28 -> Mar 31 (Preserves anchor day 31!)
      final mar = RecurringFrequency.monthly.calculateNextRunDate(feb, anchorDay: 31);
      expect(mar, equals(DateTime(2026, 3, 31)));

      // Mar 31 -> Apr 30 (April has 30 days)
      final apr = RecurringFrequency.monthly.calculateNextRunDate(mar, anchorDay: 31);
      expect(apr, equals(DateTime(2026, 4, 30)));

      // Apr 30 -> May 31 (Recovers 31)
      final may = RecurringFrequency.monthly.calculateNextRunDate(apr, anchorDay: 31);
      expect(may, equals(DateTime(2026, 5, 31)));
    });

    test('Quarterly frequency advances by 3 months with anchor day preservation', () {
      final nov30 = DateTime(2025, 11, 30);
      // Nov 30 (anchor 31) -> Feb 28
      final feb = RecurringFrequency.quarterly.calculateNextRunDate(nov30, anchorDay: 31);
      expect(feb, equals(DateTime(2026, 2, 28)));

      // Feb 28 (anchor 31) -> May 31
      final may = RecurringFrequency.quarterly.calculateNextRunDate(feb, anchorDay: 31);
      expect(may, equals(DateTime(2026, 5, 31)));
    });

    test('Half-Yearly frequency advances by 6 months', () {
      final jan15 = DateTime(2026, 1, 15);
      final jul15 = RecurringFrequency.halfYearly.calculateNextRunDate(jan15, anchorDay: 15);
      expect(jul15, equals(DateTime(2026, 7, 15)));
    });

    test('Yearly frequency advances by 1 year and respects leap years', () {
      // Leap day Feb 29, 2024 -> Feb 28, 2025
      final leapDay = DateTime(2024, 2, 29);
      final nextYear = RecurringFrequency.yearly.calculateNextRunDate(leapDay, anchorDay: 29);
      expect(nextYear, equals(DateTime(2025, 2, 28)));
    });

    test('Custom frequency advances by customIntervalDays', () {
      final start = DateTime(2026, 3, 1);
      final next = RecurringFrequency.custom.calculateNextRunDate(start, customIntervalDays: 45);
      expect(next, equals(DateTime(2026, 4, 15)));
    });

    test('toDbString and fromDbString bidirectional conversion', () {
      for (final freq in RecurringFrequency.values) {
        final dbStr = freq.toDbString();
        final recovered = RecurringFrequency.fromDbString(dbStr);
        expect(recovered, equals(freq));
      }
    });

    test('calculateNextRunDate advances consecutively across month boundaries', () {
      final start = DateTime(2026, 1, 1);
      final next1 = RecurringFrequency.monthly.calculateNextRunDate(start, anchorDay: 1);
      expect(next1, equals(DateTime(2026, 2, 1)));

      final next2 = RecurringFrequency.monthly.calculateNextRunDate(next1, anchorDay: 1);
      expect(next2, equals(DateTime(2026, 3, 1)));

      final next3 = RecurringFrequency.monthly.calculateNextRunDate(next2, anchorDay: 1);
      expect(next3, equals(DateTime(2026, 4, 1)));
    });
  });
}
