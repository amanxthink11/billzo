import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_return.dart';
import 'package:billzo/domain/purchase/purchase_return_item.dart';
import 'package:billzo/domain/purchase/purchase_validator.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/providers/purchase_providers.dart';

/// Dialog to record a purchase return / debit note against a finalized purchase bill.
class PurchaseReturnDialog extends ConsumerStatefulWidget {
  final Purchase originalPurchase;

  const PurchaseReturnDialog({
    super.key,
    required this.originalPurchase,
  });

  static Future<PurchaseReturn?> show(
    BuildContext context, {
    required Purchase originalPurchase,
  }) {
    return showDialog<PurchaseReturn>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PurchaseReturnDialog(originalPurchase: originalPurchase),
    );
  }

  @override
  ConsumerState<PurchaseReturnDialog> createState() => _PurchaseReturnDialogState();
}

class _PurchaseReturnDialogState extends ConsumerState<PurchaseReturnDialog> {
  DateTime _returnDate = DateTime.now();
  String _returnReason = 'Defective / Damaged Goods';
  final TextEditingController _reasonCustomController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final Map<String, TextEditingController> _qtyControllers = {};
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<String> _commonReasons = [
    'Defective / Damaged Goods',
    'Goods Not as Per Order',
    'Excess Delivery Received',
    'Quality Rejection',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    for (final item in widget.originalPurchase.items) {
      _qtyControllers[item.id] = TextEditingController(text: '');
    }
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    _reasonCustomController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _parseScaledQty(String text) {
    final cleaned = text.trim();
    final val = double.tryParse(cleaned);
    if (val == null || val <= 0) return 0;
    return (val * 1000).round();
  }

  /// Calculates return line item financials based on returned quantity and original line pricing.
  PurchaseReturnItem? _computeReturnLine(PurchaseItem originalItem) {
    final returnQtyScaled = _parseScaledQty(_qtyControllers[originalItem.id]?.text ?? '');
    if (returnQtyScaled <= 0) return null;

    // Rate is in paise per 1 unit (1000 scaled)
    final taxableAmountPaise = (originalItem.ratePaise * returnQtyScaled + 500) ~/ 1000;
    final totalTaxBps = originalItem.taxRateBasisPoints;

    int cgstPaise = 0;
    int sgstPaise = 0;
    int igstPaise = 0;

    if (originalItem.igstPaise > 0) {
      igstPaise = (taxableAmountPaise * totalTaxBps + 5000) ~/ 10000;
    } else {
      final halfBps = totalTaxBps ~/ 2;
      cgstPaise = (taxableAmountPaise * halfBps + 5000) ~/ 10000;
      sgstPaise = (taxableAmountPaise * halfBps + 5000) ~/ 10000;
    }

    final totalTaxPaise = cgstPaise + sgstPaise + igstPaise;
    final lineTotalPaise = taxableAmountPaise + totalTaxPaise;
    final now = DateTime.now().toUtc();

    return PurchaseReturnItem(
      id: '',
      purchaseReturnId: '',
      purchaseItemId: originalItem.id,
      productId: originalItem.productId,
      productName: originalItem.productName,
      unitCode: originalItem.unit,
      quantityScaled: returnQtyScaled,
      ratePaise: originalItem.ratePaise,
      taxableAmountPaise: taxableAmountPaise,
      cgstAmountPaise: cgstPaise,
      sgstAmountPaise: sgstPaise,
      igstAmountPaise: igstPaise,
      cessAmountPaise: 0,
      totalAmountPaise: lineTotalPaise,
      taxRateBasisPoints: originalItem.taxRateBasisPoints,
      trackInventory: originalItem.trackInventory,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<PurchaseReturnItem> get _returnItems {
    final list = <PurchaseReturnItem>[];
    for (final item in widget.originalPurchase.items) {
      final line = _computeReturnLine(item);
      if (line != null) list.add(line);
    }
    return list;
  }

  int get _totalReturnTaxablePaise =>
      _returnItems.fold(0, (sum, i) => sum + i.taxableAmountPaise);

  int get _totalReturnTaxPaise =>
      _returnItems.fold(0, (sum, i) => sum + i.totalTaxPaise);

  int get _totalReturnAmountPaise =>
      _returnItems.fold(0, (sum, i) => sum + i.lineTotalPaise);

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final returnItems = _returnItems;
    if (returnItems.isEmpty) {
      setState(() => _errorMessage = 'Please specify a return quantity for at least one item.');
      return;
    }

    final reason = _returnReason == 'Other'
        ? _reasonCustomController.text.trim()
        : _returnReason;

    if (reason.isEmpty) {
      setState(() => _errorMessage = 'Please provide a reason for the purchase return.');
      return;
    }

    final now = DateTime.now().toUtc();
    final purchaseReturn = PurchaseReturn(
      id: '',
      businessId: widget.originalPurchase.businessId,
      supplierId: widget.originalPurchase.supplierId,
      originalPurchaseId: widget.originalPurchase.id,
      returnNumber: '',
      returnDate: _returnDate,
      taxableAmountPaise: _totalReturnTaxablePaise,
      cgstPaise: returnItems.fold(0, (sum, i) => sum + i.cgstPaise),
      sgstPaise: returnItems.fold(0, (sum, i) => sum + i.sgstPaise),
      igstPaise: returnItems.fold(0, (sum, i) => sum + i.igstPaise),
      totalAmountPaise: _totalReturnAmountPaise,
      reason: _notesController.text.trim().isNotEmpty
          ? '$reason: ${_notesController.text.trim()}'
          : reason,
      items: returnItems,
      createdAt: now,
      updatedAt: now,
    );

    // Domain validation against original purchase quantities
    final validation = PurchaseValidator.validateReturn(
      purchaseReturn,
      originalPurchase: widget.originalPurchase,
    );
    if (validation.hasErrors) {
      setState(() => _errorMessage = validation.firstError);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final purchaseService = ref.read(purchaseServiceProvider);
      final recorded = await purchaseService.recordReturn(purchaseReturn);

      // Invalidate relevant providers
      ref.invalidate(purchasesListProvider);
      ref.invalidate(purchaseDetailProvider(widget.originalPurchase.id));
      ref.invalidate(partiesListProvider);

      if (mounted) {
        Navigator.of(context).pop(recorded);
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assignment_return_outlined, color: BillzoColors.accentOrange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Issue Debit Note / Purchase Return',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: BillzoColors.darkSlate,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Against Purchase ${widget.originalPurchase.purchaseNumber} • Supplier: ${widget.originalPurchase.supplierName ?? "Supplier"}',
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

            // Content
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
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Return Metadata
                    Row(
                      children: [
                        // Return Date
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Return Date *',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _returnDate,
                                    firstDate: widget.originalPurchase.purchaseDate,
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    setState(() => _returnDate = picked);
                                  }
                                },
                                child: Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: BillzoColors.border),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(dateFormat.format(_returnDate), style: const TextStyle(fontSize: 13)),
                                      const Icon(Icons.calendar_today, size: 16, color: BillzoColors.neutralText),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Return Reason
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reason for Return *',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _returnReason,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: BillzoColors.border),
                                  ),
                                ),
                                items: _commonReasons.map((r) {
                                  return DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _returnReason = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_returnReason == 'Other') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reasonCustomController,
                        decoration: InputDecoration(
                          hintText: 'Specify reason for return...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Items Table
                    const Text(
                      'Items to Return',
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
                          0: FlexColumnWidth(3),
                          1: FlexColumnWidth(1.5),
                          2: FlexColumnWidth(1.8),
                          3: FlexColumnWidth(2),
                          4: FlexColumnWidth(2),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(
                              color: BillzoColors.canvasLight,
                              border: Border(bottom: BorderSide(color: BillzoColors.border)),
                            ),
                            children: [
                              _tableHeader('Product / Description'),
                              _tableHeader('Purchased Qty'),
                              _tableHeader('Rate (₹)'),
                              _tableHeader('Return Qty'),
                              _tableHeader('Return Total (₹)'),
                            ],
                          ),
                          ...widget.originalPurchase.items.map((item) {
                            final returnLine = _computeReturnLine(item);
                            final controller = _qtyControllers[item.id];
                            final purchasedDisplay = (item.quantityScaled / 1000.0).toStringAsFixed(
                              item.quantityScaled % 1000 == 0 ? 0 : 3,
                            );

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
                                      if (item.hsnSac != null) ...[
                                        Text('HSN: ${item.hsnSac}', style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                                      ],
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text('$purchasedDisplay ${item.unit}', style: const TextStyle(fontSize: 12)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(Money.formatPaise(item.ratePaise), style: const TextStyle(fontSize: 12)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: TextField(
                                    controller: controller,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    returnLine != null ? Money.formatPaise(returnLine.lineTotalPaise) : '₹0.00',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Notes
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: 'Debit Note Notes (Optional)',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Accounting & Reversal Summary Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: BillzoColors.canvasLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: BillzoColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Return Taxable Value:'),
                              Text(Money.formatPaise(_totalReturnTaxablePaise), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Input GST Reversed:'),
                              Text(Money.formatPaise(_totalReturnTaxPaise), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Debit Note Amount:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              Text(
                                Money.formatPaise(_totalReturnAmountPaise),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: BillzoColors.dangerRed),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 14, color: BillzoColors.neutralText),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Decreases supplier payable and inventory stock value atomically. Input tax credit is reversed.',
                                  style: TextStyle(fontSize: 11, color: BillzoColors.neutralText),
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
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.accentOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Generate Debit Note', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
}
