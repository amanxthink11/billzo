import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/application/reports/accounting_integrity_service.dart';
import 'package:billzo/domain/reports/aging_analysis_report.dart';
import 'package:billzo/domain/reports/balance_sheet_report.dart';
import 'package:billzo/domain/reports/gst_summary_report.dart';
import 'package:billzo/domain/reports/gstr1_report.dart';
import 'package:billzo/domain/reports/profit_loss_report.dart';
import 'package:billzo/domain/reports/stock_valuation_report.dart';
import 'package:billzo/domain/reports/trial_balance_report.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Predefined standard date ranges for reporting periods.
enum ReportDatePreset {
  thisMonth,
  thisQuarter,
  thisFinancialYear,
  today,
  custom;

  String get displayName {
    switch (this) {
      case ReportDatePreset.thisMonth:
        return 'This Month';
      case ReportDatePreset.thisQuarter:
        return 'This Quarter';
      case ReportDatePreset.thisFinancialYear:
        return 'This FY';
      case ReportDatePreset.today:
        return 'Today';
      case ReportDatePreset.custom:
        return 'Custom';
    }
  }

  DateTimeRange calculateRange() {
    final now = DateTime.now();
    switch (this) {
      case ReportDatePreset.today:
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);

      case ReportDatePreset.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);

      case ReportDatePreset.thisQuarter:
        final quarter = ((now.month - 1) ~/ 3) + 1;
        final startMonth = (quarter - 1) * 3 + 1;
        final start = DateTime(now.year, startMonth, 1);
        final end = DateTime(now.year, startMonth + 3, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);

      case ReportDatePreset.thisFinancialYear:
        // Indian FY: April 1 to March 31
        final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
        final start = DateTime(fyStartYear, 4, 1);
        final end = DateTime(fyStartYear + 1, 3, 31, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);

      case ReportDatePreset.custom:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
    }
  }
}

/// Currently active reporting date preset notifier.
class ReportDatePresetNotifier extends Notifier<ReportDatePreset> {
  @override
  ReportDatePreset build() => ReportDatePreset.thisMonth;

  @override
  set state(ReportDatePreset value) => super.state = value;
}

final reportDatePresetProvider =
    NotifierProvider<ReportDatePresetNotifier, ReportDatePreset>(ReportDatePresetNotifier.new);

/// Custom date range notifier when preset is custom.
class ReportCustomDateRangeNotifier extends Notifier<DateTimeRange> {
  @override
  DateTimeRange build() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
    );
  }

  @override
  set state(DateTimeRange value) => super.state = value;
}

final reportCustomDateRangeProvider =
    NotifierProvider<ReportCustomDateRangeNotifier, DateTimeRange>(ReportCustomDateRangeNotifier.new);

/// Resolved effective date range based on active preset or custom selection.
final reportEffectiveDateRangeProvider = Provider<DateTimeRange>((ref) {
  final preset = ref.watch(reportDatePresetProvider);
  if (preset == ReportDatePreset.custom) {
    return ref.watch(reportCustomDateRangeProvider);
  }
  return preset.calculateRange();
});

/// Active sub-tab index in Reports Hub.
class ReportActiveTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  @override
  set state(int value) => super.state = value;
}

final reportActiveTabProvider =
    NotifierProvider<ReportActiveTabNotifier, int>(ReportActiveTabNotifier.new);

/// Provider for loading Trial Balance Report.
final trialBalanceReportProvider = FutureProvider.family<TrialBalanceReport, String>((ref, businessId) async {
  final service = ref.watch(reportServiceProvider);
  final range = ref.watch(reportEffectiveDateRangeProvider);
  return service.getTrialBalance(
    businessId,
    startDate: range.start,
    asOfDate: range.end,
  );
});

/// Provider for loading Profit & Loss Report.
final profitLossReportProvider = FutureProvider.family<ProfitLossReport, String>((ref, businessId) async {
  final service = ref.watch(reportServiceProvider);
  final range = ref.watch(reportEffectiveDateRangeProvider);
  return service.getProfitLoss(
    businessId,
    startDate: range.start,
    endDate: range.end,
    includePreviousPeriod: true,
  );
});

/// Provider for loading Balance Sheet Report.
final balanceSheetReportProvider = FutureProvider.family<BalanceSheetReport, String>((ref, businessId) async {
  final service = ref.watch(reportServiceProvider);
  final range = ref.watch(reportEffectiveDateRangeProvider);
  return service.getBalanceSheet(
    businessId,
    asOfDate: range.end,
  );
});

/// Provider for loading GST Summary Report.
final gstSummaryReportProvider = FutureProvider.family<GstSummaryReport, String>((ref, businessId) async {
  final service = ref.watch(reportServiceProvider);
  final range = ref.watch(reportEffectiveDateRangeProvider);
  return service.getGstSummary(
    businessId,
    startDate: range.start,
    endDate: range.end,
  );
});

/// Provider for executing Accounting Data Integrity Audit.
final accountingIntegrityAuditProvider =
    FutureProvider.family<AccountingIntegrityReport, String>((ref, businessId) async {
  final service = ref.watch(accountingIntegrityServiceProvider);
  return service.runIntegrityAudit(businessId);
});

/// Provider for loading GSTR-1 Statutory Report.
final gstr1ReportProvider = FutureProvider.family<Gstr1Report, String>((ref, businessId) async {
  final service = ref.watch(reportServiceProvider);
  final range = ref.watch(reportEffectiveDateRangeProvider);
  return service.getGstr1Report(
    businessId,
    startDate: range.start,
    endDate: range.end,
  );
});

/// Provider for loading Accounts Receivable Aging Analysis.
final receivablesAgingReportProvider =
    FutureProvider.family<ReceivablesAgingReport, String>((ref, businessId) async {
  final service = ref.watch(reportServiceProvider);
  final range = ref.watch(reportEffectiveDateRangeProvider);
  return service.getReceivablesAgingReport(
    businessId,
    asOfDate: range.end,
  );
});

/// Provider for loading Accounts Payable Aging Analysis.
final payablesAgingReportProvider =
    FutureProvider.family<PayablesAgingReport, String>((ref, businessId) async {
  final service = ref.watch(reportServiceProvider);
  final range = ref.watch(reportEffectiveDateRangeProvider);
  return service.getPayablesAgingReport(
    businessId,
    asOfDate: range.end,
  );
});

/// Provider for loading Stock Valuation Report.
final stockValuationReportProvider =
    FutureProvider.family<StockValuationReport, String>((ref, businessId) async {
  final service = ref.watch(reportServiceProvider);
  return service.getStockValuationReport(businessId);
});

