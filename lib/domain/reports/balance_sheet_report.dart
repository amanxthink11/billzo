import 'package:billzo/core/money/money.dart';

/// Single item within a balance sheet section.
class BalanceSheetItem {
  final String accountCode;
  final String accountName;
  final int amountPaise;

  const BalanceSheetItem({
    required this.accountCode,
    required this.accountName,
    required this.amountPaise,
  });

  Money get amount => Money.fromPaise(amountPaise);
}

/// Balance Sheet report derived from general ledger accounts and retained earnings.
class BalanceSheetReport {
  final String businessId;
  final DateTime asOfDate;
  final List<BalanceSheetItem> assetItems;
  final int totalAssetsPaise;
  final List<BalanceSheetItem> liabilityItems;
  final int totalLiabilitiesPaise;
  final List<BalanceSheetItem> equityItems;
  final int currentPeriodEarningsPaise;
  final int totalEquityPaise;
  final DateTime generatedAt;

  const BalanceSheetReport({
    required this.businessId,
    required this.asOfDate,
    required this.assetItems,
    required this.totalAssetsPaise,
    required this.liabilityItems,
    required this.totalLiabilitiesPaise,
    required this.equityItems,
    required this.currentPeriodEarningsPaise,
    required this.totalEquityPaise,
    required this.generatedAt,
  });

  Money get totalAssets => Money.fromPaise(totalAssetsPaise);
  Money get totalLiabilities => Money.fromPaise(totalLiabilitiesPaise);
  Money get currentPeriodEarnings => Money.fromPaise(currentPeriodEarningsPaise);
  Money get totalEquity => Money.fromPaise(totalEquityPaise);

  int get equityAccountsTotalPaise =>
      equityItems.fold<int>(0, (sum, item) => sum + item.amountPaise);
  Money get equityAccountsTotal => Money.fromPaise(equityAccountsTotalPaise);

  int get totalLiabilitiesAndEquityPaise => totalLiabilitiesPaise + totalEquityPaise;
  Money get totalLiabilitiesAndEquity => Money.fromPaise(totalLiabilitiesAndEquityPaise);

  /// Imbalance (if any) between Assets and (Liabilities + Equity).
  /// Exposes discrepancies explicitly without artificial balancing.
  int get imbalancePaise => totalAssetsPaise - totalLiabilitiesAndEquityPaise;
  Money get imbalance => Money.fromPaise(imbalancePaise.abs());

  bool get isBalanced => imbalancePaise == 0;
}
