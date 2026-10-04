import 'package:billzo/core/money/money.dart';

/// Single line item in a Trial Balance representing an account's debit and credit postings.
class TrialBalanceEntry {
  final String accountId;
  final String accountCode;
  final String accountName;
  final String accountType; // ASSET, LIABILITY, EQUITY, INCOME, EXPENSE
  final int totalDebitPaise;
  final int totalCreditPaise;
  final int netDebitPaise;
  final int netCreditPaise;

  const TrialBalanceEntry({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.totalDebitPaise,
    required this.totalCreditPaise,
    required this.netDebitPaise,
    required this.netCreditPaise,
  });

  Money get totalDebit => Money.fromPaise(totalDebitPaise);
  Money get totalCredit => Money.fromPaise(totalCreditPaise);
  Money get netDebit => Money.fromPaise(netDebitPaise);
  Money get netCredit => Money.fromPaise(netCreditPaise);
}

/// Trial Balance report summarizing all general ledger activity and proving debit/credit equality.
class TrialBalanceReport {
  final String businessId;
  final DateTime? asOfDate;
  final DateTime? startDate;
  final List<TrialBalanceEntry> entries;
  final int totalDebitsPaise;
  final int totalCreditsPaise;
  final DateTime generatedAt;

  const TrialBalanceReport({
    required this.businessId,
    this.asOfDate,
    this.startDate,
    required this.entries,
    required this.totalDebitsPaise,
    required this.totalCreditsPaise,
    required this.generatedAt,
  });

  Money get totalDebits => Money.fromPaise(totalDebitsPaise);
  Money get totalCredits => Money.fromPaise(totalCreditsPaise);
  int get differencePaise => (totalDebitsPaise - totalCreditsPaise).abs();
  Money get difference => Money.fromPaise(differencePaise);

  /// Trial Balance equation invariant: Total Debits == Total Credits
  bool get isBalanced => totalDebitsPaise == totalCreditsPaise;
}
