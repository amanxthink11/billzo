import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/invoice_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/screens/payments/payment_detail_dialog.dart';
import 'package:billzo/presentation/screens/payments/payment_form_dialog.dart';

/// Screen listing customer payments with real-time KPI metrics, search,
/// multi-attribute filtering, receipt inspection, and recording flows.
class PaymentsScreen extends ConsumerStatefulWidget {
  final Business business;

  const PaymentsScreen({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openRecordPayment() async {
    final result = await PaymentFormDialog.show(
      context,
      business: widget.business,
    );
    if (result != null) {
      _refresh();
    }
  }

  void _openPaymentDetail(Payment payment) async {
    await PaymentDetailDialog.show(context, payment: payment);
    _refresh();
  }

  void _refresh() {
    ref.invalidate(paymentsListProvider(widget.business.id));
    ref.invalidate(paymentsCountProvider(widget.business.id));
    ref.invalidate(invoicesListProvider);
  }

  Future<void> _postDraft(Payment draft) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post Draft Payment'),
        content: Text('Are you sure you want to post payment ${draft.paymentNumber} for ₹${draft.amount.toIndianRupeeString()}? This will apply allocations to customer invoices and create balanced ledger entries.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.successGreen, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Post Payment'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final service = ref.read(paymentServiceProvider);
      await service.postDraft(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment posted successfully.'), backgroundColor: BillzoColors.successGreen),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post payment: $e'), backgroundColor: BillzoColors.dangerRed),
        );
      }
    }
  }

  Future<void> _deleteDraft(Payment draft) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft Payment'),
        content: const Text('Are you sure you want to permanently discard this draft payment? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep Draft')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.dangerRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard Draft'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final service = ref.read(paymentServiceProvider);
      await service.deleteDraft(draft.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft discarded.'), backgroundColor: BillzoColors.neutralText),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete draft: $e'), backgroundColor: BillzoColors.dangerRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentsListProvider(widget.business.id));
    final invoicesAsync = ref.watch(invoicesListProvider);
    final currentStatus = ref.watch(paymentStatusFilterProvider);
    final currentMethod = ref.watch(paymentMethodFilterProvider);
    final currentDateRange = ref.watch(paymentDateRangeProvider);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header & Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payments & Receipts',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: BillzoColors.darkSlate,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Record customer receipts, manage cash/bank accounts, and track outstanding receivables.',
                      style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BillzoColors.successGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'Record Payment [F4]',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: _openRecordPayment,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Summary KPI Metric Cards
          paymentsAsync.maybeWhen(
            data: (payments) {
              final invoices = invoicesAsync.maybeWhen(
                data: (list) => list,
                orElse: () => <Invoice>[],
              );
              return _buildKpiCards(payments, invoices);
            },
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // 3. Search & Filters Toolbar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BillzoColors.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: BillzoColors.border),
            ),
            child: Row(
              children: [
                // Search Input
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by payment number, customer, phone, or reference...',
                        prefixIcon: const Icon(Icons.search, size: 18, color: BillzoColors.neutralText),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(paymentSearchQueryProvider.notifier).clear();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: BillzoColors.border),
                        ),
                      ),
                      onChanged: (val) {
                        ref.read(paymentSearchQueryProvider.notifier).setQuery(val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Status Filter
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: BillzoColors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PaymentStatus?>(
                      value: currentStatus,
                      hint: const Text('Status: All', style: TextStyle(fontSize: 12)),
                      items: [
                        const DropdownMenuItem<PaymentStatus?>(
                          value: null,
                          child: Text('All Statuses', style: TextStyle(fontSize: 12)),
                        ),
                        ...PaymentStatus.values.map((s) {
                          return DropdownMenuItem<PaymentStatus?>(
                            value: s,
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(s.displayName, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        ref.read(paymentStatusFilterProvider.notifier).setStatus(val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Payment Method Filter
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: BillzoColors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PaymentMethod?>(
                      value: currentMethod,
                      hint: const Text('Method: All', style: TextStyle(fontSize: 12)),
                      items: [
                        const DropdownMenuItem<PaymentMethod?>(
                          value: null,
                          child: Text('All Methods', style: TextStyle(fontSize: 12)),
                        ),
                        ...PaymentMethod.values.map((m) {
                          return DropdownMenuItem<PaymentMethod?>(
                            value: m,
                            child: Row(
                              children: [
                                Icon(m.icon, size: 14, color: BillzoColors.darkSlate),
                                const SizedBox(width: 6),
                                Text(m.displayName, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        ref.read(paymentMethodFilterProvider.notifier).setMethod(val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Date Range Picker
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.date_range, size: 16, color: BillzoColors.neutralText),
                  label: Text(
                    currentDateRange.start != null
                        ? '${DateFormat('dd/MM').format(currentDateRange.start!)} - ${DateFormat('dd/MM').format(currentDateRange.end ?? currentDateRange.start!)}'
                        : 'Date Range',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      initialDateRange: currentDateRange.start != null
                          ? DateTimeRange(
                              start: currentDateRange.start!,
                              end: currentDateRange.end ?? currentDateRange.start!,
                            )
                          : null,
                    );
                    if (picked != null) {
                      ref.read(paymentDateRangeProvider.notifier).setRange(picked.start, picked.end);
                    }
                  },
                ),
                if (currentDateRange.start != null) ...[
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      ref.read(paymentDateRangeProvider.notifier).clear();
                    },
                  ),
                ],

                const Spacer(),

                // Refresh Button
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh Payments',
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Data Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: BillzoColors.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BillzoColors.border),
              ),
              child: paymentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Text('Error loading payments: $err', style: const TextStyle(color: BillzoColors.dangerRed)),
                ),
                data: (payments) {
                  if (payments.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.payments_outlined, size: 54, color: BillzoColors.neutralText),
                          const SizedBox(height: 12),
                          const Text(
                            'No Payments Recorded Yet',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Record payments received from customers using the "+ Record Payment" button.',
                            style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.successGreen, foregroundColor: Colors.white),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Record First Payment'),
                            onPressed: _openRecordPayment,
                          ),
                        ],
                      ),
                    );
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SingleChildScrollView(
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(1.4), // Payment #
                          1: FlexColumnWidth(1.1), // Date
                          2: FlexColumnWidth(2.0), // Customer
                          3: FlexColumnWidth(1.2), // Method
                          4: FlexColumnWidth(1.4), // Account / Ref
                          5: FlexColumnWidth(1.3), // Amount
                          6: FlexColumnWidth(1.1), // Status
                          7: FlexColumnWidth(1.3), // Actions
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          // Table Header
                          TableRow(
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              border: Border(bottom: BorderSide(color: BillzoColors.border, width: 1.5)),
                            ),
                            children: [
                              _th('Payment #'),
                              _th('Date'),
                              _th('Customer'),
                              _th('Payment Mode'),
                              _th('Account / Ref'),
                              _th('Amount', align: TextAlign.right),
                              _th('Status', align: TextAlign.center),
                              _th('Actions', align: TextAlign.center),
                            ],
                          ),

                          // Table Rows
                          ...payments.map((p) => _buildPaymentRow(p, dateFormat)),
                        ],
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

  TableRow _buildPaymentRow(Payment payment, DateFormat dateFormat) {
    return TableRow(
      decoration: BoxDecoration(
        color: payment.isCancelled ? const Color(0xFFFEF2F2).withValues(alpha: 0.3) : Colors.transparent,
        border: Border(bottom: BorderSide(color: BillzoColors.border.withValues(alpha: 0.5))),
      ),
      children: [
        // Payment #
        InkWell(
          onTap: () => _openPaymentDetail(payment),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  payment.isPosted
                      ? Icons.check_circle_outline
                      : payment.isDraft
                          ? Icons.edit_note
                          : Icons.cancel_outlined,
                  size: 16,
                  color: payment.status.color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    payment.paymentNumber,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BillzoColors.primaryBlue),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Date
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            dateFormat.format(payment.paymentDate),
            style: const TextStyle(fontSize: 12, color: BillzoColors.darkSlate),
          ),
        ),

        // Customer
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payment.customerName ?? 'Direct Customer',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: BillzoColors.darkSlate),
                overflow: TextOverflow.ellipsis,
              ),
              if (payment.customerPhone != null && payment.customerPhone!.isNotEmpty)
                Text(payment.customerPhone!, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
            ],
          ),
        ),

        // Payment Mode
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(payment.paymentMethod.icon, size: 14, color: BillzoColors.darkSlate),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  payment.paymentMethod.displayName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Account / Ref #
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payment.accountName ?? (payment.paymentMethod == PaymentMethod.cash ? 'Cash on Hand' : 'Default Bank'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: BillzoColors.darkSlate),
                overflow: TextOverflow.ellipsis,
              ),
              if (payment.referenceNumber != null && payment.referenceNumber!.isNotEmpty)
                Text('Ref: ${payment.referenceNumber}', style: const TextStyle(fontSize: 10, color: BillzoColors.neutralText)),
            ],
          ),
        ),

        // Amount
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            '₹${payment.amount.toIndianRupeeString()}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: payment.isCancelled ? BillzoColors.neutralText : BillzoColors.successGreen,
              decoration: payment.isCancelled ? TextDecoration.lineThrough : null,
            ),
          ),
        ),

        // Status Badge
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: payment.status.backgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: payment.status.color.withValues(alpha: 0.3)),
              ),
              child: Text(
                payment.status.displayName,
                style: TextStyle(color: payment.status.color, fontWeight: FontWeight.w700, fontSize: 11),
              ),
            ),
          ),
        ),

        // Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 18),
                tooltip: 'View Receipt',
                onPressed: () => _openPaymentDetail(payment),
              ),
              if (payment.isDraft) ...[
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, size: 18, color: BillzoColors.successGreen),
                  tooltip: 'Post Draft',
                  onPressed: () => _postDraft(payment),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: BillzoColors.dangerRed),
                  tooltip: 'Discard Draft',
                  onPressed: () => _deleteDraft(payment),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _th(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: BillzoColors.neutralText),
      ),
    );
  }

  Widget _buildKpiCards(List<Payment> payments, List<Invoice> invoices) {
    int totalReceivedPaise = 0;
    int todayReceivedPaise = 0;
    int cashReceivedPaise = 0;
    int bankReceivedPaise = 0;
    int outstandingReceivablesPaise = 0;

    final now = DateTime.now();

    for (final p in payments) {
      if (p.isPosted) {
        totalReceivedPaise += p.amountPaise;
        if (p.paymentDate.year == now.year &&
            p.paymentDate.month == now.month &&
            p.paymentDate.day == now.day) {
          todayReceivedPaise += p.amountPaise;
        }

        if (p.paymentMethod == PaymentMethod.cash) {
          cashReceivedPaise += p.amountPaise;
        } else {
          bankReceivedPaise += p.amountPaise;
        }
      }
    }

    for (final inv in invoices) {
      if (inv.isFinalized || inv.isPartiallyPaid) {
        outstandingReceivablesPaise += inv.balanceAmountPaise;
      }
    }

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            'Total Received',
            '₹${Money.fromPaise(totalReceivedPaise).toIndianRupeeString()}',
            Icons.account_balance_wallet,
            BillzoColors.successGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            "Today's Receipts",
            '₹${Money.fromPaise(todayReceivedPaise).toIndianRupeeString()}',
            Icons.today,
            BillzoColors.primaryBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'Cash Received',
            '₹${Money.fromPaise(cashReceivedPaise).toIndianRupeeString()}',
            Icons.payments_outlined,
            const Color(0xFF0D9488), // Teal
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'Bank / UPI Received',
            '₹${Money.fromPaise(bankReceivedPaise).toIndianRupeeString()}',
            Icons.account_balance,
            const Color(0xFF7C3AED), // Violet
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'Outstanding Receivables',
            '₹${Money.fromPaise(outstandingReceivablesPaise).toIndianRupeeString()}',
            Icons.pending_actions,
            BillzoColors.accentOrange,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillzoColors.neutralText),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
