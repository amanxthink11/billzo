import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/presentation/providers/expense_providers.dart';
import 'package:billzo/presentation/screens/expenses/expense_builder_dialog.dart';
import 'package:billzo/presentation/screens/expenses/expense_detail_dialog.dart';

/// Screen listing operational and indirect expenses with KPI summary cards,
/// filter toolbar, and responsive table.
class ExpensesScreen extends ConsumerStatefulWidget {
  final Business business;

  const ExpensesScreen({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openNewExpenseDialog() {
    ExpenseBuilderDialog.show(
      context,
      business: widget.business,
    );
  }

  void _openExpenseDetail(Expense expense) {
    ExpenseDetailDialog.show(
      context,
      business: widget.business,
      expenseId: expense.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesListProvider(widget.business.id));
    final summaryAsync = ref.watch(expenseSummaryProvider(widget.business.id));
    final categoriesAsync = ref.watch(expenseCategoriesProvider(widget.business.id));

    final currentSearch = ref.watch(expenseSearchQueryProvider);
    final currentStatus = ref.watch(expenseStatusFilterProvider);
    final currentCategory = ref.watch(expenseCategoryFilterProvider);
    final currentMethod = ref.watch(expensePaymentMethodFilterProvider);
    final currentDateRange = ref.watch(expenseDateRangeFilterProvider);

    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Bar: Header & Primary CTA
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Operational Expenses',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: BillzoColors.darkSlate,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Track overhead, utilities, salaries, and operational spending with double-entry accounting',
                      style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _openNewExpenseDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Record Expense'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Dashboard KPI Cards Row
          summaryAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const SizedBox.shrink(),
            data: (summary) => Row(
              children: [
                Expanded(
                  child: _KpiCard(
                    title: "Today's Expenses",
                    amount: Money.fromPaise(summary.todayExpensesPaise).formatted,
                    icon: Icons.today,
                    accentColor: BillzoColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: "This Month",
                    amount: Money.fromPaise(summary.thisMonthExpensesPaise).formatted,
                    icon: Icons.calendar_month,
                    accentColor: Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Total Expenses',
                    amount: Money.fromPaise(summary.totalAmountPaise).formatted,
                    subtitle: '${summary.totalExpensesCount} posted',
                    icon: Icons.receipt_long,
                    accentColor: BillzoColors.darkSlate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Cash Outflow',
                    amount: Money.fromPaise(summary.cashExpensesPaise).formatted,
                    icon: Icons.payments_outlined,
                    accentColor: BillzoColors.accentOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Bank Outflow',
                    amount: Money.fromPaise(summary.bankExpensesPaise).formatted,
                    icon: Icons.account_balance_outlined,
                    accentColor: Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    title: 'Input GST Credit',
                    amount: Money.fromPaise(summary.totalGstPaise).formatted,
                    icon: Icons.verified_outlined,
                    accentColor: BillzoColors.successGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Filter Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BillzoColors.neutralBorder),
            ),
            child: Row(
              children: [
                // Search Input
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by payee, description, or EXP number...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(expenseSearchQueryProvider.notifier).state = '';
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) {
                        ref.read(expenseSearchQueryProvider.notifier).state = val;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Category Filter
                Expanded(
                  flex: 2,
                  child: categoriesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (categories) => Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: BillzoColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: currentCategory,
                          isExpanded: true,
                          hint: const Text('All Categories', style: TextStyle(fontSize: 12)),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Categories', style: TextStyle(fontSize: 12))),
                            ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 12)))),
                          ],
                          onChanged: (val) => ref.read(expenseCategoryFilterProvider.notifier).state = val,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Status Filter
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: BillzoColors.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ExpenseStatus?>(
                        value: currentStatus,
                        isExpanded: true,
                        hint: const Text('All Statuses', style: TextStyle(fontSize: 12)),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All Statuses', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: ExpenseStatus.draft, child: Text('Draft', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: ExpenseStatus.posted, child: Text('Posted', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: ExpenseStatus.cancelled, child: Text('Cancelled', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (val) => ref.read(expenseStatusFilterProvider.notifier).state = val,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Payment Method Filter
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: BillzoColors.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<PaymentMethod?>(
                        value: currentMethod,
                        isExpanded: true,
                        hint: const Text('All Methods', style: TextStyle(fontSize: 12)),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Methods', style: TextStyle(fontSize: 12))),
                          ...PaymentMethod.values.map((m) => DropdownMenuItem(value: m, child: Text(m.displayName, style: const TextStyle(fontSize: 12)))),
                        ],
                        onChanged: (val) => ref.read(expensePaymentMethodFilterProvider.notifier).state = val,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Date Filter Button
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: currentDateRange,
                    );
                    if (picked != null) {
                      ref.read(expenseDateRangeFilterProvider.notifier).state = picked;
                    }
                  },
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    currentDateRange == null
                        ? 'Date Range'
                        : '${DateFormat('dd/MM').format(currentDateRange.start)} - ${DateFormat('dd/MM').format(currentDateRange.end)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),

                // Clear Filters CTA
                if (currentSearch.isNotEmpty ||
                    currentStatus != null ||
                    currentCategory != null ||
                    currentMethod != null ||
                    currentDateRange != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off, size: 20),
                    tooltip: 'Reset Filters',
                    onPressed: () {
                      _searchController.clear();
                      ref.read(expenseSearchQueryProvider.notifier).state = '';
                      ref.read(expenseStatusFilterProvider.notifier).state = null;
                      ref.read(expenseCategoryFilterProvider.notifier).state = null;
                      ref.read(expensePaymentMethodFilterProvider.notifier).state = null;
                      ref.read(expenseDateRangeFilterProvider.notifier).state = null;
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Data Table Canvas
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BillzoColors.neutralBorder),
              ),
              child: expensesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error loading expenses: $e', style: const TextStyle(color: BillzoColors.dangerRed)),
                  ),
                ),
                data: (expenses) {
                  if (expenses.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'No expenses found',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Record overhead, utilities, or supplier payments to see them listed here.',
                            style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _openNewExpenseDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Record First Expense'),
                          ),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(BillzoColors.neutralLight),
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 52,
                        columns: const [
                          DataColumn(label: Text('Expense #', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Payee / Vendor', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w700))),
                          DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.w700))),
                        ],
                        rows: expenses.map((expense) {
                          Color statusColor;
                          Color statusBgColor;
                          switch (expense.status) {
                            case ExpenseStatus.draft:
                              statusColor = Colors.amber.shade800;
                              statusBgColor = Colors.amber.shade50;
                              break;
                            case ExpenseStatus.posted:
                              statusColor = BillzoColors.successGreen;
                              statusBgColor = Colors.green.shade50;
                              break;
                            case ExpenseStatus.cancelled:
                              statusColor = BillzoColors.dangerRed;
                              statusBgColor = Colors.red.shade50;
                              break;
                          }

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  expense.expenseNumber ?? 'DRAFT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: expense.isDraft ? Colors.amber.shade800 : BillzoColors.darkSlate,
                                  ),
                                ),
                                onTap: () => _openExpenseDetail(expense),
                              ),
                              DataCell(
                                Text(dateFormat.format(expense.expenseDate)),
                                onTap: () => _openExpenseDetail(expense),
                              ),
                              DataCell(
                                Text(expense.categoryName ?? 'Operational'),
                                onTap: () => _openExpenseDetail(expense),
                              ),
                              DataCell(
                                Text(expense.payee, style: const TextStyle(fontWeight: FontWeight.w600)),
                                onTap: () => _openExpenseDetail(expense),
                              ),
                              DataCell(
                                Text(
                                  expense.totalAmount.formatted,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                onTap: () => _openExpenseDetail(expense),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(expense.paymentMethod.icon, size: 16, color: BillzoColors.neutralText),
                                    const SizedBox(width: 6),
                                    Text(expense.paymentMethod.displayName),
                                  ],
                                ),
                                onTap: () => _openExpenseDetail(expense),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusBgColor,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: statusColor.withAlpha(80)),
                                  ),
                                  child: Text(
                                    expense.status.displayName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                onTap: () => _openExpenseDetail(expense),
                              ),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.chevron_right, size: 20),
                                  onPressed: () => _openExpenseDetail(expense),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String amount;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;

  const _KpiCard({
    required this.title,
    required this.amount,
    this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: BillzoColors.neutralText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: accentColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: accentColor),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 10, color: BillzoColors.neutralText),
            ),
          ],
        ],
      ),
    );
  }
}
