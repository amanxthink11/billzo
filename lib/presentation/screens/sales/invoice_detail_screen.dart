import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/invoice_providers.dart';
import 'package:billzo/presentation/screens/payments/payment_form_dialog.dart';
import 'package:billzo/presentation/screens/sales/invoice_builder_screen.dart';
import 'package:billzo/presentation/screens/sales/print_preview_dialog.dart';

/// Screen displaying the full statutory details of a sales invoice.
class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final Business business;
  final String invoiceId;

  const InvoiceDetailScreen({
    super.key,
    required this.business,
    required this.invoiceId,
  });

  @override
  ConsumerState<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  bool _isProcessing = false;

  Future<void> _handleCancel(Invoice invoice) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Sales Invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel Invoice ${invoice.invoiceNumber}? This will preserve the record, restore deducted inventory, and reverse ledger entries.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Cancellation Reason *',
                hintText: 'e.g., Customer cancelled, billing error, order modified',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abort'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.dangerRed),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Confirm Cancellation', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && reasonController.text.trim().isNotEmpty) {
      setState(() => _isProcessing = true);
      final service = ref.read(invoiceServiceProvider);
      try {
        await service.cancelInvoice(invoice.id, cancellationReason: reasonController.text.trim());
        ref.invalidate(invoiceDetailProvider(invoice.id));
        ref.invalidate(invoicesListProvider);
        ref.invalidate(invoicesCountProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invoice ${invoice.invoiceNumber} has been safely cancelled.'),
              backgroundColor: BillzoColors.dangerRed,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error cancelling invoice: $e'), backgroundColor: BillzoColors.dangerRed),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleFinalizeDraft(Invoice draft) async {
    setState(() => _isProcessing = true);
    final service = ref.read(invoiceServiceProvider);
    try {
      final finalized = await service.finalizeInvoice(draft);
      ref.invalidate(invoiceDetailProvider(draft.id));
      ref.invalidate(invoicesListProvider);
      ref.invalidate(invoicesCountProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice ${finalized.invoiceNumber} finalized successfully!'),
            backgroundColor: BillzoColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error finalizing: $e'), backgroundColor: BillzoColors.dangerRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handlePrint(Invoice invoice, Party? customer, PrintFormat format) async {
    final businessRepo = ref.read(businessRepositoryProvider);
    final settings = await businessRepo.getBusinessSettings(widget.business.id);

    if (!mounted) return;
    await PrintPreviewDialog.show(
      context,
      business: widget.business,
      invoice: invoice,
      customer: customer,
      settings: settings,
      initialFormat: format,
    );
  }

  Future<void> _handlePdfShare(Invoice invoice, Party? customer) async {
    setState(() => _isProcessing = true);
    final printer = ref.read(printerServiceProvider);
    final businessRepo = ref.read(businessRepositoryProvider);
    final settings = await businessRepo.getBusinessSettings(widget.business.id);

    try {
      await printer.shareInvoicePdf(
        invoice: invoice,
        business: widget.business,
        customer: customer,
        settings: settings,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF action: $e'), backgroundColor: BillzoColors.neutralText),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(invoiceDetailProvider(widget.invoiceId));
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: BillzoColors.canvasLight,
      appBar: AppBar(
        title: const Text('Invoice Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: BillzoColors.cardSurface,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : invoiceAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading invoice: $err')),
              data: (invoice) {
                if (invoice == null) {
                  return const Center(child: Text('Invoice not found.'));
                }

                final isInterState = invoice.igstPaise > 0;
                final logoFile = widget.business.logoPath != null ? File(widget.business.logoPath!) : null;
                final signatureFile = widget.business.signaturePath != null ? File(widget.business.signaturePath!) : null;
                final isCompositionOrUnregistered = widget.business.gstin == null || widget.business.gstin!.trim().isEmpty;
                final documentTitle = (invoice.invoiceType == InvoiceType.billOfSupply || isCompositionOrUnregistered)
                    ? 'BILL OF SUPPLY'
                    : invoice.invoiceType.displayName.toUpperCase();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top Action Bar
                          _buildActionBar(invoice),
                          const SizedBox(height: 16),

                          // Main Printable Paper Canvas Card
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: BillzoColors.cardSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: BillzoColors.border),
                              boxShadow: const [
                                BoxShadow(color: Color(0x08000000), blurRadius: 15, offset: Offset(0, 5)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. Header: Merchant info & Invoice badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (logoFile != null && logoFile.existsSync()) ...[
                                          Container(
                                            width: 64,
                                            height: 64,
                                            margin: const EdgeInsets.only(right: 14),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: BillzoColors.border),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: Image.file(logoFile, fit: BoxFit.contain),
                                          ),
                                        ],
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.business.name,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: BillzoColors.darkSlate),
                                            ),
                                            if (widget.business.addressLine1 != null)
                                              Text(
                                                widget.business.addressLine1! + (widget.business.city != null ? ', ${widget.business.city}' : ''),
                                                style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                              ),
                                            Text(
                                              'State: ${widget.business.stateName} (${widget.business.stateCode})',
                                              style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                            ),
                                            if (widget.business.gstin != null)
                                              Text(
                                                'GSTIN: ${widget.business.gstin}',
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                                              ),
                                            Text(
                                              'Phone: ${widget.business.phone}',
                                              style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),

                                    // Invoice Meta Box
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: BillzoColors.border),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: invoice.isFinalized
                                                      ? const Color(0xFFEFF6FF)
                                                      : (invoice.isCancelled ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9)),
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(
                                                    color: (invoice.isFinalized
                                                            ? BillzoColors.primaryBlue
                                                            : (invoice.isCancelled ? BillzoColors.dangerRed : BillzoColors.neutralText))
                                                        .withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Text(
                                                  invoice.lifecycleStatus.displayName.toUpperCase(),
                                                  style: TextStyle(
                                                    color: invoice.isFinalized
                                                        ? BillzoColors.primaryBlue
                                                        : (invoice.isCancelled ? BillzoColors.dangerRed : BillzoColors.neutralText),
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: invoice.isPaid
                                                      ? const Color(0xFFE8F5E9)
                                                      : (invoice.isPartiallyPaid ? const Color(0xFFFFF3E0) : const Color(0xFFFEE2E2)),
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(
                                                    color: (invoice.isPaid
                                                            ? BillzoColors.successGreen
                                                            : (invoice.isPartiallyPaid ? BillzoColors.accentOrange : BillzoColors.dangerRed))
                                                        .withValues(alpha: 0.35),
                                                  ),
                                                ),
                                                child: Text(
                                                  invoice.paymentStatus.code,
                                                  style: TextStyle(
                                                    color: invoice.isPaid
                                                        ? BillzoColors.successGreen
                                                        : (invoice.isPartiallyPaid ? BillzoColors.accentOrange : BillzoColors.dangerRed),
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            documentTitle,
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: BillzoColors.primaryBlue),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            invoice.invoiceNumber,
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: BillzoColors.darkSlate),
                                          ),
                                          Text(
                                            'Date: ${dateFormat.format(invoice.invoiceDate)}',
                                            style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                          ),
                                          Text(
                                            'Due: ${dateFormat.format(invoice.dueDate)}',
                                            style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                          ),
                                          Text(
                                            'Place of Supply: State ${invoice.placeOfSupplyStateCode}',
                                            style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const Divider(height: 36, color: BillzoColors.border),

                                // 2. Customer Section (Bill To)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('BILL TO (CUSTOMER)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: BillzoColors.primaryBlue)),
                                            const SizedBox(height: 4),
                                            Text(
                                              invoice.customerName ?? 'Customer',
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: BillzoColors.darkSlate),
                                            ),
                                            if (invoice.customerCompanyName != null)
                                              Text(invoice.customerCompanyName!, style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                                            if (invoice.customerAddress != null && invoice.customerAddress!.isNotEmpty)
                                              Text(invoice.customerAddress!, style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          if (invoice.customerGstin != null && invoice.customerGstin!.isNotEmpty)
                                            Text('GSTIN: ${invoice.customerGstin!}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                          if (invoice.customerPhone != null && invoice.customerPhone!.isNotEmpty)
                                            Text('Phone: ${invoice.customerPhone!}', style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // 3. Items Table
                                Table(
                                  columnWidths: const {
                                    0: FixedColumnWidth(32),
                                    1: FlexColumnWidth(4),
                                    2: FixedColumnWidth(65),
                                    3: FixedColumnWidth(60),
                                    4: FixedColumnWidth(85),
                                    5: FixedColumnWidth(80),
                                    6: FixedColumnWidth(90),
                                    7: FixedColumnWidth(65),
                                    8: FixedColumnWidth(95),
                                  },
                                  children: [
                                    TableRow(
                                      decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                                      children: [
                                        _th('#'),
                                        _th('Item Description'),
                                        _th('HSN', align: TextAlign.center),
                                        _th('Qty', align: TextAlign.right),
                                        _th('Rate (₹)', align: TextAlign.right),
                                        _th('Disc (₹)', align: TextAlign.right),
                                        _th('Taxable (₹)', align: TextAlign.right),
                                        _th('GST', align: TextAlign.center),
                                        _th('Amount (₹)', align: TextAlign.right),
                                      ],
                                    ),
                                    for (int i = 0; i < invoice.items.length; i++) ...[
                                      _buildItemRow(i + 1, invoice.items[i]),
                                    ],
                                  ],
                                ),

                                const SizedBox(height: 24),

                                // 4. Calculations Summary Grid
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Left: Amount in Words, Notes, Terms
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: BillzoColors.border),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'AMOUNT IN WORDS:',
                                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: BillzoColors.neutralText),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  invoice.amountInWords,
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BillzoColors.darkSlate),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (invoice.notes != null) ...[
                                            const SizedBox(height: 12),
                                            const Text('Notes:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: BillzoColors.neutralText)),
                                            Text(invoice.notes!, style: const TextStyle(fontSize: 12)),
                                          ],
                                          if (invoice.termsAndConditions != null) ...[
                                            const SizedBox(height: 12),
                                            const Text('Terms & Conditions:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: BillzoColors.neutralText)),
                                            Text(invoice.termsAndConditions!, style: const TextStyle(fontSize: 12)),
                                          ],
                                          if (invoice.isCancelled && invoice.cancellationReason != null) ...[
                                            const SizedBox(height: 16),
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF2F2),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: BillzoColors.dangerRed.withValues(alpha: 0.3)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'CANCELLATION AUDIT TRAIL',
                                                    style: TextStyle(color: BillzoColors.dangerRed, fontWeight: FontWeight.w700, fontSize: 11),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Reason: ${invoice.cancellationReason!}',
                                                    style: const TextStyle(color: BillzoColors.darkSlate, fontSize: 12),
                                                  ),
                                                  if (invoice.cancelledAt != null)
                                                    Text(
                                                      'Cancelled on: ${DateFormat('dd MMM yyyy, hh:mm a').format(invoice.cancelledAt!)}',
                                                      style: const TextStyle(color: BillzoColors.neutralText, fontSize: 11),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    const SizedBox(width: 24),

                                    // Right: Financial Summary
                                    Expanded(
                                      flex: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: BillzoColors.border),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          children: [
                                            _summaryRow('Taxable Amount', '₹${invoice.taxableAmount.toIndianRupeeString()}'),
                                            if (invoice.discountPaise > 0)
                                              _summaryRow('Total Discount', '- ₹${invoice.discount.toIndianRupeeString()}', isGreen: true),
                                            if (isInterState) ...[
                                              _summaryRow('IGST', '₹${invoice.igst.toIndianRupeeString()}'),
                                            ] else ...[
                                              _summaryRow('CGST', '₹${invoice.cgst.toIndianRupeeString()}'),
                                              _summaryRow('SGST', '₹${invoice.sgst.toIndianRupeeString()}'),
                                            ],
                                            if (invoice.cessPaise > 0)
                                              _summaryRow('Cess', '₹${invoice.cess.toIndianRupeeString()}'),
                                            if (invoice.roundOffPaise != 0)
                                              _summaryRow(
                                                'Round Off',
                                                '${invoice.roundOffPaise > 0 ? '+' : ''}${Money.fromPaise(invoice.roundOffPaise).formatted}',
                                              ),
                                            const Divider(height: 18, color: BillzoColors.border),
                                            _summaryRow(
                                              'Total Amount',
                                              '₹',
                                              isBold: true,
                                              fontSize: 16,
                                              color: BillzoColors.primaryBlue,
                                            ),
                                            const SizedBox(height: 4),
                                            _summaryRow(
                                              'Amount Paid',
                                              '₹',
                                              isBold: true,
                                              fontSize: 12,
                                              color: BillzoColors.successGreen,
                                            ),
                                            const SizedBox(height: 4),
                                            _summaryRow(
                                              'Balance Due',
                                              '₹',
                                              isBold: true,
                                              fontSize: 13,
                                              color: invoice.balanceAmountPaise > 0 ? BillzoColors.dangerRed : BillzoColors.successGreen,
                                            ),
                                            const SizedBox(height: 6),
                                            _summaryRow(
                                              'Payment Status',
                                              invoice.paymentStatus.code,
                                              isBold: true,
                                              fontSize: 12,
                                              color: invoice.isPaid
                                                  ? BillzoColors.successGreen
                                                  : (invoice.isPartiallyPaid ? BillzoColors.accentOrange : BillzoColors.dangerRed),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 36),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Generated offline with Billzo',
                                          style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11, color: BillzoColors.neutralText),
                                        ),
                                        Text(
                                          'Billing. Business. Simple.',
                                          style: TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('For ${widget.business.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                        if (signatureFile != null && signatureFile.existsSync()) ...[
                                          const SizedBox(height: 6),
                                          Image.file(signatureFile, height: 42, width: 120, fit: BoxFit.contain),
                                          const SizedBox(height: 4),
                                        ] else ...[
                                          const SizedBox(height: 36),
                                        ],
                                        Container(width: 140, height: 1, color: BillzoColors.border),
                                        const SizedBox(height: 4),
                                        const Text('Authorized Signatory', style: TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
  Widget _buildActionBar(Invoice invoice) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: invoice.isFinalized
                      ? const Color(0xFFEFF6FF)
                      : (invoice.isCancelled ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (invoice.isFinalized
                            ? BillzoColors.primaryBlue
                            : (invoice.isCancelled ? BillzoColors.dangerRed : BillzoColors.neutralText))
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  invoice.lifecycleStatus.displayName.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: invoice.isFinalized
                        ? BillzoColors.primaryBlue
                        : (invoice.isCancelled ? BillzoColors.dangerRed : BillzoColors.neutralText),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: invoice.isPaid
                      ? const Color(0xFFE8F5E9)
                      : (invoice.isPartiallyPaid ? const Color(0xFFFFF3E0) : const Color(0xFFFEE2E2)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (invoice.isPaid
                            ? BillzoColors.successGreen
                            : (invoice.isPartiallyPaid ? BillzoColors.accentOrange : BillzoColors.dangerRed))
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  invoice.paymentStatus.code,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: invoice.isPaid
                        ? BillzoColors.successGreen
                        : (invoice.isPartiallyPaid ? BillzoColors.accentOrange : BillzoColors.dangerRed),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Total: ₹${invoice.totalAmount.toIndianRupeeString()}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: BillzoColors.darkSlate),
              ),
              const SizedBox(width: 12),
              Text(
                'Paid: ₹${invoice.paidAmount.toIndianRupeeString()}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: BillzoColors.successGreen),
              ),
              const SizedBox(width: 12),
              Text(
                'Outstanding: ₹${invoice.balanceAmount.toIndianRupeeString()}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: invoice.balanceAmountPaise > 0 ? BillzoColors.dangerRed : BillzoColors.neutralText,
                ),
              ),
            ],
          ),

          // Actions
          Row(
            children: [
              // Receive Payment button if Finalized or Partially Paid and has outstanding balance
              if ((invoice.isFinalized || invoice.isPartiallyPaid) && invoice.balanceAmountPaise > 0) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BillzoColors.successGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  ),
                  icon: const Icon(Icons.payment, size: 16),
                  label: const Text('Receive Payment', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () async {
                    Party? customer;
                    if (invoice.customerId.isNotEmpty) {
                      final partyRepo = ref.read(partyRepositoryProvider);
                      customer = await partyRepo.getPartyById(invoice.customerId);
                    }
                    if (!mounted) return;
                    final payment = await PaymentFormDialog.show(
                      context,
                      business: widget.business,
                      preselectedCustomer: customer,
                      preselectedInvoice: invoice,
                      prefilledAmountPaise: invoice.balanceAmountPaise,
                    );
                    if (payment != null) {
                      ref.invalidate(invoiceDetailProvider(widget.invoiceId));
                      ref.invalidate(invoicesListProvider);
                    }
                  },
                ),
                const SizedBox(width: 8),
              ],

              if (invoice.isDraft) ...[
                // Edit Draft
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit Draft'),
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
                const SizedBox(width: 8),

                // Finalize Draft
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.primaryBlue),
                  icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                  label: const Text('Finalize Invoice', style: TextStyle(color: Colors.white)),
                  onPressed: () => _handleFinalizeDraft(invoice),
                ),
                const SizedBox(width: 8),
              ],

              // Print Button with popup menu for format (A4 / 80mm / 58mm)
              PopupMenuButton<PrintFormat>(
                tooltip: 'Print Invoice',
                onSelected: (fmt) => _handlePrint(invoice, null, fmt),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: PrintFormat.a4,
                    child: Row(
                      children: [
                        Icon(Icons.print, size: 18, color: BillzoColors.darkSlate),
                        SizedBox(width: 8),
                        Text('Standard A4 Print'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: PrintFormat.thermal80mm,
                    child: Row(
                      children: [
                        Icon(Icons.receipt, size: 18, color: BillzoColors.darkSlate),
                        SizedBox(width: 8),
                        Text('80mm Thermal Receipt'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: PrintFormat.thermal58mm,
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long, size: 18, color: BillzoColors.darkSlate),
                        SizedBox(width: 8),
                        Text('58mm Thermal Receipt'),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: BillzoColors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.print, size: 16, color: BillzoColors.darkSlate),
                      SizedBox(width: 6),
                      Text('Print', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Icon(Icons.arrow_drop_down, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Export PDF Button
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 16, color: BillzoColors.dangerRed),
                label: const Text('Export PDF'),
                onPressed: () => _handlePdfShare(invoice, null),
              ),
              const SizedBox(width: 8),

              // Cancel button if finalized (and no payments or partially paid)
              if (invoice.isFinalized || invoice.isPartiallyPaid)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEF2F2), foregroundColor: BillzoColors.dangerRed),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel Invoice'),
                  onPressed: () => _handleCancel(invoice),
                ),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildItemRow(int sNo, InvoiceItem item) {
    final taxRateBps = item.igstRateBasisPoints > 0
        ? item.igstRateBasisPoints
        : (item.cgstRateBasisPoints + item.sgstRateBasisPoints);
    final taxDisplay = '${(taxRateBps / 100).toStringAsFixed(0)}%';

    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: BillzoColors.border.withValues(alpha: 0.4))),
      ),
      children: [
        _td('$sNo', align: TextAlign.center),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: BillzoColors.darkSlate)),
            ],
          ),
        ),
        _td(item.hsnSac ?? '-', align: TextAlign.center),
        _td('${item.quantity.toStringAsFixed(item.unitCode == 'PCS' ? 0 : 2)} ${item.unitCode}', align: TextAlign.right),
        _td(Money.fromPaise(item.ratePaise).formattedWithoutSymbol, align: TextAlign.right),
        _td(Money.fromPaise(item.discountPaise).formattedWithoutSymbol, align: TextAlign.right),
        _td(Money.fromPaise(item.taxableAmountPaise).formattedWithoutSymbol, align: TextAlign.right),
        _td(taxDisplay, align: TextAlign.center),
        _td(Money.fromPaise(item.totalAmountPaise).formattedWithoutSymbol, align: TextAlign.right, isBold: true),
      ],
    );
  }

  Widget _th(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: BillzoColors.darkSlate),
      ),
    );
  }

  Widget _td(String text, {TextAlign align = TextAlign.left, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          color: BillzoColors.darkSlate,
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    bool isGreen = false,
    double fontSize = 13,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: fontSize, color: BillzoColors.neutralText)),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: color ?? (isGreen ? BillzoColors.successGreen : BillzoColors.darkSlate),
            ),
          ),
        ],
      ),
    );
  }
}
