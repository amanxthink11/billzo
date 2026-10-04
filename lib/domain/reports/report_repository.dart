import 'package:billzo/domain/reports/aging_analysis_report.dart';
import 'package:billzo/domain/reports/balance_sheet_report.dart';
import 'package:billzo/domain/reports/gst_summary_report.dart';
import 'package:billzo/domain/reports/gstr1_report.dart';
import 'package:billzo/domain/reports/profit_loss_report.dart';
import 'package:billzo/domain/reports/stock_valuation_report.dart';
import 'package:billzo/domain/reports/trial_balance_report.dart';

/// Abstract contract for generating financial and statutory management reports.
abstract class IReportRepository {
  /// Generates Trial Balance proving debit/credit equality across all ledger accounts.
  Future<TrialBalanceReport> getTrialBalance(
    String businessId, {
    DateTime? asOfDate,
    DateTime? startDate,
  });

  /// Generates Profit & Loss Statement derived from revenue, COGS, and operating expense ledger accounts.
  Future<ProfitLossReport> getProfitLoss(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
    bool includePreviousPeriod = false,
  });

  /// Generates Balance Sheet displaying Assets = Liabilities + Equity without artificial balancing.
  Future<BalanceSheetReport> getBalanceSheet(
    String businessId, {
    required DateTime asOfDate,
  });

  /// Generates offline GST Summary / Management report comparing Outward tax against eligible ITC.
  Future<GstSummaryReport> getGstSummary(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
  });

  /// Generates statutory GSTR-1 portal tables (B2B, B2CL, B2CS, and HSN summary).
  Future<Gstr1Report> getGstr1Report(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
  });

  /// Generates receivables aging report bucketing unpaid customer balances.
  Future<ReceivablesAgingReport> getReceivablesAgingReport(
    String businessId, {
    DateTime? asOfDate,
  });

  /// Generates payables aging report bucketing unpaid supplier balances.
  Future<PayablesAgingReport> getPayablesAgingReport(
    String businessId, {
    DateTime? asOfDate,
  });

  /// Generates stock valuation report detailing on-hand inventory at cost and retail value.
  Future<StockValuationReport> getStockValuationReport(
    String businessId,
  );
}
