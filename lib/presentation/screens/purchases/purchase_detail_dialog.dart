import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/providers/purchase_providers.dart';
import 'package:billzo/presentation/screens/payments/supplier_payment_dialog.dart';
import 'package:billzo/presentation/screens/purchases/purchase_return_dialog.dart';

/// Modal dialog showing comprehensive purchase bill details, item breakdown,
/// GST / ITC audit trails, payment history, and actions.
class PurchaseDetailDialog extends ConsumerStatefulWidget {
  final Business business;
  final String purchaseId;
  final VoidCallback? onEditDraft;

  const PurchaseDetailDialog({
    super.key,
    required this.business,
    required this.purchaseId,
    this.onEditDraft,
  });

  static Future<void> show(
    BuildContext context, {
    required Business business,
    required String purchaseId,
    VoidCallback? onEditDraft,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => PurchaseDetailDialog(
        business: business,
        purchaseId: purchaseId,
        onEditDraft: onEditDraft,
      ),
    );
  }

  @override
  ConsumerState<PurchaseDetailDialog> createState() => _PurchaseDetailDialogState();
}

class _PurchaseDetailDialogState extends ConsumerState<PurchaseDetailDialog> {
  bool _isProcessing = false;
  String? _errorMessage;

  Future<void> _finalizePurchase(Purchase purchase) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(purchaseServiceProvider);
      await service.finalizePurchase(purchase);

      ref.invalidate(purchasesListProvider);
      ref.invalidate(purchaseDetailProvider(widget.purchaseId));
      ref.invalidate(partiesListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase bill finalized successfully.')),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cancelPurchase(Purchase purchase) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Purchase Bill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to cancel purchase ${purchase.purchaseNumber}?'),
            const SizedBox(height: 8),
            const Text(
              'This will atomically reverse inventory stock, restore supplier payable, and reverse input tax credit.',
              style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Cancellation Reason *',
                hintText: 'e.g., Duplicate entry, Order cancelled',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Go Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.dangerRed, foregroundColor: Colors.white),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Cancel Purchase'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(purchaseServiceProvider);
      await service.cancelPurchase(
        purchase.id,
        cancellationReason: reasonController.text.trim(),
      );

      ref.invalidate(purchasesListProvider);
      ref.invalidate(purchaseDetailProvider(widget.purchaseId));
      ref.invalidate(partiesListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase cancelled and entries reversed successfully.')),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchaseAsync = ref.watch(purchaseDetailProvider(widget.purchaseId));
    final dateFormat = DateFormat('dd MMM yyyy');

    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 820),
        child: purchaseAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: BillzoColors.dangerRed, size: 36),
                const SizedBox(height: 12),
                Text('Failed to load purchase bill: $err'),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              ],
            ),
          ),
          data: (purchase) {
            if (purchase == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Purchase bill not found.'),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: BillzoColors.border)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, color: BillzoColors.primaryBlue, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  purchase.purchaseNumber,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: BillzoColors.darkSlate,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _buildStatusBadge(purchase.status),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Supplier: ${purchase.supplierName ?? "Supplier"} • Invoice: ${purchase.supplierInvoiceNumber ?? "N/A"} (${dateFormat.format(purchase.supplierInvoiceDate ?? purchase.purchaseDate)})',
                              style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // 2. Body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: BillzoColors.dangerRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: BillzoColors.dangerRed.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: BillzoColors.dangerRed, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(_errorMessage!, style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Cancellation Notice Banner
                        if (purchase.status == PurchaseStatus.cancelled) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: BillzoColors.dangerRed.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: BillzoColors.dangerRed.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.cancel_outlined, color: BillzoColors.dangerRed, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'PURCHASE BILL CANCELLED',
                                      style: TextStyle(fontWeight: FontWeight.w700, color: BillzoColors.dangerRed, fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Reason: ${purchase.cancellationReason ?? "No reason specified"}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                if (purchase.cancelledAt != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Cancelled on: ${dateFormat.format(purchase.cancelledAt!)}',
                                    style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        // KPI Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricTile(
                                'Total Bill Amount',
                                Money.formatPaise(purchase.totalAmountPaise),
                                BillzoColors.darkSlate,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricTile(
                                'Paid Amount',
                                Money.formatPaise(purchase.paidAmountPaise),
                                BillzoColors.successGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricTile(
                                'Balance Outstanding',
                                Money.formatPaise(purchase.balanceAmountPaise),
                                purchase.balanceAmountPaise > 0 ? BillzoColors.dangerRed : BillzoColors.neutralText,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricTile(
                                'Eligible ITC',
                                Money.formatPaise(purchase.eligibleItcPaise),
                                BillzoColors.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Bill Details Grid
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: BillzoColors.canvasLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: BillzoColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bill Metadata',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildInfoItem('Purchase Date', dateFormat.format(purchase.purchaseDate))),
                                  Expanded(child: _buildInfoItem('Due Date', dateFormat.format(purchase.dueDate))),
                                  Expanded(child: _buildInfoItem('Supplier Invoice #', purchase.supplierInvoiceNumber ?? 'N/A')),
                                  Expanded(child: _buildInfoItem('Place of Supply', purchase.placeOfSupply)),
                                ],
                              ),
                              if (purchase.notes != null && purchase.notes!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildInfoItem('Notes', purchase.notes!),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Line Items Table
                        const Text(
                          'Purchase Items',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                        ),
                        const SizedBox(height: 8),

                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: BillzoColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Table(
                            columnWidths: const {
                              0: FlexColumnWidth(3.5),
                              1: FlexColumnWidth(1.5),
                              2: FlexColumnWidth(1.8),
                              3: FlexColumnWidth(2),
                              4: FlexColumnWidth(2),
                              5: FlexColumnWidth(2),
                              6: FlexColumnWidth(1.5),
                            },
                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(
                                  color: BillzoColors.canvasLight,
                                  border: Border(bottom: BorderSide(color: BillzoColors.border)),
                                ),
                                children: [
                                  _tableHeader('Item / Description'),
                                  _tableHeader('HSN/SAC'),
                                  _tableHeader('Qty & Unit'),
                                  _tableHeader('Rate (₹)'),
                                  _tableHeader('Taxable (₹)'),
                                  _tableHeader('GST (₹)'),
                                  _tableHeader('ITC'),
                                ],
                              ),
                              ...purchase.items.map((item) {
                                final qtyDisplay = (item.quantityScaled / 1000.0).toStringAsFixed(
                                  item.quantityScaled % 1000 == 0 ? 0 : 3,
                                );
                                final gstPercent = (item.taxRateBasisPoints / 100.0).toStringAsFixed(0);

                                return TableRow(
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: BillzoColors.border)),
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.description ?? item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(item.hsnSac ?? '-', style: const TextStyle(fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text('$qtyDisplay ${item.unit}', style: const TextStyle(fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(Money.formatPaise(item.ratePaise), style: const TextStyle(fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(Money.formatPaise(item.taxableAmountPaise), style: const TextStyle(fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(Money.formatPaise(item.totalTaxPaise), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                          Text('$gstPercent% GST', style: const TextStyle(fontSize: 10, color: BillzoColors.neutralText)),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: _buildItcBadge(item.isItcEligible ? ItcEligibility.eligible : ItcEligibility.ineligible),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Financial Summary Card
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ITC Audit Card
                            Expanded(
                              flex: 3,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: BillzoColors.cardSurface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: BillzoColors.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.verified_outlined, size: 18, color: BillzoColors.primaryBlue),
                                        SizedBox(width: 8),
                                        Text('Input Tax Credit (ITC) Summary', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _summaryLine('Eligible Input Tax:', Money.formatPaise(purchase.eligibleItcPaise), isBold: true, color: BillzoColors.successGreen),
                                    const SizedBox(height: 4),
                                    _summaryLine('Ineligible Input Tax (Sec 17(5)):', Money.formatPaise(purchase.ineligibleItcPaise), color: BillzoColors.neutralText),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Eligible ITC is debited to Input Tax Accounts (2310/2320/2330). Ineligible tax is accounted separately (2340).',
                                      style: TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),

                            // Total Bill Calculation Card
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: BillzoColors.canvasLight,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: BillzoColors.border),
                                ),
                                child: Column(
                                  children: [
                                    _summaryLine('Subtotal:', Money.formatPaise(purchase.subtotalPaise)),
                                    if (purchase.discountPaise > 0) ...[
                                      const SizedBox(height: 4),
                                      _summaryLine('Discount:', '-${Money.formatPaise(purchase.discountPaise)}', color: BillzoColors.dangerRed),
                                    ],
                                    const SizedBox(height: 4),
                                    _summaryLine('Taxable Amount:', Money.formatPaise(purchase.taxableAmountPaise)),
                                    if (purchase.cgstPaise > 0) ...[
                                      const SizedBox(height: 4),
                                      _summaryLine('CGST:', Money.formatPaise(purchase.cgstPaise)),
                                    ],
                                    if (purchase.sgstPaise > 0) ...[
                                      const SizedBox(height: 4),
                                      _summaryLine('SGST:', Money.formatPaise(purchase.sgstPaise)),
                                    ],
                                    if (purchase.igstPaise > 0) ...[
                                      const SizedBox(height: 4),
                                      _summaryLine('IGST:', Money.formatPaise(purchase.igstPaise)),
                                    ],
                                    if (purchase.roundOffPaise != 0) ...[
                                      const SizedBox(height: 4),
                                      _summaryLine('Round-Off:', Money.formatPaise(purchase.roundOffPaise)),
                                    ],
                                    const Divider(height: 16),
                                    _summaryLine('Grand Total:', Money.formatPaise(purchase.totalAmountPaise), isBold: true, fontSize: 16, color: BillzoColors.primaryBlue),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Footer Actions
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: BillzoColors.border)),
                  ),
                  child: Row(
                    children: [
                      // Cancel Bill Button
                      if (purchase.status != PurchaseStatus.cancelled) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: BillzoColors.dangerRed,
                            side: const BorderSide(color: BillzoColors.dangerRed),
                          ),
                          onPressed: _isProcessing ? null : () => _cancelPurchase(purchase),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Cancel Bill'),
                        ),
                      ],
                      const Spacer(),

                      // Edit Draft Action
                      if (purchase.status == PurchaseStatus.draft && widget.onEditDraft != null) ...[
                        OutlinedButton.icon(
                          onPressed: _isProcessing ? null : widget.onEditDraft,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit Draft'),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // Finalize Action
                      if (purchase.status == PurchaseStatus.draft) ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BillzoColors.primaryBlue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isProcessing ? null : () => _finalizePurchase(purchase),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Finalize Purchase'),
                        ),
                      ],

                      // Return / Debit Note Action
                      if (purchase.status == PurchaseStatus.finalized ||
                          purchase.status == PurchaseStatus.partiallyPaid ||
                          purchase.status == PurchaseStatus.paid) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: BillzoColors.accentOrange,
                            side: const BorderSide(color: BillzoColors.accentOrange),
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () async {
                                  await PurchaseReturnDialog.show(
                                    context,
                                    originalPurchase: purchase,
                                  );
                                },
                          icon: const Icon(Icons.assignment_return_outlined, size: 18),
                          label: const Text('Debit Note / Return'),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // Record Payment Action
                      if ((purchase.status == PurchaseStatus.finalized ||
                              purchase.status == PurchaseStatus.partiallyPaid) &&
                          purchase.balanceAmountPaise > 0) ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BillzoColors.successGreen,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () async {
                                  await SupplierPaymentDialog.show(
                                    context,
                                    business: widget.business,
                                    preselectedPurchase: purchase,
                                  );
                                },
                          icon: const Icon(Icons.payment, size: 18),
                          label: const Text('Record Payment'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusBadge(PurchaseStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildItcBadge(ItcEligibility itc) {
    final isEligible = itc == ItcEligibility.eligible;
    final color = isEligible ? BillzoColors.successGreen : BillzoColors.neutralText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        itc.displayName,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BillzoColors.canvasLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
      ),
    );
  }

  Widget _summaryLine(String label, String value, {bool isBold = false, double fontSize = 13, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
