import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/screens/sales/customer_select_dialog.dart';

/// Modal dialog for recording or editing a customer payment with invoice allocation.
class PaymentFormDialog extends ConsumerStatefulWidget {
  final Business business;
  final Party? preselectedCustomer;
  final Invoice? preselectedInvoice;
  final int? prefilledAmountPaise;

  const PaymentFormDialog({
    super.key,
    required this.business,
    this.preselectedCustomer,
    this.preselectedInvoice,
    this.prefilledAmountPaise,
  });

  static Future<Payment?> show(
    BuildContext context, {
    required Business business,
    Party? preselectedCustomer,
    Invoice? preselectedInvoice,
    int? prefilledAmountPaise,
  }) {
    return showDialog<Payment>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PaymentFormDialog(
        business: business,
        preselectedCustomer: preselectedCustomer,
        preselectedInvoice: preselectedInvoice,
        prefilledAmountPaise: prefilledAmountPaise,
      ),
    );
  }

  @override
  ConsumerState<PaymentFormDialog> createState() => _PaymentFormDialogState();
}

class _PaymentFormDialogState extends ConsumerState<PaymentFormDialog> {
  Party? _customer;
  DateTime _paymentDate = DateTime.now();
  PaymentMethod _method = PaymentMethod.cash;
  String? _selectedAccountId;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _refNumberController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<Invoice> _outstandingInvoices = [];
  final Map<String, TextEditingController> _allocationControllers = {};
  bool _isLoadingInvoices = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _customer = widget.preselectedCustomer;

    if (widget.prefilledAmountPaise != null) {
      _amountController.text =
          (widget.prefilledAmountPaise! / 100.0).toStringAsFixed(2);
    } else if (widget.preselectedInvoice != null) {
      _amountController.text =
          (widget.preselectedInvoice!.balanceAmountPaise / 100.0)
              .toStringAsFixed(2);
    }

    _amountController.addListener(_onAmountChanged);

    if (_customer != null) {
      _loadCustomerInvoices(_customer!.id);
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

  void _onAmountChanged() {
    setState(() {});
  }

  Future<void> _loadCustomerInvoices(String customerId) async {
    setState(() {
      _isLoadingInvoices = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(paymentServiceProvider);
      final invoices = await service.getOutstandingInvoicesForCustomer(
        widget.business.id,
        customerId,
      );

      // Clean up previous controllers
      for (final c in _allocationControllers.values) {
        c.dispose();
      }
      _allocationControllers.clear();

      for (final inv in invoices) {
        final ctrl = TextEditingController(text: '0.00');
        ctrl.addListener(() => setState(() {}));
        _allocationControllers[inv.id] = ctrl;
      }

      setState(() {
        _outstandingInvoices = invoices;
        _isLoadingInvoices = false;
      });

      // If preselected invoice, prefill allocation
      if (widget.preselectedInvoice != null &&
          _allocationControllers.containsKey(widget.preselectedInvoice!.id)) {
        final targetAlloc = widget.prefilledAmountPaise ??
            widget.preselectedInvoice!.balanceAmountPaise;
        _allocationControllers[widget.preselectedInvoice!.id]!.text =
            (targetAlloc / 100.0).toStringAsFixed(2);
      }
    } catch (e) {
      setState(() {
        _isLoadingInvoices = false;
        _errorMessage = 'Failed to load outstanding invoices: $e';
      });
    }
  }

  int get _enteredAmountPaise {
    final text = _amountController.text.trim();
    if (text.isEmpty) return 0;
    final val = double.tryParse(text) ?? 0.0;
    return Money.fromRupees(val).paise;
  }

  int get _totalAllocatedPaise {
    int sum = 0;
    for (final ctrl in _allocationControllers.values) {
      final val = double.tryParse(ctrl.text.trim()) ?? 0.0;
      sum += Money.fromRupees(val).paise;
    }
    return sum;
  }

  int get _unallocatedPaise => _enteredAmountPaise - _totalAllocatedPaise;

  void _autoAllocate() {
    final total = _enteredAmountPaise;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a payment amount first.')),
      );
      return;
    }

    final service = ref.read(paymentServiceProvider);
    final autoAllocs = service.autoAllocateAmount(
      amountPaise: total,
      outstandingInvoices: _outstandingInvoices,
    );

    // Reset all to 0
    for (final ctrl in _allocationControllers.values) {
      ctrl.text = '0.00';
    }

    // Apply auto allocations
    for (final a in autoAllocs) {
      if (_allocationControllers.containsKey(a.documentId)) {
        _allocationControllers[a.documentId]!.text =
            (a.allocatedAmountPaise / 100.0).toStringAsFixed(2);
      }
    }

    setState(() {});
  }

  void _clearAllocations() {
    for (final ctrl in _allocationControllers.values) {
      ctrl.text = '0.00';
    }
    setState(() {});
  }

  Future<void> _submit({bool isDraft = false}) async {
    setState(() => _errorMessage = null);

    if (_customer == null) {
      setState(() => _errorMessage = 'Please select a customer.');
      return;
    }

    if (_enteredAmountPaise <= 0) {
      setState(() => _errorMessage = 'Payment amount must be greater than zero.');
      return;
    }

    if (_totalAllocatedPaise > _enteredAmountPaise) {
      setState(() => _errorMessage =
          'Total allocated amount (₹${Money.fromPaise(_totalAllocatedPaise).toIndianRupeeString()}) cannot exceed the payment amount.');
      return;
    }

    final List<PaymentAllocation> allocations = [];
    final now = DateTime.now().toUtc();

    for (final inv in _outstandingInvoices) {
      final ctrl = _allocationControllers[inv.id];
      if (ctrl != null) {
        final amt = Money.fromRupees(double.tryParse(ctrl.text.trim()) ?? 0.0).paise;
        if (amt > 0) {
          if (amt > inv.balanceAmountPaise) {
            setState(() => _errorMessage =
                'Allocation for invoice ${inv.invoiceNumber} exceeds outstanding balance.');
            return;
          }
          allocations.add(
            PaymentAllocation(
              id: '',
              paymentId: '',
              documentId: inv.id,
              documentType: 'TAX_INVOICE',
              allocatedAmountPaise: amt,
              invoiceNumber: inv.invoiceNumber,
              invoiceDate: inv.invoiceDate,
              invoiceTotalPaise: inv.totalAmountPaise,
              invoiceOutstandingBeforePaise: inv.balanceAmountPaise,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(paymentServiceProvider);
      final payment = await service.recordPayment(
        businessId: widget.business.id,
        customerId: _customer!.id,
        customerName: _customer!.name,
        customerPhone: _customer!.phone,
        paymentDate: _paymentDate,
        paymentMethod: _method,
        amountPaise: _enteredAmountPaise,
        accountId: _selectedAccountId,
        referenceNumber: _refNumberController.text.trim().isEmpty
            ? null
            : _refNumberController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        allocations: allocations,
        isDraft: isDraft,
      );

      // Refresh list and counter
      ref.invalidate(paymentsListProvider(widget.business.id));
      ref.invalidate(paymentsCountProvider(widget.business.id));

      if (mounted) {
        Navigator.of(context).pop(payment);
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final accountsAsync = ref.watch(cashBankAccountsProvider(widget.business.id));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.payment, color: BillzoColors.primaryBlue, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Receive Customer Payment',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                          ),
                          Text(
                            widget.business.name,
                            style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                          ),
                        ],
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

              if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: BillzoColors.dangerRed.withValues(alpha: 0.1),
                    border: Border.all(color: BillzoColors.dangerRed.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: BillzoColors.dangerRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

              // Form fields
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer Picker Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Customer *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: widget.preselectedCustomer != null
                                      ? null
                                      : () async {
                                          final picked = await showDialog<Party>(
                                            context: context,
                                            builder: (_) => CustomerSelectDialog(
                                              businessId: widget.business.id,
                                            ),
                                          );
                                          if (picked != null) {
                                            setState(() => _customer = picked);
                                            _loadCustomerInvoices(picked.id);
                                          }
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: BillzoColors.border),
                                      borderRadius: BorderRadius.circular(8),
                                      color: widget.preselectedCustomer != null ? const Color(0xFFF8FAFC) : Colors.white,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.person_outline, size: 18, color: BillzoColors.neutralText),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _customer != null
                                              ? Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(_customer!.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                                    if (_customer!.phone != null)
                                                      Text('Ph: ${_customer!.phone}', style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                                                  ],
                                                )
                                              : const Text('Select Customer', style: TextStyle(color: BillzoColors.neutralText, fontSize: 13)),
                                        ),
                                        if (widget.preselectedCustomer == null)
                                          const Icon(Icons.arrow_drop_down, color: BillzoColors.neutralText),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Payment Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _paymentDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2035),
                                    );
                                    if (picked != null) setState(() => _paymentDate = picked);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: BillzoColors.border),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(dateFormat.format(_paymentDate), style: const TextStyle(fontSize: 13)),
                                        const Icon(Icons.calendar_today, size: 14, color: BillzoColors.neutralText),
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

                      // Amount, Method, and Account
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Amount Received (₹) *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _amountController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillzoColors.primaryBlue),
                                  decoration: InputDecoration(
                                    hintText: '0.00',
                                    prefixText: '₹ ',
                                    prefixStyle: const TextStyle(fontWeight: FontWeight.w700, color: BillzoColors.primaryBlue),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 6),
                                Container(
                                  height: 48,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: BillzoColors.border),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<PaymentMethod>(
                                      value: _method,
                                      isExpanded: true,
                                      items: PaymentMethod.values.map((m) {
                                        return DropdownMenuItem(
                                          value: m,
                                          child: Row(
                                            children: [
                                              Icon(m.icon, size: 16, color: BillzoColors.neutralText),
                                              const SizedBox(width: 8),
                                              Text(m.displayName, style: const TextStyle(fontSize: 13)),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) setState(() => _method = val);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Deposit To Account', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 6),
                                accountsAsync.when(
                                  data: (accounts) {
                                    if (_selectedAccountId == null && accounts.isNotEmpty) {
                                      final def = accounts.firstWhere(
                                        (a) => _method.isBankSettled ? a.isBank : a.isCash,
                                        orElse: () => accounts.first,
                                      );
                                      _selectedAccountId = def.id;
                                    }
                                    return Container(
                                      height: 48,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: BillzoColors.border),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedAccountId,
                                          isExpanded: true,
                                          items: accounts.map((a) {
                                            return DropdownMenuItem(
                                              value: a.id,
                                              child: Text(
                                                '${a.name} (${a.accountType.displayName})',
                                                style: const TextStyle(fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (id) => setState(() => _selectedAccountId = id),
                                        ),
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox(height: 48, child: Center(child: LinearProgressIndicator())),
                                  error: (err, _) => const Text('Error loading accounts'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Reference Number & Notes
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Reference / UTR / Cheque #', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _refNumberController,
                                  decoration: InputDecoration(
                                    hintText: 'e.g. UTR12345678, CHQ-0045',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Notes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _notesController,
                                  decoration: InputDecoration(
                                    hintText: 'Remarks or memo...',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Invoice Allocation Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Allocate to Invoices',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: BillzoColors.darkSlate),
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.auto_fix_high, size: 16),
                                label: const Text('Auto-Allocate (FIFO)', style: TextStyle(fontSize: 12)),
                                onPressed: _autoAllocate,
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _clearAllocations,
                                child: const Text('Clear', style: TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_isLoadingInvoices)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_customer == null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: BillzoColors.border),
                          ),
                          child: const Center(
                            child: Text('Select a customer to view outstanding invoices.', style: TextStyle(color: BillzoColors.neutralText)),
                          ),
                        )
                      else if (_outstandingInvoices.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: BillzoColors.border),
                          ),
                          child: const Center(
                            child: Text(
                              'No outstanding invoices found for this customer. Payment can be held on account.',
                              style: TextStyle(color: BillzoColors.neutralText),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: BillzoColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Table(
                            columnWidths: const {
                              0: FlexColumnWidth(2.5),
                              1: FlexColumnWidth(2.0),
                              2: FlexColumnWidth(2.0),
                              3: FlexColumnWidth(2.0),
                              4: FlexColumnWidth(2.5),
                              5: FixedColumnWidth(90),
                            },
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                                children: [
                                  _th('Invoice #'),
                                  _th('Date'),
                                  _th('Total', align: TextAlign.right),
                                  _th('Outstanding', align: TextAlign.right),
                                  _th('Allocate (₹)', align: TextAlign.right),
                                  _th('Quick Action', align: TextAlign.center),
                                ],
                              ),
                              for (final inv in _outstandingInvoices)
                                TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      child: Text(inv.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      child: Text(dateFormat.format(inv.invoiceDate), style: const TextStyle(fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      child: Text(
                                        '₹${inv.totalAmount.toIndianRupeeString()}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      child: Text(
                                        '₹${inv.balanceAmount.toIndianRupeeString()}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: BillzoColors.dangerRed, fontSize: 12),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: SizedBox(
                                        height: 36,
                                        child: TextField(
                                          controller: _allocationControllers[inv.id],
                                          textAlign: TextAlign.right,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                          decoration: const InputDecoration(
                                            prefixText: '₹ ',
                                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: const Text('Full Bal', style: TextStyle(fontSize: 11)),
                                        onPressed: () {
                                          if (_allocationControllers.containsKey(inv.id)) {
                                            _allocationControllers[inv.id]!.text =
                                                (inv.balanceAmountPaise / 100.0).toStringAsFixed(2);
                                          }
                                        },
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

              const SizedBox(height: 14),

              // Summary Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: BillzoColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _chip('Payment Amount', '₹${Money.fromPaise(_enteredAmountPaise).toIndianRupeeString()}', BillzoColors.primaryBlue),
                    _chip('Allocated', '₹${Money.fromPaise(_totalAllocatedPaise).toIndianRupeeString()}', BillzoColors.successGreen),
                    _chip('Unallocated (Advance)', '₹${Money.fromPaise(_unallocatedPaise).toIndianRupeeString()}', _unallocatedPaise < 0 ? BillzoColors.dangerRed : BillzoColors.accentOrange),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
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
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BillzoColors.successGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(_isSubmitting ? 'Posting...' : 'Post Payment', style: const TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: _isSubmitting ? null : () => _submit(isDraft: false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _th(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: BillzoColors.neutralText),
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
