import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/expense_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/screens/expenses/expense_builder_dialog.dart';

/// Modal dialog showing comprehensive detail and audit trail for an Expense.
class ExpenseDetailDialog extends ConsumerStatefulWidget {
  final Business business;
  final String expenseId;

  const ExpenseDetailDialog({
    super.key,
    required this.business,
    required this.expenseId,
  });

  static Future<void> show(
    BuildContext context, {
    required Business business,
    required String expenseId,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ExpenseDetailDialog(
        business: business,
        expenseId: expenseId,
      ),
    );
  }

  @override
  ConsumerState<ExpenseDetailDialog> createState() => _ExpenseDetailDialogState();
}

class _ExpenseDetailDialogState extends ConsumerState<ExpenseDetailDialog> {
  Expense? _expense;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadExpense();
  }

  Future<void> _loadExpense() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(expenseRepositoryProvider);
      final expense = await repo.getExpenseById(widget.expenseId);
      if (mounted) {
        setState(() {
          _expense = expense;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePost() async {
    if (_expense == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Expense Posting'),
        content: Text(
          'Post expense of ${_expense!.totalAmount.formatted} to ${_expense!.payee}? This will allocate a sequential expense number, create double-entry ledger postings, and deduct the payment account balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.primaryBlue),
            child: const Text('Confirm & Post', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final service = ref.read(expenseServiceProvider);
      final posted = await service.postExpense(
        _expense!.id,
        paymentAccountId: _expense!.paymentAccountId,
      );

      ref.invalidate(expensesListProvider(widget.business.id));
      ref.invalidate(expenseSummaryProvider(widget.business.id));
      ref.invalidate(cashBankAccountsProvider(widget.business.id));

      setState(() => _expense = posted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting expense: $e'), backgroundColor: BillzoColors.dangerRed),
        );
      }
    }
  }

  Future<void> _handleCancel() async {
    if (_expense == null) return;

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Posted Expense'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to cancel expense ${_expense!.expenseNumber}? This will create balancing reversal entries in the ledger and restore the cash/bank account balance.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Cancellation Reason *',
                  hintText: 'e.g. Duplicate entry, wrong vendor amount',
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 3) {
                    return 'Please enter a reason (min 3 characters)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.dangerRed),
            child: const Text('Confirm Cancellation', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final service = ref.read(expenseServiceProvider);
      final cancelled = await service.cancelExpense(
        _expense!.id,
        reason: reasonController.text.trim(),
      );

      ref.invalidate(expensesListProvider(widget.business.id));
      ref.invalidate(expenseSummaryProvider(widget.business.id));
      ref.invalidate(cashBankAccountsProvider(widget.business.id));

      setState(() => _expense = cancelled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling expense: $e'), backgroundColor: BillzoColors.dangerRed),
        );
      }
    }
  }

  Future<void> _handleDeleteDraft() async {
    if (_expense == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense Draft'),
        content: const Text('Permanently delete this unposted expense draft? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.dangerRed),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final service = ref.read(expenseServiceProvider);
      await service.deleteDraft(_expense!.id);

      ref.invalidate(expensesListProvider(widget.business.id));
      ref.invalidate(expenseSummaryProvider(widget.business.id));

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting draft: $e'), backgroundColor: BillzoColors.dangerRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Dialog(
        child: SizedBox(
          width: 300,
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_errorMessage != null || _expense == null) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: BillzoColors.dangerRed, size: 36),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Expense not found'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }

    final expense = _expense!;
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        expense.expenseNumber ?? 'Draft Expense',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusBgColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor.withAlpha(100)),
                        ),
                        child: Text(
                          expense.status.displayName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Content Area
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Overview Grid
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _InfoTile(label: 'Payee / Vendor', value: expense.payee),
                          ),
                          Expanded(
                            child: _InfoTile(
                              label: 'Category',
                              value: expense.categoryName ?? 'Operational Expense',
                            ),
                          ),
                          Expanded(
                            child: _InfoTile(
                              label: 'Expense Date',
                              value: DateFormat('dd MMM yyyy').format(expense.expenseDate),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _InfoTile(
                              label: 'Payment Method',
                              value: expense.paymentMethod.displayName,
                            ),
                          ),
                          Expanded(
                            child: _InfoTile(
                              label: 'Holding Account',
                              value: expense.paymentAccountName ?? 'Not Assigned',
                            ),
                          ),
                          Expanded(
                            child: _InfoTile(
                              label: 'Reference Number',
                              value: expense.referenceNumber ?? '—',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (expense.description.isNotEmpty) ...[
                        _InfoTile(label: 'Description / Purpose', value: expense.description),
                        const SizedBox(height: 16),
                      ],

                      if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                        _InfoTile(label: 'Internal Notes', value: expense.notes!),
                        const SizedBox(height: 16),
                      ],

                      // Financial Breakdown Card
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
                            const Text(
                              'Financial Breakdown',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            _AmountRow(label: 'Taxable Base Amount', amount: expense.taxableAmount.formatted),
                            if (expense.cgstPaise > 0)
                              _AmountRow(label: 'CGST', amount: expense.cgst.formatted),
                            if (expense.sgstPaise > 0)
                              _AmountRow(label: 'SGST', amount: expense.sgst.formatted),
                            if (expense.igstPaise > 0)
                              _AmountRow(label: 'IGST', amount: expense.igst.formatted),
                            if (expense.totalGstPaise > 0)
                              _AmountRow(label: 'Total GST (Input Credit)', amount: expense.totalGst.formatted),
                            const Divider(height: 16),
                            _AmountRow(
                              label: 'Total Expense Amount',
                              amount: expense.totalAmount.formatted,
                              isBold: true,
                              textColor: BillzoColors.primaryBlue,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Audit Metadata Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: BillzoColors.neutralBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Audit Trail & History',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BillzoColors.neutralText),
                            ),
                            const SizedBox(height: 6),
                            Text('Created: ${dateFormat.format(expense.createdAt.toLocal())}', style: const TextStyle(fontSize: 12)),
                            if (expense.postedAt != null)
                              Text('Posted: ${dateFormat.format(expense.postedAt!.toLocal())}', style: const TextStyle(fontSize: 12)),
                            if (expense.cancelledAt != null) ...[
                              Text('Cancelled: ${dateFormat.format(expense.cancelledAt!.toLocal())}', style: const TextStyle(fontSize: 12, color: BillzoColors.dangerRed)),
                              Text('Cancellation Reason: ${expense.cancellationReason}', style: const TextStyle(fontSize: 12, color: BillzoColors.dangerRed, fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              // Action Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left side actions
                  if (expense.isDraft)
                    TextButton.icon(
                      onPressed: _handleDeleteDraft,
                      icon: const Icon(Icons.delete_outline, color: BillzoColors.dangerRed, size: 18),
                      label: const Text('Delete Draft', style: TextStyle(color: BillzoColors.dangerRed)),
                    )
                  else if (expense.isPosted)
                    TextButton.icon(
                      onPressed: _handleCancel,
                      icon: const Icon(Icons.cancel_outlined, color: BillzoColors.dangerRed, size: 18),
                      label: const Text('Cancel Expense', style: TextStyle(color: BillzoColors.dangerRed)),
                    )
                  else
                    const SizedBox.shrink(),

                  // Right side actions
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                      if (expense.isDraft) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final updated = await ExpenseBuilderDialog.show(
                              context,
                              business: widget.business,
                              expenseToEdit: expense,
                            );
                            if (updated != null) {
                              setState(() => _expense = updated);
                            }
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit Draft'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _handlePost,
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Post Expense'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String amount;
  final bool isBold;
  final Color? textColor;

  const _AmountRow({
    required this.label,
    required this.amount,
    this.isBold = false,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: textColor ?? (isBold ? BillzoColors.darkSlate : BillzoColors.neutralText),
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: textColor ?? BillzoColors.darkSlate,
            ),
          ),
        ],
      ),
    );
  }
}
