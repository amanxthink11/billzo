import 'package:billzo/domain/reports/aging_analysis_report.dart';
import 'package:billzo/domain/reports/balance_sheet_report.dart';
import 'package:billzo/domain/reports/gst_summary_report.dart';
import 'package:billzo/domain/reports/gstr1_report.dart';
import 'package:billzo/domain/reports/profit_loss_report.dart';
import 'package:billzo/domain/reports/report_repository.dart';
import 'package:billzo/domain/reports/stock_valuation_report.dart';
import 'package:billzo/domain/reports/trial_balance_report.dart';

/// Application service orchestrating financial and statutory management reporting.
class ReportService {
  final IReportRepository _reportRepository;

  ReportService(this._reportRepository);

  Future<TrialBalanceReport> getTrialBalance(
    String businessId, {
    DateTime? asOfDate,
    DateTime? startDate,
  }) =>
      _reportRepository.getTrialBalance(
        businessId,
        asOfDate: asOfDate,
        startDate: startDate,
      );

  Future<ProfitLossReport> getProfitLoss(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
    bool includePreviousPeriod = false,
  }) =>
      _reportRepository.getProfitLoss(
        businessId,
        startDate: startDate,
        endDate: endDate,
        includePreviousPeriod: includePreviousPeriod,
      );

  Future<BalanceSheetReport> getBalanceSheet(
    String businessId, {
    required DateTime asOfDate,
  }) =>
      _reportRepository.getBalanceSheet(businessId, asOfDate: asOfDate);

  Future<GstSummaryReport> getGstSummary(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
  }) =>
      _reportRepository.getGstSummary(
        businessId,
        startDate: startDate,
        endDate: endDate,
      );

  Future<Gstr1Report> getGstr1Report(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
  }) =>
      _reportRepository.getGstr1Report(
        businessId,
        startDate: startDate,
        endDate: endDate,
      );

  Future<ReceivablesAgingReport> getReceivablesAgingReport(
    String businessId, {
    DateTime? asOfDate,
  }) =>
      _reportRepository.getReceivablesAgingReport(
        businessId,
        asOfDate: asOfDate,
      );

  Future<PayablesAgingReport> getPayablesAgingReport(
    String businessId, {
    DateTime? asOfDate,
  }) =>
      _reportRepository.getPayablesAgingReport(
        businessId,
        asOfDate: asOfDate,
      );

  Future<StockValuationReport> getStockValuationReport(
    String businessId,
  ) =>
      _reportRepository.getStockValuationReport(businessId);
}

