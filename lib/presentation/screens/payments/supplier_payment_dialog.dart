import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/providers/purchase_providers.dart';

/// Modal dialog for recording a supplier payment with purchase bill allocation.
class SupplierPaymentDialog extends ConsumerStatefulWidget {
  final Business business;
  final Party? preselectedSupplier;
  final Purchase? preselectedPurchase;
  final int? prefilledAmountPaise;

  const SupplierPaymentDialog({
    super.key,
    required this.business,
    this.preselectedSupplier,
    this.preselectedPurchase,
    this.prefilledAmountPaise,
  });

  static Future<Payment?> show(
    BuildContext context, {
    required Business business,
    Party? preselectedSupplier,
    Purchase? preselectedPurchase,
    int? prefilledAmountPaise,
  }) {
    return showDialog<Payment>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SupplierPaymentDialog(
        business: business,
        preselectedSupplier: preselectedSupplier,
        preselectedPurchase: preselectedPurchase,
        prefilledAmountPaise: prefilledAmountPaise,
      ),
    );
  }

  @override
  ConsumerState<SupplierPaymentDialog> createState() => _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends ConsumerState<SupplierPaymentDialog> {
  Party? _supplier;
  DateTime _paymentDate = DateTime.now();
  PaymentMethod _method = PaymentMethod.bankTransfer;
  String? _selectedAccountId;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _refNumberController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<Purchase> _outstandingPurchases = [];
  final Map<String, TextEditingController> _allocationControllers = {};
  bool _isLoadingPurchases = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _supplier = widget.preselectedSupplier;

    if (widget.prefilledAmountPaise != null) {
      _amountController.text = (widget.prefilledAmountPaise! / 100.0).toStringAsFixed(2);
    } else if (widget.preselectedPurchase != null) {
      _amountController.text = (widget.preselectedPurchase!.balanceAmountPaise / 100.0).toStringAsFixed(2);
    }

    _amountController.addListener(_onAmountChanged);

    if (_supplier != null) {
      _loadSupplierPurchases(_supplier!.id);
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _refNumberController.dispose();
    _notesController.dispose();
    for (final c in _allocationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSupplierPurchases(String supplierId) async {
    setState(() {
      _isLoadingPurchases = true;
      _errorMessage = null;
    });

    try {
      final purchaseService = ref.read(purchaseServiceProvider);
      final purchases = await purchaseService.getOutstandingPurchasesForSupplier(
        widget.business.id,
        supplierId,
      );

      // Clean up previous controllers
      for (final c in _allocationControllers.values) {
        c.dispose();
      }
      _allocationControllers.clear();

      for (final p in purchases) {
        _allocationControllers[p.id] = TextEditingController();
      }

      setState(() {
        _outstandingPurchases = purchases;
        _isLoadingPurchases = false;
      });

      // Auto-allocate if amount is already entered
      _onAmountChanged();
    } catch (e) {
      setState(() {
        _isLoadingPurchases = false;
        _errorMessage = 'Failed to load outstanding purchases: $e';
      });
    }
  }

  void _onAmountChanged() {
    final amountPaise = _parsePaise(_amountController.text);
    if (amountPaise <= 0 || _outstandingPurchases.isEmpty) {
      for (final c in _allocationControllers.values) {
        c.text = '';
      }
      setState(() {});
      return;
    }

    // Auto-allocate FIFO
    final paymentService = ref.read(paymentServiceProvider);
    final autoAllocations = paymentService.autoAllocatePurchases(
      amountPaise: amountPaise,
      outstandingPurchases: _outstandingPurchases,
    );

    final allocMap = {for (var a in autoAllocations) a.documentId: a.allocatedAmountPaise};
    for (final p in _outstandingPurchases) {
      final allocated = allocMap[p.id] ?? 0;
      final controller = _allocationControllers[p.id];
      if (controller != null) {
        controller.text = allocated > 0 ? (allocated / 100.0).toStringAsFixed(2) : '';
      }
    }

    setState(() {});
  }

  int _parsePaise(String text) {
    final cleaned = text.trim().replaceAll(',', '');
    final val = double.tryParse(cleaned);
    if (val == null || val <= 0) return 0;
    return (val * 100).round();
  }

  int get _enteredAmountPaise => _parsePaise(_amountController.text);

  int get _totalAllocatedPaise {
    int sum = 0;
    for (final c in _allocationControllers.values) {
      sum += _parsePaise(c.text);
    }
    return sum;
  }

  int get _unallocatedPaise {
    final diff = _enteredAmountPaise - _totalAllocatedPaise;
    return diff > 0 ? diff : 0;
  }

  Future<void> _submit({required bool isDraft}) async {
    setState(() {
      _errorMessage = null;
    });

    if (_supplier == null) {
      setState(() => _errorMessage = 'Please select a supplier.');
      return;
    }

    final amountPaise = _enteredAmountPaise;
    if (amountPaise <= 0) {
      setState(() => _errorMessage = 'Payment amount must be greater than zero.');
      return;
    }

    if (_totalAllocatedPaise > amountPaise) {
      setState(() => _errorMessage = 'Total allocated amount cannot exceed payment amount.');
      return;
    }

    // Build allocations
    final List<PaymentAllocation> allocations = [];
    for (final p in _outstandingPurchases) {
      final controller = _allocationControllers[p.id];
      final allocPaise = controller != null ? _parsePaise(controller.text) : 0;
      if (allocPaise > 0) {
        if (allocPaise > p.balanceAmountPaise) {
          setState(() {
            _errorMessage = 'Allocation for purchase ${p.purchaseNumber} exceeds its balance.';
          });
          return;
        }
        allocations.add(
          PaymentAllocation(
            id: '',
            paymentId: '',
            documentId: p.id,
            documentType: 'PURCHASE',
            allocatedAmountPaise: allocPaise,
            invoiceNumber: p.purchaseNumber,
            invoiceDate: p.purchaseDate,
            invoiceTotalPaise: p.totalAmountPaise,
            invoiceOutstandingBeforePaise: p.balanceAmountPaise,
          ),
        );
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final paymentService = ref.read(paymentServiceProvider);
      final payment = await paymentService.recordSupplierPayment(
        businessId: widget.business.id,
        supplierId: _supplier!.id,
        supplierName: _supplier!.name,
        supplierPhone: _supplier!.phone,
        paymentDate: _paymentDate,
        paymentMethod: _method,
        amountPaise: amountPaise,
        accountId: _selectedAccountId,
        referenceNumber: _refNumberController.text.trim().isEmpty ? null : _refNumberController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        allocations: allocations,
        isDraft: isDraft,
      );

      // Invalidate relevant providers
      ref.invalidate(paymentsListProvider);
      ref.invalidate(purchasesListProvider);
      ref.invalidate(cashBankAccountsProvider);
      ref.invalidate(partiesListProvider);

      if (mounted) {
        Navigator.of(context).pop(payment);
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
    final accountsAsync = ref.watch(cashBankAccountsProvider(widget.business.id));
    final partiesAsync = ref.watch(partiesListProvider);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
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
                  const Icon(Icons.outbox, color: BillzoColors.dangerRed, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Record Supplier Payment',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: BillzoColors.darkSlate,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Disburse funds to supplier and reconcile outstanding purchase bills.',
                          style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
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

            // Body
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

                    // Top Form: Supplier & Payment Details
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Supplier Selector
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Supplier *',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: BillzoColors.darkSlate,
                                ),
                              ),
                              const SizedBox(height: 6),
                              partiesAsync.maybeWhen(
                                data: (parties) {
                                  final suppliers =
                                      parties.where((p) => p.partyType == PartyType.supplier).toList();
                                  return DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _supplier?.id,
                                    decoration: InputDecoration(
                                      hintText: 'Select supplier',
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: const BorderSide(color: BillzoColors.border),
                                      ),
                                    ),
                                    items: suppliers.map((s) {
                                      return DropdownMenuItem<String>(
                                        value: s.id,
                                        child: Text(
                                          '${s.name} (Payable: ₹${(s.currentBalancePaise / 100.0).toStringAsFixed(2)})',
                                          style: const TextStyle(fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val == null) return;
                                      final selected = suppliers.firstWhere((s) => s.id == val);
                                      setState(() => _supplier = selected);
                                      _loadSupplierPurchases(val);
                                    },
                                  );
                                },
                                orElse: () => const LinearProgressIndicator(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Payment Date
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Payment Date *',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: BillzoColors.darkSlate,
                                ),
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _paymentDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    setState(() => _paymentDate = picked);
                                  }
                                },
                                child: Container(
                                  height: 42,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: BillzoColors.border),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        dateFormat.format(_paymentDate),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      const Icon(Icons.calendar_today, size: 16, color: BillzoColors.neutralText),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 2: Payment Method, Account, Amount
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Method
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Payment Mode *',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: BillzoColors.darkSlate,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<PaymentMethod>(
                                isExpanded: true,
                                initialValue: _method,
                                decoration: InputDecoration(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: BillzoColors.border),
                                  ),
                                ),
                                items: PaymentMethod.values.map((m) {
                                  return DropdownMenuItem(
                                    value: m,
                                    child: Text(m.displayName, style: const TextStyle(fontSize: 13)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _method = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Cash / Bank Account
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Disbursing Account',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: BillzoColors.darkSlate,
                                ),
                              ),
                              const SizedBox(height: 6),
                              accountsAsync.maybeWhen(
                                data: (accounts) {
                                  return DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _selectedAccountId,
                                    decoration: InputDecoration(
                                      hintText: 'Default ${_method == PaymentMethod.cash ? "Cash on Hand" : "Bank Account"}',
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: const BorderSide(color: BillzoColors.border),
                                      ),
                                    ),
                                    items: accounts.map((a) {
                                      return DropdownMenuItem<String>(
                                        value: a.id,
                                        child: Text(
                                          '${a.name} (Bal: ₹${(a.currentBalancePaise / 100.0).toStringAsFixed(2)})',
                                          style: const TextStyle(fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() => _selectedAccountId = val);
                                    },
                                  );
                                },
                                orElse: () => const LinearProgressIndicator(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Amount (₹)
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Amount Paid (₹) *',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: BillzoColors.darkSlate,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _amountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                decoration: InputDecoration(
                                  prefixText: '₹ ',
                                  hintText: '0.00',
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: BillzoColors.border),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row 3: Reference & Notes
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _refNumberController,
                            decoration: InputDecoration(
                              labelText: 'Cheque / UTR / Reference #',
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: BillzoColors.border),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _notesController,
                            decoration: InputDecoration(
                              labelText: 'Notes / Remarks',
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: BillzoColors.border),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Outstanding Purchase Bills Table
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Allocate to Outstanding Purchase Bills',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: BillzoColors.darkSlate,
                          ),
                        ),
                        if (_outstandingPurchases.isNotEmpty)
                          TextButton.icon(
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: const Text('Auto-Allocate FIFO'),
                            onPressed: _onAmountChanged,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_isLoadingPurchases) ...[
                      const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                    ] else if (_outstandingPurchases.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: BillzoColors.canvasLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: BillzoColors.border),
                        ),
                        child: Center(
                          child: Text(
                            _supplier == null
                                ? 'Select a supplier above to see unpaid purchase bills.'
                                : 'No unpaid purchase bills found for this supplier.',
                            style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText),
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: BillzoColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Table(
                          columnWidths: const {
                            0: FlexColumnWidth(2.5),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(2),
                            3: FlexColumnWidth(2),
                            4: FlexColumnWidth(2.5),
                          },
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(
                                color: BillzoColors.canvasLight,
                                border: Border(bottom: BorderSide(color: BillzoColors.border)),
                              ),
                              children: [
                                _tableHeader('Purchase Bill #'),
                                _tableHeader('Bill Date'),
                                _tableHeader('Bill Total'),
                                _tableHeader('Balance Due'),
                                _tableHeader('Amount to Allocate (₹)'),
                              ],
                            ),
                            ..._outstandingPurchases.map((purchase) {
                              final controller = _allocationControllers[purchase.id];
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
                                        Text(
                                          purchase.purchaseNumber,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        if (purchase.supplierInvoiceNumber != null) ...[
                                          Text(
                                            'Inv: ${purchase.supplierInvoiceNumber}',
                                            style: const TextStyle(
                                                fontSize: 11, color: BillzoColors.neutralText),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      dateFormat.format(purchase.purchaseDate),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      Money.formatPaise(purchase.totalAmountPaise),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      Money.formatPaise(purchase.balanceAmountPaise),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: BillzoColors.dangerRed,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: TextField(
                                      controller: controller,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        prefixText: '₹ ',
                                        hintText: '0.00',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Allocation Summary Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: BillzoColors.canvasLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: BillzoColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _summaryMetric('Total Paid', Money.formatPaise(_enteredAmountPaise), BillzoColors.darkSlate),
                          _summaryMetric('Total Allocated', Money.formatPaise(_totalAllocatedPaise), BillzoColors.primaryBlue),
                          _summaryMetric('Unallocated', Money.formatPaise(_unallocatedPaise), BillzoColors.accentOrange),
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
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => _submit(isDraft: true),
                    child: const Text('Save Draft'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: _isSubmitting ? null : () => _submit(isDraft: false),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Post Payment', style: TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _summaryMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
