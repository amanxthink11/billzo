import 'package:billzo/core/money/money.dart';

/// Single party row in an Accounts Receivable or Accounts Payable aging report.
class PartyAgingItem {
  final String partyId;
  final String partyName;
  final String? phone;
  final String? gstin;
  final int totalOutstandingPaise;
  final int currentPaise;      // Not yet overdue
  final int days1To30Paise;    // 1 - 30 days overdue
  final int days31To60Paise;   // 31 - 60 days overdue
  final int days61To90Paise;   // 61 - 90 days overdue
  final int days90PlusPaise;   // > 90 days overdue

  const PartyAgingItem({
    required this.partyId,
    required this.partyName,
    this.phone,
    this.gstin,
    required this.totalOutstandingPaise,
    required this.currentPaise,
    required this.days1To30Paise,
    required this.days31To60Paise,
    required this.days61To90Paise,
    required this.days90PlusPaise,
  });

  Money get totalOutstanding => Money.fromPaise(totalOutstandingPaise);
  Money get current => Money.fromPaise(currentPaise);
  Money get days1To30 => Money.fromPaise(days1To30Paise);
  Money get days31To60 => Money.fromPaise(days31To60Paise);
  Money get days61To90 => Money.fromPaise(days61To90Paise);
  Money get days90Plus => Money.fromPaise(days90PlusPaise);
}

/// Accounts Receivable (Customer Overdue) Aging Analysis Report.
class ReceivablesAgingReport {
  final String businessId;
  final DateTime asOfDate;
  final List<PartyAgingItem> items;
  final DateTime generatedAt;

  const ReceivablesAgingReport({
    required this.businessId,
    required this.asOfDate,
    required this.items,
    required this.generatedAt,
  });

  int get totalOutstandingPaise =>
      items.fold<int>(0, (sum, i) => sum + i.totalOutstandingPaise);
  int get totalCurrentPaise =>
      items.fold<int>(0, (sum, i) => sum + i.currentPaise);
  int get totalDays1To30Paise =>
      items.fold<int>(0, (sum, i) => sum + i.days1To30Paise);
  int get totalDays31To60Paise =>
      items.fold<int>(0, (sum, i) => sum + i.days31To60Paise);
  int get totalDays61To90Paise =>
      items.fold<int>(0, (sum, i) => sum + i.days61To90Paise);
  int get totalDays90PlusPaise =>
      items.fold<int>(0, (sum, i) => sum + i.days90PlusPaise);

  Money get totalOutstanding => Money.fromPaise(totalOutstandingPaise);
  Money get totalCurrent => Money.fromPaise(totalCurrentPaise);
  Money get totalDays1To30 => Money.fromPaise(totalDays1To30Paise);
  Money get totalDays31To60 => Money.fromPaise(totalDays31To60Paise);
  Money get totalDays61To90 => Money.fromPaise(totalDays61To90Paise);
  Money get totalDays90Plus => Money.fromPaise(totalDays90PlusPaise);
}

/// Accounts Payable (Supplier Overdue) Aging Analysis Report.
class PayablesAgingReport {
  final String businessId;
  final DateTime asOfDate;
  final List<PartyAgingItem> items;
  final DateTime generatedAt;

  const PayablesAgingReport({
    required this.businessId,
    required this.asOfDate,
    required this.items,
    required this.generatedAt,
  });

  int get totalOutstandingPaise =>
      items.fold<int>(0, (sum, i) => sum + i.totalOutstandingPaise);
  int get totalCurrentPaise =>
      items.fold<int>(0, (sum, i) => sum + i.currentPaise);
  int get totalDays1To30Paise =>
      items.fold<int>(0, (sum, i) => sum + i.days1To30Paise);
  int get totalDays31To60Paise =>
      items.fold<int>(0, (sum, i) => sum + i.days31To60Paise);
  int get totalDays61To90Paise =>
      items.fold<int>(0, (sum, i) => sum + i.days61To90Paise);
  int get totalDays90PlusPaise =>
      items.fold<int>(0, (sum, i) => sum + i.days90PlusPaise);

  Money get totalOutstanding => Money.fromPaise(totalOutstandingPaise);
  Money get totalCurrent => Money.fromPaise(totalCurrentPaise);
  Money get totalDays1To30 => Money.fromPaise(totalDays1To30Paise);
  Money get totalDays31To60 => Money.fromPaise(totalDays31To60Paise);
  Money get totalDays61To90 => Money.fromPaise(totalDays61To90Paise);
  Money get totalDays90Plus => Money.fromPaise(totalDays90PlusPaise);
}
