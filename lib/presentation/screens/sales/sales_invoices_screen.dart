import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/invoice_providers.dart';
import 'package:billzo/presentation/screens/sales/invoice_builder_screen.dart';
import 'package:billzo/presentation/screens/sales/invoice_detail_screen.dart';
import 'package:billzo/presentation/screens/sales/print_preview_dialog.dart';

/// Screen listing sales invoices with real-time search, status filtering,
/// date range filtering, KPI summary chips, and quick actions.
class SalesInvoicesScreen extends ConsumerStatefulWidget {
  final Business business;

  const SalesInvoicesScreen({
    super.key,
    required this.business,
  });

  @override
  ConsumerState<SalesInvoicesScreen> createState() => _SalesInvoicesScreenState();
}

class _SalesInvoicesScreenState extends ConsumerState<SalesInvoicesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openNewInvoice() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceBuilderScreen(business: widget.business),
      ),
    );
  }

  void _openInvoiceDetail(Invoice invoice) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
          business: widget.business,
          invoiceId: invoice.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesListProvider);
    final currentStatus = ref.watch(invoiceStatusFilterProvider);
    final currentDateRange = ref.watch(invoiceDateRangeProvider);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Section: Module Title + Primary CTA
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sales Invoices',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: BillzoColors.darkSlate,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manage tax invoices, bills of supply, and drafts.',
                    style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BillzoColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'New Invoice [F2]',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: _openNewInvoice,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Summary KPI Metric Cards
          invoicesAsync.maybeWhen(
            data: (list) => _buildMetricCards(list),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // 3. Filter & Search Toolbar
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
                  flex: 4,
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by invoice number, customer, phone, or GSTIN...',
                        prefixIcon: const Icon(Icons.search, size: 18, color: BillzoColors.neutralText),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(invoiceSearchQueryProvider.notifier).state = '';
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
                        ref.read(invoiceSearchQueryProvider.notifier).state = val;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Status Filter Dropdown
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: BillzoColors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<InvoiceStatus?>(
                      value: currentStatus,
                      hint: const Text('Status: All', style: TextStyle(fontSize: 12)),
                      items: [
                        const DropdownMenuItem<InvoiceStatus?>(
                          value: null,
                          child: Text('All Statuses', style: TextStyle(fontSize: 12)),
                        ),
                        ...InvoiceStatus.values.map((s) {
                          return DropdownMenuItem<InvoiceStatus?>(
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
                        ref.read(invoiceStatusFilterProvider.notifier).state = val;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Date Range Filter Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.date_range, size: 16, color: BillzoColors.neutralText),
                  label: Text(
                    currentDateRange != null
                        ? '${DateFormat('dd/MM').format(currentDateRange.start)} - ${DateFormat('dd/MM').format(currentDateRange.end)}'
                        : 'Date Range',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      initialDateRange: currentDateRange,
                    );
                    ref.read(invoiceDateRangeProvider.notifier).state = picked;
                  },
                ),
                if (currentDateRange != null) ...[
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      ref.read(invoiceDateRangeProvider.notifier).state = null;
                    },
                  ),
                ],

                const Spacer(),

                // Refresh Button
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh Invoices',
                  onPressed: () {
                    ref.invalidate(invoicesListProvider);
                    ref.invalidate(invoicesCountProvider);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Data Table Canvas
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: BillzoColors.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BillzoColors.border),
              ),
              child: invoicesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Text('Error loading invoices: $err', style: const TextStyle(color: BillzoColors.dangerRed)),
                ),
                data: (invoices) {
                  if (invoices.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 54, color: BillzoColors.neutralText),
                          const SizedBox(height: 12),
                          const Text(
                            'No Sales Invoices Found',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Create your first sales invoice using the "+ New Invoice" button.',
                            style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.primaryBlue),
                            icon: const Icon(Icons.add, size: 18, color: Colors.white),
                            label: const Text('Create Invoice [F2]', style: TextStyle(color: Colors.white)),
                            onPressed: _openNewInvoice,
                          ),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.0), // Invoice #
                        1: FixedColumnWidth(100), // Date
                        2: FlexColumnWidth(2.6), // Customer
                        3: FixedColumnWidth(115), // Total Amount
                        4: FixedColumnWidth(170), // Payment Status
                        5: FixedColumnWidth(115), // Invoice Status
                        6: FixedColumnWidth(115), // Actions
                      },
                      children: [
                        // Table Header
                        TableRow(
                          decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                          children: [
                            _th('Invoice #'),
                            _th('Date'),
                            _th('Customer'),
                            _th('Total (₹)', align: TextAlign.right),
                            _th('Payment Status', align: TextAlign.center),
                            _th('Invoice Status', align: TextAlign.center),
                            _th('Actions', align: TextAlign.center),
                          ],
                        ),

                        // Table Rows
                        for (final invoice in invoices) ...[
                          _buildTableRow(invoice, dateFormat),
                        ],
                      ],
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

  TableRow _buildTableRow(Invoice invoice, DateFormat dateFormat) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: BillzoColors.border.withValues(alpha: 0.5))),
      ),
      children: [
        // Invoice Number (Clickable)
        InkWell(
          onTap: () => _openInvoiceDetail(invoice),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  invoice.invoiceType == InvoiceType.taxInvoice ? Icons.receipt : Icons.description_outlined,
                  size: 16,
                  color: BillzoColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    invoice.invoiceNumber,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            dateFormat.format(invoice.invoiceDate),
            style: const TextStyle(fontSize: 12, color: BillzoColors.darkSlate),
          ),
        ),

        // Customer
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                invoice.customerName ?? 'Customer',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: BillzoColors.darkSlate),
                overflow: TextOverflow.ellipsis,
              ),
              if (invoice.customerPhone != null && invoice.customerPhone!.isNotEmpty)
                Text(invoice.customerPhone!, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
            ],
          ),
        ),

        // Total Amount
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            '₹${invoice.totalAmount.toIndianRupeeString()}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BillzoColors.darkSlate),
          ),
        ),

        // Payment Status Badge
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: _buildPaymentStatusBadge(invoice),
        ),

        // Invoice Lifecycle Status Badge
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: _buildInvoiceStatusBadge(invoice),
        ),

        // Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // View Action
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 18),
                tooltip: 'View Invoice',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: const EdgeInsets.all(4),
                onPressed: () => _openInvoiceDetail(invoice),
              ),

              // Edit Action (if Draft)
              if (invoice.isDraft) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: BillzoColors.primaryBlue),
                  tooltip: 'Edit Draft',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: const EdgeInsets.all(4),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InvoiceBuilderScreen(
                          business: widget.business,
                          draftToEdit: invoice,
                        ),
                      ),
                    );
                  },
                ),
              ] else ...[
                // Print Action
                IconButton(
                  icon: const Icon(Icons.print_outlined, size: 18),
                  tooltip: 'Print Preview & Spool',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: const EdgeInsets.all(4),
                  onPressed: () async {
                    final businessRepo = ref.read(businessRepositoryProvider);
                    final settings = await businessRepo.getBusinessSettings(widget.business.id);
                    Party? customer;
                    if (invoice.customerId.isNotEmpty) {
                      final partyRepo = ref.read(partyRepositoryProvider);
                      customer = await partyRepo.getPartyById(invoice.customerId);
                    }
                    if (!mounted) return;
                    await PrintPreviewDialog.show(
                      context,
                      business: widget.business,
                      invoice: invoice,
                      customer: customer,
                      settings: settings,
                      initialFormat: PrintFormat.fromString(settings?.thermalPrinterType ?? 'a4'),
                    );
                  },
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

  Widget _buildPaymentStatusBadge(Invoice invoice) {
    if (invoice.isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BillzoColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.remove_circle_outline, size: 12, color: BillzoColors.neutralText),
            SizedBox(width: 4),
            Text(
              'CANCELLED',
              style: TextStyle(color: BillzoColors.neutralText, fontWeight: FontWeight.w700, fontSize: 10),
            ),
          ],
        ),
      );
    }

    final pStatus = invoice.paymentStatus;
    Color color;
    Color bg;
    IconData icon;
    String label;
    String? subtitle;

    switch (pStatus) {
      case InvoicePaymentStatus.paid:
        color = BillzoColors.successGreen;
        bg = const Color(0xFFE8F5E9);
        icon = Icons.check_circle;
        label = 'PAID';
        break;
      case InvoicePaymentStatus.partiallyPaid:
        color = BillzoColors.accentOrange;
        bg = const Color(0xFFFFF3E0);
        icon = Icons.timelapse;
        label = 'PARTIALLY PAID';
        subtitle = '₹${invoice.paidAmount.toIndianRupeeString()} paid / ₹${invoice.balanceAmount.toIndianRupeeString()} due';
        break;
      case InvoicePaymentStatus.due:
        color = BillzoColors.dangerRed;
        bg = const Color(0xFFFEE2E2);
        icon = Icons.pending_actions;
        label = 'DUE';
        if (invoice.isFinalized && invoice.balanceAmountPaise > 0) {
          subtitle = '₹${invoice.balanceAmount.toIndianRupeeString()} due';
        }
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInvoiceStatusBadge(Invoice invoice) {
    Color color;
    Color bg;
    IconData icon;
    String label;

    if (invoice.isFinalized) {
      color = BillzoColors.primaryBlue;
      bg = const Color(0xFFEFF6FF);
      icon = Icons.lock_outline;
      label = 'FINALIZED';
    } else if (invoice.isCancelled) {
      color = BillzoColors.dangerRed;
      bg = const Color(0xFFFEF2F2);
      icon = Icons.cancel_outlined;
      label = 'CANCELLED';
    } else {
      color = BillzoColors.neutralText;
      bg = const Color(0xFFF1F5F9);
      icon = Icons.edit_note;
      label = 'DRAFT';
    }

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCards(List<Invoice> list) {
    int totalSalesPaise = 0;
    int totalReceivablePaise = 0;
    int finalizedCount = 0;
    int draftsCount = 0;

    for (final inv in list) {
      if (inv.isFinalized || inv.isPaid || inv.isPartiallyPaid) {
        totalSalesPaise += inv.totalAmountPaise;
        totalReceivablePaise += inv.balanceAmountPaise;
        finalizedCount++;
      } else if (inv.isDraft) {
        draftsCount++;
      }
    }

    return Row(
      children: [
        Expanded(
          child: _metricCard(
            'Total Sales',
            '₹${Money.fromPaise(totalSalesPaise).toIndianRupeeString()}',
            Icons.trending_up,
            BillzoColors.primaryBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'Outstanding Receivables',
            '₹${Money.fromPaise(totalReceivablePaise).toIndianRupeeString()}',
            Icons.account_balance_wallet_outlined,
            BillzoColors.accentOrange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'Finalized Invoices',
            '$finalizedCount',
            Icons.check_circle_outline,
            BillzoColors.successGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            'Open Drafts',
            '$draftsCount',
            Icons.edit_note,
            BillzoColors.neutralText,
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BillzoColors.border),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
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
