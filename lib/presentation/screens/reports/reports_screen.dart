import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/application/reports/csv_export_helper.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/reports/gst_summary_report.dart';
import 'package:billzo/domain/reports/gstr1_report.dart';
import 'package:billzo/domain/reports/stock_valuation_report.dart';
import 'package:billzo/presentation/providers/report_providers.dart';

/// Comprehensive Financial & Statutory Management Reports Hub.
class ReportsScreen extends ConsumerStatefulWidget {
  final Business business;

  const ReportsScreen({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 10, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(reportActiveTabProvider.notifier).state = _tabController.index;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshAllReports() {
    ref.invalidate(trialBalanceReportProvider(widget.business.id));
    ref.invalidate(profitLossReportProvider(widget.business.id));
    ref.invalidate(balanceSheetReportProvider(widget.business.id));
    ref.invalidate(gstSummaryReportProvider(widget.business.id));
    ref.invalidate(accountingIntegrityAuditProvider(widget.business.id));
    ref.invalidate(gstr1ReportProvider(widget.business.id));
    ref.invalidate(receivablesAgingReportProvider(widget.business.id));
    ref.invalidate(payablesAgingReportProvider(widget.business.id));
    ref.invalidate(stockValuationReportProvider(widget.business.id));
  }

  Future<void> _showAuditDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final auditAsync = ref.watch(accountingIntegrityAuditProvider(widget.business.id));
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.fact_check_outlined, color: BillzoColors.primaryBlue),
                SizedBox(width: 8),
                Text('Accounting Integrity Audit'),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: auditAsync.when(
                loading: () => const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Audit execution error: $e', style: const TextStyle(color: BillzoColors.dangerRed)),
                data: (audit) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: audit.isClean ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: audit.isClean ? Colors.green.shade300 : Colors.red.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                audit.isClean ? Icons.check_circle : Icons.warning_amber,
                                color: audit.isClean ? BillzoColors.successGreen : BillzoColors.dangerRed,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  audit.isClean
                                      ? 'Double-entry accounting integrity verified! 100% of journal entries, ledger accounts, cash/bank holdings, receivables, and payables agree.'
                                      : 'Integrity discrepancy detected: ${audit.totalIssuesCount} discrepancy found in accounting records.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: audit.isClean ? Colors.green.shade900 : Colors.red.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _AuditCheckRow('1. Balanced Journal Entries', audit.journalEntriesBalanced),
                        _AuditCheckRow('2. Trial Balance Debits == Credits', audit.trialBalanceBalanced),
                        _AuditCheckRow('3. Cash/Bank Postings Reconciliation', audit.cashBankReconciled),
                        _AuditCheckRow('4. Customer Receivables vs Account 1100', audit.receivablesReconciled),
                        _AuditCheckRow('5. Supplier Payables vs Account 2100', audit.payablesReconciled),
                        _AuditCheckRow('6. Operational Expenses vs Ledger', audit.expensesReconciled),
                        if (audit.issues.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text('Discrepancy Details:', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          ...audit.issues.map((issue) => Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '• [${issue.category}] ${issue.description}',
                                  style: const TextStyle(fontSize: 12, color: BillzoColors.dangerRed),
                                ),
                              )),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePreset = ref.watch(reportDatePresetProvider);
    final effectiveRange = ref.watch(reportEffectiveDateRangeProvider);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Section: Title & Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Financial Reports & Accounting',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: BillzoColors.darkSlate,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Period: ${dateFormat.format(effectiveRange.start)} — ${dateFormat.format(effectiveRange.end)}',
                    style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                  ),
                ],
              ),
              Row(
                children: [
                  // Preset Selector
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: BillzoColors.neutralBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ReportDatePreset>(
                        value: activePreset,
                        items: ReportDatePreset.values.map((p) {
                          return DropdownMenuItem(value: p, child: Text(p.displayName));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref.read(reportDatePresetProvider.notifier).state = val;
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Custom Range Picker if active
                  if (activePreset == ReportDatePreset.custom) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDateRange: effectiveRange,
                        );
                        if (picked != null) {
                          ref.read(reportCustomDateRangeProvider.notifier).state = picked;
                        }
                      },
                      icon: const Icon(Icons.date_range, size: 16),
                      label: Text(
                        '${DateFormat('dd/MM').format(effectiveRange.start)} - ${DateFormat('dd/MM').format(effectiveRange.end)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Audit Button
                  OutlinedButton.icon(
                    onPressed: _showAuditDialog,
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: const Text('Integrity Audit'),
                  ),
                  const SizedBox(width: 8),

                  // Refresh Button
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh Reports',
                    onPressed: _refreshAllReports,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Tab Bar
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: BillzoColors.neutralBorder)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: BillzoColors.primaryBlue,
              unselectedLabelColor: BillzoColors.neutralText,
              indicatorColor: BillzoColors.primaryBlue,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Profit & Loss'),
                Tab(text: 'Balance Sheet'),
                Tab(text: 'Trial Balance'),
                Tab(text: 'GST Summary'),
                Tab(text: 'Expense Breakdown'),
                Tab(text: 'GSTR-1 Portal'),
                Tab(text: 'Receivables Aging'),
                Tab(text: 'Payables Aging'),
                Tab(text: 'Stock Valuation'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Tab Views Content Canvas
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _OverviewTab(business: widget.business),
                _ProfitLossTab(business: widget.business),
                _BalanceSheetTab(business: widget.business),
                _TrialBalanceTab(business: widget.business),
                _GstSummaryTab(business: widget.business),
                _ExpenseSummaryTab(business: widget.business),
                _Gstr1Tab(business: widget.business),
                _ReceivablesAgingTab(business: widget.business),
                _PayablesAgingTab(business: widget.business),
                _StockValuationTab(business: widget.business),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditCheckRow extends StatelessWidget {
  final String title;
  final bool isPassing;

  const _AuditCheckRow(this.title, this.isPassing);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 13)),
          Row(
            children: [
              Icon(
                isPassing ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: isPassing ? BillzoColors.successGreen : BillzoColors.dangerRed,
              ),
              const SizedBox(width: 6),
              Text(
                isPassing ? 'PASSED' : 'FAILED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isPassing ? BillzoColors.successGreen : BillzoColors.dangerRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 1. OVERVIEW TAB
// ==========================================
class _OverviewTab extends ConsumerWidget {
  final Business business;

  const _OverviewTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plAsync = ref.watch(profitLossReportProvider(business.id));
    final gstAsync = ref.watch(gstSummaryReportProvider(business.id));
    final auditAsync = ref.watch(accountingIntegrityAuditProvider(business.id));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Accounting Health Banner
          auditAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const SizedBox.shrink(),
            data: (audit) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: audit.isClean ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: audit.isClean ? Colors.green.shade200 : Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    audit.isClean ? Icons.verified : Icons.warning_amber_rounded,
                    color: audit.isClean ? BillzoColors.successGreen : BillzoColors.dangerRed,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      audit.isClean
                          ? 'Accounting ledger is in perfect equilibrium. Double-entry trial balance, receivables, payables, and cash/bank positions are 100% verified.'
                          : 'Accounting alert: Discrepancy detected in trial balance or subledger reconciliation. Inspect Integrity Audit for details.',
                      style: TextStyle(
                        fontSize: 13,
                        color: audit.isClean ? Colors.green.shade900 : Colors.red.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // P&L Highlights
          plAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error loading P&L overview: $e'),
            data: (pl) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ReportMetricCard(
                        title: 'Sales Revenue',
                        amount: pl.salesRevenue.formatted,
                        subtitle: 'Operating turnover',
                        icon: Icons.trending_up,
                        color: BillzoColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ReportMetricCard(
                        title: 'Cost of Goods Sold',
                        amount: pl.cogs.formatted,
                        subtitle: pl.cogsPaise == 0 ? 'Deferred in Asset (1200)' : 'Direct COGS',
                        icon: Icons.inventory_2_outlined,
                        color: Colors.brown,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ReportMetricCard(
                        title: 'Gross Profit',
                        amount: pl.grossProfit.formatted,
                        subtitle: 'Revenue minus COGS',
                        icon: Icons.monetization_on_outlined,
                        color: pl.grossProfitPaise >= 0 ? BillzoColors.successGreen : BillzoColors.dangerRed,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ReportMetricCard(
                        title: 'Operating Expenses',
                        amount: pl.totalOperatingExpenses.formatted,
                        subtitle: '${pl.expenseBreakdown.length} active categories',
                        icon: Icons.receipt_long_outlined,
                        color: BillzoColors.accentOrange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ReportMetricCard(
                        title: 'Net Profit',
                        amount: pl.netProfit.formatted,
                        subtitle: pl.isProfitable ? 'Net Surplus' : 'Net Loss',
                        icon: pl.isProfitable ? Icons.arrow_upward : Icons.arrow_downward,
                        color: pl.isProfitable ? BillzoColors.successGreen : BillzoColors.dangerRed,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // GST Highlights
          gstAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (gst) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BillzoColors.neutralBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance, color: BillzoColors.darkSlate, size: 20),
                      SizedBox(width: 8),
                      Text('GST Statutory Position', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SubMetric('Output GST (Sales)', gst.totalOutputGst.formatted),
                      ),
                      Expanded(
                        child: _SubMetric('Eligible Purchase ITC', gst.eligiblePurchaseItc.totalTax.formatted),
                      ),
                      Expanded(
                        child: _SubMetric('Eligible Expense ITC', gst.eligibleExpenseItc.totalTax.formatted),
                      ),
                      Expanded(
                        child: _SubMetric('Total Input Tax Credit', gst.totalInputGst.formatted),
                      ),
                      Expanded(
                        child: _SubMetric(
                          gst.isPayable ? 'Net GST Payable' : 'ITC Carried Forward',
                          gst.netGstLiability.formatted,
                          color: gst.isPayable ? BillzoColors.accentOrange : BillzoColors.successGreen,
                          isBold: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. PROFIT & LOSS TAB
// ==========================================
class _ProfitLossTab extends ConsumerWidget {
  final Business business;

  const _ProfitLossTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plAsync = ref.watch(profitLossReportProvider(business.id));

    return plAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading Profit & Loss: $e')),
      data: (pl) {
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BillzoColors.neutralBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: Column(
                    children: [
                      Text(
                        'Statement of Profit & Loss',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Derived deterministically from double-entry general ledger accounts',
                        style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Revenue Section
                _StatementSectionHeader('Operating Revenue'),
                _StatementRow('Sales Revenue (Taxable Turnover)', pl.salesRevenue.formatted),
                if (pl.otherIncomePaise > 0)
                  _StatementRow('Other Income (Round-off gain)', pl.otherIncome.formatted),
                const Divider(height: 12),
                _StatementRow('Total Revenue [A]', pl.totalRevenue.formatted, isBold: true),
                const SizedBox(height: 16),

                // Cost of Goods Sold Section
                _StatementSectionHeader('Cost of Goods Sold (COGS)'),
                _StatementRow('Direct Cost of Goods Sold', pl.cogs.formatted),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4, bottom: 8),
                  child: Text(
                    'Note: ${pl.cogsNote}',
                    style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: BillzoColors.neutralText),
                  ),
                ),
                const Divider(height: 12),
                _StatementRow('Total Cost of Goods Sold [B]', pl.cogs.formatted, isBold: true),
                const SizedBox(height: 16),

                // Gross Profit Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: BillzoColors.neutralLight,
                  child: _StatementRow(
                    'Gross Profit [A - B]',
                    pl.grossProfit.formatted,
                    isBold: true,
                    textColor: pl.grossProfitPaise >= 0 ? BillzoColors.successGreen : BillzoColors.dangerRed,
                  ),
                ),
                const SizedBox(height: 20),

                // Operating Expenses Section
                _StatementSectionHeader('Operating & Indirect Expenses'),
                if (pl.expenseBreakdown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Text('No operating expenses posted in this period.', style: TextStyle(color: BillzoColors.neutralText)),
                  )
                else
                  ...pl.expenseBreakdown.map((exp) {
                    return _StatementRow(
                      '${exp.categoryName} (${exp.accountCode})',
                      exp.amount.formatted,
                    );
                  }),
                if (pl.roundOffExpensePaise > 0)
                  _StatementRow('Round-off Expense / Concession (5200)', pl.roundOffExpense.formatted),
                const Divider(height: 12),
                _StatementRow('Total Operating Expenses [C]', pl.totalOperatingExpenses.formatted, isBold: true),
                const SizedBox(height: 20),

                // Net Profit Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: pl.isProfitable ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: pl.isProfitable ? Colors.green.shade300 : Colors.red.shade300,
                    ),
                  ),
                  child: _StatementRow(
                    pl.isProfitable ? 'NET PROFIT FOR THE PERIOD [Gross Profit - C]' : 'NET LOSS FOR THE PERIOD [Gross Profit - C]',
                    pl.netProfit.formatted,
                    isBold: true,
                    fontSize: 16,
                    textColor: pl.isProfitable ? Colors.green.shade900 : Colors.red.shade900,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// 3. BALANCE SHEET TAB
// ==========================================
class _BalanceSheetTab extends ConsumerWidget {
  final Business business;

  const _BalanceSheetTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bsAsync = ref.watch(balanceSheetReportProvider(business.id));

    return bsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading Balance Sheet: $e')),
      data: (bs) {
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BillzoColors.neutralBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Statement of Financial Position (Balance Sheet)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'As of ${DateFormat('dd MMMM yyyy').format(bs.asOfDate)}',
                        style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Equation Status Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bs.isBalanced ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: bs.isBalanced ? Colors.green.shade300 : Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        bs.isBalanced ? Icons.check_circle : Icons.error,
                        color: bs.isBalanced ? BillzoColors.successGreen : BillzoColors.dangerRed,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          bs.isBalanced
                              ? 'Fundamental Accounting Equation Balances: Total Assets (${bs.totalAssets.formatted}) == Total Liabilities & Equity (${bs.totalLiabilitiesAndEquity.formatted})'
                              : 'IMBALANCE DETECTED: Assets (${bs.totalAssets.formatted}) differ from Liabilities & Equity (${bs.totalLiabilitiesAndEquity.formatted}) by ${bs.imbalance.formatted}. Discrepancy is explicitly exposed.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: bs.isBalanced ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Two-column layout for Assets and Liabilities+Equity
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Assets
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: BillzoColors.neutralLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: BillzoColors.neutralBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('ASSETS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const Divider(height: 16),
                            if (bs.assetItems.isEmpty)
                              const Text('No asset accounts with balances.', style: TextStyle(color: BillzoColors.neutralText))
                            else
                              ...bs.assetItems.map((item) {
                                return _StatementRow('${item.accountName} (${item.accountCode})', item.amount.formatted);
                              }),
                            const Divider(height: 24),
                            _StatementRow('TOTAL ASSETS', bs.totalAssets.formatted, isBold: true, fontSize: 15),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Right Column: Liabilities & Equity
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: BillzoColors.neutralLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: BillzoColors.neutralBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('LIABILITIES', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const Divider(height: 16),
                            if (bs.liabilityItems.isEmpty)
                              const Text('No liability accounts with balances.', style: TextStyle(color: BillzoColors.neutralText))
                            else
                              ...bs.liabilityItems.map((item) {
                                return _StatementRow('${item.accountName} (${item.accountCode})', item.amount.formatted);
                              }),
                            const SizedBox(height: 8),
                            _StatementRow('Total Liabilities', bs.totalLiabilities.formatted, isBold: true),
                            const SizedBox(height: 20),

                            const Text('EQUITY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const Divider(height: 16),
                            if (bs.equityItems.isEmpty)
                              _StatementRow("Owner's Capital (3000)", '₹0.00')
                            else
                              ...bs.equityItems.map((item) {
                                return _StatementRow('${item.accountName} (${item.accountCode})', item.amount.formatted);
                              }),
                            _StatementRow('Current Period Net Earnings', bs.currentPeriodEarnings.formatted),
                            const SizedBox(height: 8),
                            _StatementRow('Total Equity', bs.totalEquity.formatted, isBold: true),
                            const Divider(height: 24),
                            _StatementRow(
                              'TOTAL LIABILITIES & EQUITY',
                              bs.totalLiabilitiesAndEquity.formatted,
                              isBold: true,
                              fontSize: 15,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// 4. TRIAL BALANCE TAB
// ==========================================
class _TrialBalanceTab extends ConsumerWidget {
  final Business business;

  const _TrialBalanceTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tbAsync = ref.watch(trialBalanceReportProvider(business.id));

    return tbAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading Trial Balance: $e')),
      data: (tb) {
        return SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BillzoColors.neutralBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'General Ledger Trial Balance',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: tb.isBalanced ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tb.isBalanced ? Colors.green : Colors.red),
                        ),
                        child: Text(
                          tb.isBalanced ? 'BALANCED' : 'IMBALANCED',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tb.isBalanced ? BillzoColors.successGreen : BillzoColors.dangerRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(BillzoColors.neutralLight),
                    columns: const [
                      DataColumn(label: Text('Code', style: TextStyle(fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('Account Name', style: TextStyle(fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('Total Debit', style: TextStyle(fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('Total Credit', style: TextStyle(fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('Net Balance', style: TextStyle(fontWeight: FontWeight.w700))),
                    ],
                    rows: [
                      ...tb.entries.map((e) {
                        final netStr = e.netDebitPaise > 0
                            ? '${e.netDebit.formatted} Dr'
                            : e.netCreditPaise > 0
                                ? '${e.netCredit.formatted} Cr'
                                : '—';

                        return DataRow(
                          cells: [
                            DataCell(Text(e.accountCode, style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(e.accountName)),
                            DataCell(Text(e.accountType)),
                            DataCell(Text(e.totalDebit.formatted)),
                            DataCell(Text(e.totalCredit.formatted)),
                            DataCell(Text(netStr, style: const TextStyle(fontWeight: FontWeight.w600))),
                          ],
                        );
                      }),
                      // Totals Row
                      DataRow(
                        color: WidgetStateProperty.all(BillzoColors.neutralLight),
                        cells: [
                          const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800))),
                          const DataCell(Text('All Ledger Postings', style: TextStyle(fontWeight: FontWeight.w800))),
                          const DataCell(Text('')),
                          DataCell(Text(tb.totalDebits.formatted, style: const TextStyle(fontWeight: FontWeight.w800))),
                          DataCell(Text(tb.totalCredits.formatted, style: const TextStyle(fontWeight: FontWeight.w800))),
                          DataCell(
                            Text(
                              tb.isBalanced ? '₹0.00 (Balanced)' : 'Diff: ${tb.difference.formatted}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: tb.isBalanced ? BillzoColors.successGreen : BillzoColors.dangerRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// 5. GST SUMMARY TAB
// ==========================================
class _GstSummaryTab extends ConsumerWidget {
  final Business business;

  const _GstSummaryTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gstAsync = ref.watch(gstSummaryReportProvider(business.id));

    return gstAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading GST Summary: $e')),
      data: (gst) {
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BillzoColors.neutralBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        GstSummaryReport.reportTitle,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        GstSummaryReport.disclaimer,
                        style: TextStyle(fontSize: 12, color: BillzoColors.neutralText, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 1. Outward Tax
                _StatementSectionHeader('1. OUTWARD SUPPLY TAX (Sales Invoices)'),
                _GstTable(bucket: gst.outwardSupply),
                const SizedBox(height: 20),

                // 2. Input Tax - Purchases
                _StatementSectionHeader('2. INPUT TAX CREDIT — PURCHASES (Eligible Supplier Invoices)'),
                _GstTable(bucket: gst.eligiblePurchaseItc),
                if (gst.ineligiblePurchaseItcPaise > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Ineligible / Blocked Purchase ITC: ${Money.fromPaise(gst.ineligiblePurchaseItcPaise).formatted}',
                      style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                    ),
                  ),
                const SizedBox(height: 20),

                // 3. Input Tax - Expenses
                _StatementSectionHeader('3. INPUT TAX CREDIT — EXPENSES (Operational Expenses)'),
                _GstTable(bucket: gst.eligibleExpenseItc),
                const SizedBox(height: 24),

                // 4. Net Tax Reconciliation Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: BillzoColors.neutralLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: BillzoColors.neutralBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('NET STATUTORY RECONCILIATION SUMMARY', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      _StatementRow('Total Output GST (A)', gst.totalOutputGst.formatted),
                      _StatementRow('Total Eligible Input Tax Credit (B)', gst.totalInputGst.formatted),
                      const Divider(height: 16),
                      _StatementRow(
                        gst.isPayable ? 'Net GST Payable to Government [A - B]' : 'Net Excess Input Tax Credit (Carried Forward) [B - A]',
                        gst.netGstLiability.formatted,
                        isBold: true,
                        fontSize: 16,
                        textColor: gst.isPayable ? BillzoColors.accentOrange : BillzoColors.successGreen,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GstTable extends StatelessWidget {
  final GstTaxBucket bucket;

  const _GstTable({required this.bucket});

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(color: BillzoColors.neutralBorder),
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(2),
        4: FlexColumnWidth(2),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: BillzoColors.neutralLight),
          children: const [
            _TableCell('Taxable Value', isHeader: true),
            _TableCell('CGST', isHeader: true),
            _TableCell('SGST', isHeader: true),
            _TableCell('IGST', isHeader: true),
            _TableCell('Total Tax', isHeader: true),
          ],
        ),
        TableRow(
          children: [
            _TableCell(bucket.taxableAmount.formatted),
            _TableCell(bucket.cgst.formatted),
            _TableCell(bucket.sgst.formatted),
            _TableCell(bucket.igst.formatted),
            _TableCell(bucket.totalTax.formatted, isBold: true),
          ],
        ),
      ],
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final bool isBold;

  const _TableCell(this.text, {this.isHeader = false, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isHeader || isBold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

// ==========================================
// 6. EXPENSE SUMMARY TAB
// ==========================================
class _ExpenseSummaryTab extends ConsumerWidget {
  final Business business;

  const _ExpenseSummaryTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plAsync = ref.watch(profitLossReportProvider(business.id));

    return plAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading Expense Summary: $e')),
      data: (pl) {
        final totalExp = pl.totalOperatingExpensesPaise;

        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BillzoColors.neutralBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Expense Category Distribution',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total Operating Expenses: ${pl.totalOperatingExpenses.formatted}',
                  style: const TextStyle(fontSize: 14, color: BillzoColors.neutralText),
                ),
                const SizedBox(height: 20),

                if (pl.expenseBreakdown.isEmpty)
                  const Text('No expenses recorded for this period.')
                else
                  ...pl.expenseBreakdown.map((item) {
                    final percentage = totalExp > 0 ? (item.amountPaise * 100 / totalExp) : 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(item.categoryName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${item.amount.formatted} (${percentage.toStringAsFixed(1)}%)'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: totalExp > 0 ? item.amountPaise / totalExp : 0,
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade200,
                              color: BillzoColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Common reporting widgets
class _ReportMetricCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _ReportMetricCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BillzoColors.neutralBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _SubMetric extends StatelessWidget {
  final String label;
  final String amount;
  final Color? color;
  final bool isBold;

  const _SubMetric(this.label, this.amount, {this.color, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
        const SizedBox(height: 4),
        Text(
          amount,
          style: TextStyle(
            fontSize: isBold ? 15 : 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            color: color ?? BillzoColors.darkSlate,
          ),
        ),
      ],
    );
  }
}

class _StatementSectionHeader extends StatelessWidget {
  final String title;

  const _StatementSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: BillzoColors.darkSlate,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _StatementRow extends StatelessWidget {
  final String label;
  final String amount;
  final bool isBold;
  final double fontSize;
  final Color? textColor;

  const _StatementRow(
    this.label,
    this.amount, {
    this.isBold = false,
    this.fontSize = 13,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: textColor ?? (isBold ? BillzoColors.darkSlate : BillzoColors.neutralText),
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: textColor ?? BillzoColors.darkSlate,
            ),
          ),
        ],
      ),
    );
  }
}

void _showCsvExportModal(BuildContext context, String title, String csvContent) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Official RFC 4180 CSV export ready for import or external spreadsheet processing:',
              style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: BillzoColors.neutralBorder),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    csvContent,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: csvContent));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('CSV copied to clipboard!'),
                backgroundColor: BillzoColors.successGreen,
              ),
            );
            Navigator.of(ctx).pop();
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy to Clipboard'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: BillzoColors.primaryBlue,
            foregroundColor: Colors.white,
          ),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

// ==========================================
// 7. GSTR-1 STATUTORY PORTAL TAB
// ==========================================
class _Gstr1Tab extends ConsumerStatefulWidget {
  final Business business;

  const _Gstr1Tab({required this.business});

  @override
  ConsumerState<_Gstr1Tab> createState() => _Gstr1TabState();
}

class _Gstr1TabState extends ConsumerState<_Gstr1Tab> {
  int _subTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final gstr1Async = ref.watch(gstr1ReportProvider(widget.business.id));
    final dateFormat = DateFormat('dd-MM-yyyy');

    return gstr1Async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading GSTR-1: $e')),
      data: (gstr1) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary cards
              Row(
                children: [
                  _SummaryMetricCard(
                    title: 'Grand Total Taxable',
                    value: gstr1.grandTotalTaxable.formatted,
                    icon: Icons.receipt_long,
                    color: BillzoColors.primaryBlue,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: 'Total Tax Liability',
                    value: gstr1.grandTotalTax.formatted,
                    icon: Icons.account_balance,
                    color: BillzoColors.accentOrange,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: 'B2B Invoices (Table 4)',
                    value: '${gstr1.b2bInvoices.length}',
                    icon: Icons.business,
                    color: BillzoColors.successGreen,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: 'HSN Items (Table 12)',
                    value: '${gstr1.hsnSummary.length}',
                    icon: Icons.list_alt,
                    color: BillzoColors.darkSlate,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sub-table Switcher & CSV Export CTA
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Table 4: B2B')),
                      ButtonSegment(value: 1, label: Text('Table 5: B2CL')),
                      ButtonSegment(value: 2, label: Text('Table 7: B2CS')),
                      ButtonSegment(value: 3, label: Text('Table 12: HSN')),
                    ],
                    selected: {_subTabIndex},
                    onSelectionChanged: (set) {
                      setState(() => _subTabIndex = set.first);
                    },
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      String csv = '';
                      String title = '';
                      switch (_subTabIndex) {
                        case 0:
                          csv = CsvExportHelper.exportGstr1B2b(gstr1.b2bInvoices);
                          title = 'GSTR-1 Table 4 (B2B) CSV';
                          break;
                        case 1:
                          csv = CsvExportHelper.exportGstr1B2cl(gstr1.b2clInvoices);
                          title = 'GSTR-1 Table 5 (B2CL) CSV';
                          break;
                        case 2:
                          csv = CsvExportHelper.exportGstr1B2cs(gstr1.b2csItems);
                          title = 'GSTR-1 Table 7 (B2CS) CSV';
                          break;
                        case 3:
                          csv = CsvExportHelper.exportGstr1Hsn(gstr1.hsnSummary);
                          title = 'GSTR-1 Table 12 (HSN Summary) CSV';
                          break;
                      }
                      _showCsvExportModal(context, title, csv);
                    },
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Export Portal CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Active Table Content
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BillzoColors.neutralBorder),
                ),
                child: _buildSubTableContent(gstr1, dateFormat),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubTableContent(Gstr1Report gstr1, DateFormat dateFormat) {
    switch (_subTabIndex) {
      case 0:
        if (gstr1.b2bInvoices.isEmpty) {
          return const _EmptyReportTable(message: 'No B2B invoices found in this period.');
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('GSTIN of Recipient')),
              DataColumn(label: Text('Receiver Name')),
              DataColumn(label: Text('Invoice No.')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Value (₹)')),
              DataColumn(label: Text('POS')),
              DataColumn(label: Text('Rate %')),
              DataColumn(label: Text('Taxable (₹)')),
              DataColumn(label: Text('CGST (₹)')),
              DataColumn(label: Text('SGST (₹)')),
              DataColumn(label: Text('IGST (₹)')),
            ],
            rows: gstr1.b2bInvoices.map((inv) {
              return DataRow(cells: [
                DataCell(Text(inv.receiverGstin)),
                DataCell(Text(inv.receiverName)),
                DataCell(Text(inv.invoiceNumber)),
                DataCell(Text(dateFormat.format(inv.invoiceDate))),
                DataCell(Text(inv.invoiceValue.formatted)),
                DataCell(Text(inv.placeOfSupply)),
                DataCell(Text('${inv.ratePercent.toStringAsFixed(1)}%')),
                DataCell(Text(inv.taxableValue.formatted)),
                DataCell(Text(inv.cgst.formatted)),
                DataCell(Text(inv.sgst.formatted)),
                DataCell(Text(inv.igst.formatted)),
              ]);
            }).toList(),
          ),
        );

      case 1:
        if (gstr1.b2clInvoices.isEmpty) {
          return const _EmptyReportTable(
              message: 'No large inter-state B2C supplies (> ₹2,50,000) found in this period.');
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Invoice No.')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Value (₹)')),
              DataColumn(label: Text('POS')),
              DataColumn(label: Text('Rate %')),
              DataColumn(label: Text('Taxable (₹)')),
              DataColumn(label: Text('IGST (₹)')),
            ],
            rows: gstr1.b2clInvoices.map((inv) {
              return DataRow(cells: [
                DataCell(Text(inv.invoiceNumber)),
                DataCell(Text(dateFormat.format(inv.invoiceDate))),
                DataCell(Text(inv.invoiceValue.formatted)),
                DataCell(Text(inv.placeOfSupply)),
                DataCell(Text('${inv.ratePercent.toStringAsFixed(1)}%')),
                DataCell(Text(inv.taxableValue.formatted)),
                DataCell(Text(inv.igst.formatted)),
              ]);
            }).toList(),
          ),
        );

      case 2:
        if (gstr1.b2csItems.isEmpty) {
          return const _EmptyReportTable(message: 'No small B2C supplies found in this period.');
        }
        return DataTable(
          columns: const [
            DataColumn(label: Text('Place of Supply (POS)')),
            DataColumn(label: Text('GST Rate %')),
            DataColumn(label: Text('Taxable Value (₹)')),
            DataColumn(label: Text('CGST (₹)')),
            DataColumn(label: Text('SGST (₹)')),
            DataColumn(label: Text('IGST (₹)')),
          ],
          rows: gstr1.b2csItems.map((item) {
            return DataRow(cells: [
              DataCell(Text(item.placeOfSupply)),
              DataCell(Text('${item.ratePercent.toStringAsFixed(1)}%')),
              DataCell(Text(item.taxableValue.formatted)),
              DataCell(Text(item.cgst.formatted)),
              DataCell(Text(item.sgst.formatted)),
              DataCell(Text(item.igst.formatted)),
            ]);
          }).toList(),
        );

      case 3:
      default:
        if (gstr1.hsnSummary.isEmpty) {
          return const _EmptyReportTable(message: 'No HSN records found for outward supplies.');
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('HSN/SAC')),
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('UQC')),
              DataColumn(label: Text('Total Qty')),
              DataColumn(label: Text('Total Value (₹)')),
              DataColumn(label: Text('Taxable Value (₹)')),
              DataColumn(label: Text('CGST (₹)')),
              DataColumn(label: Text('SGST (₹)')),
              DataColumn(label: Text('IGST (₹)')),
            ],
            rows: gstr1.hsnSummary.map((item) {
              return DataRow(cells: [
                DataCell(Text(item.hsnSac)),
                DataCell(Text(item.description)),
                DataCell(Text(item.uqc)),
                DataCell(Text('${item.totalQuantity}')),
                DataCell(Text(item.totalValue.formatted)),
                DataCell(Text(item.taxableValue.formatted)),
                DataCell(Text(item.cgst.formatted)),
                DataCell(Text(item.sgst.formatted)),
                DataCell(Text(item.igst.formatted)),
              ]);
            }).toList(),
          ),
        );
    }
  }
}

// ==========================================
// 8. RECEIVABLES AGING TAB
// ==========================================
class _ReceivablesAgingTab extends ConsumerWidget {
  final Business business;

  const _ReceivablesAgingTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arAsync = ref.watch(receivablesAgingReportProvider(business.id));

    return arAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading Receivables Aging: $e')),
      data: (report) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary cards
              Row(
                children: [
                  _SummaryMetricCard(
                    title: 'Total Outstanding',
                    value: report.totalOutstanding.formatted,
                    icon: Icons.pending_actions,
                    color: BillzoColors.dangerRed,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: 'Current (Not Due)',
                    value: report.totalCurrent.formatted,
                    icon: Icons.check_circle_outline,
                    color: BillzoColors.successGreen,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: '1-30 Days Overdue',
                    value: report.totalDays1To30.formatted,
                    icon: Icons.schedule,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: '90+ Days Overdue',
                    value: report.totalDays90Plus.formatted,
                    icon: Icons.warning_amber_rounded,
                    color: BillzoColors.dangerRed,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Customer Aging Breakdown (${report.items.length} Customers)',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      final csv = CsvExportHelper.exportReceivablesAging(report);
                      _showCsvExportModal(context, 'Receivables Aging CSV', csv);
                    },
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Export CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BillzoColors.neutralBorder),
                ),
                child: report.items.isEmpty
                    ? const _EmptyReportTable(message: 'No outstanding receivables found.')
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Customer Name')),
                            DataColumn(label: Text('Phone')),
                            DataColumn(label: Text('Total Outstanding')),
                            DataColumn(label: Text('Current')),
                            DataColumn(label: Text('1-30 Days')),
                            DataColumn(label: Text('31-60 Days')),
                            DataColumn(label: Text('61-90 Days')),
                            DataColumn(label: Text('90+ Days')),
                          ],
                          rows: report.items.map((item) {
                            return DataRow(cells: [
                              DataCell(Text(item.partyName, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(item.phone ?? '-')),
                              DataCell(Text(item.totalOutstanding.formatted, style: const TextStyle(fontWeight: FontWeight.w700))),
                              DataCell(Text(item.current.formatted)),
                              DataCell(Text(item.days1To30.formatted)),
                              DataCell(Text(item.days31To60.formatted)),
                              DataCell(Text(item.days61To90.formatted)),
                              DataCell(Text(
                                item.days90Plus.formatted,
                                style: TextStyle(
                                  fontWeight: item.days90PlusPaise > 0 ? FontWeight.w700 : FontWeight.normal,
                                  color: item.days90PlusPaise > 0 ? BillzoColors.dangerRed : null,
                                ),
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// 9. PAYABLES AGING TAB
// ==========================================
class _PayablesAgingTab extends ConsumerWidget {
  final Business business;

  const _PayablesAgingTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apAsync = ref.watch(payablesAgingReportProvider(business.id));

    return apAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading Payables Aging: $e')),
      data: (report) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary cards
              Row(
                children: [
                  _SummaryMetricCard(
                    title: 'Total Outstanding',
                    value: report.totalOutstanding.formatted,
                    icon: Icons.account_balance_wallet_outlined,
                    color: BillzoColors.accentOrange,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: 'Current (Not Due)',
                    value: report.totalCurrent.formatted,
                    icon: Icons.check_circle_outline,
                    color: BillzoColors.successGreen,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: '1-30 Days Overdue',
                    value: report.totalDays1To30.formatted,
                    icon: Icons.schedule,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: '90+ Days Overdue',
                    value: report.totalDays90Plus.formatted,
                    icon: Icons.warning_amber_rounded,
                    color: BillzoColors.dangerRed,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Supplier Aging Breakdown (${report.items.length} Suppliers)',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      final csv = CsvExportHelper.exportPayablesAging(report);
                      _showCsvExportModal(context, 'Payables Aging CSV', csv);
                    },
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Export CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BillzoColors.neutralBorder),
                ),
                child: report.items.isEmpty
                    ? const _EmptyReportTable(message: 'No outstanding payables found.')
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Supplier Name')),
                            DataColumn(label: Text('Phone')),
                            DataColumn(label: Text('Total Outstanding')),
                            DataColumn(label: Text('Current')),
                            DataColumn(label: Text('1-30 Days')),
                            DataColumn(label: Text('31-60 Days')),
                            DataColumn(label: Text('61-90 Days')),
                            DataColumn(label: Text('90+ Days')),
                          ],
                          rows: report.items.map((item) {
                            return DataRow(cells: [
                              DataCell(Text(item.partyName, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(item.phone ?? '-')),
                              DataCell(Text(item.totalOutstanding.formatted, style: const TextStyle(fontWeight: FontWeight.w700))),
                              DataCell(Text(item.current.formatted)),
                              DataCell(Text(item.days1To30.formatted)),
                              DataCell(Text(item.days31To60.formatted)),
                              DataCell(Text(item.days61To90.formatted)),
                              DataCell(Text(
                                item.days90Plus.formatted,
                                style: TextStyle(
                                  fontWeight: item.days90PlusPaise > 0 ? FontWeight.w700 : FontWeight.normal,
                                  color: item.days90PlusPaise > 0 ? BillzoColors.dangerRed : null,
                                ),
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// 10. STOCK VALUATION TAB
// ==========================================
class _StockValuationTab extends ConsumerWidget {
  final Business business;

  const _StockValuationTab({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(stockValuationReportProvider(business.id));

    return stockAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading Stock Valuation: $e')),
      data: (report) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary cards
              Row(
                children: [
                  _SummaryMetricCard(
                    title: 'Total Cost Valuation',
                    value: report.totalCostValuation.formatted,
                    icon: Icons.inventory_2,
                    color: BillzoColors.primaryBlue,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: 'Total Retail Valuation',
                    value: report.totalRetailValuation.formatted,
                    icon: Icons.storefront,
                    color: BillzoColors.successGreen,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: 'Stock Quantity on Hand',
                    value: '${report.totalStockQuantity}',
                    icon: Icons.layers,
                    color: BillzoColors.darkSlate,
                  ),
                  const SizedBox(width: 12),
                  _SummaryMetricCard(
                    title: 'Low Stock Items',
                    value: '${report.lowStockItemsCount}',
                    icon: Icons.warning_amber_rounded,
                    color: report.lowStockItemsCount > 0 ? BillzoColors.dangerRed : BillzoColors.successGreen,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Inventory Stock Ledger (${report.totalItemsCount} Products)',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      final csv = CsvExportHelper.exportStockValuation(report);
                      _showCsvExportModal(context, 'Stock Valuation CSV', csv);
                    },
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Export CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BillzoColors.neutralBorder),
                ),
                child: report.items.isEmpty
                    ? const _EmptyReportTable(message: 'No products registered in inventory.')
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Product Name')),
                            DataColumn(label: Text('SKU')),
                            DataColumn(label: Text('Category')),
                            DataColumn(label: Text('Current Stock')),
                            DataColumn(label: Text('Cost Price (₹)')),
                            DataColumn(label: Text('Selling Price (₹)')),
                            DataColumn(label: Text('Cost Valuation (₹)')),
                            DataColumn(label: Text('Retail Valuation (₹)')),
                            DataColumn(label: Text('Status')),
                          ],
                          rows: report.items.map((item) {
                            return DataRow(cells: [
                              DataCell(Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(item.sku ?? '-')),
                              DataCell(Text(item.categoryName ?? 'Uncategorized')),
                              DataCell(Text('${item.currentStock} ${item.unitCode}')),
                              DataCell(Text(item.purchasePrice.formatted)),
                              DataCell(Text(item.sellingPrice.formatted)),
                              DataCell(Text(item.costValuation.formatted, style: const TextStyle(fontWeight: FontWeight.w700))),
                              DataCell(Text(item.retailValuation.formatted)),
                              DataCell(_StockStatusBadge(item: item)),
                            ]);
                          }).toList(),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyReportTable extends StatelessWidget {
  final String message;

  const _EmptyReportTable({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: BillzoColors.neutralText, fontSize: 14),
        ),
      ),
    );
  }
}

class _StockStatusBadge extends StatelessWidget {
  final StockValuationItem item;

  const _StockStatusBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.isOutOfStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Out of Stock',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillzoColors.dangerRed),
        ),
      );
    }

    if (item.isLowStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Low Stock',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillzoColors.warningOrange),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Normal',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillzoColors.successGreen),
      ),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BillzoColors.neutralBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: BillzoColors.darkSlate,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


