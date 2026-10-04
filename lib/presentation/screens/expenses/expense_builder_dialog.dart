import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/expense_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';

/// Modal dialog for recording or editing an Expense.
class ExpenseBuilderDialog extends ConsumerStatefulWidget {
  final Business business;
  final Expense? expenseToEdit;

  const ExpenseBuilderDialog({
    super.key,
    required this.business,
    this.expenseToEdit,
  });

  static Future<Expense?> show(
    BuildContext context, {
    required Business business,
    Expense? expenseToEdit,
  }) {
    return showDialog<Expense>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExpenseBuilderDialog(
        business: business,
        expenseToEdit: expenseToEdit,
      ),
    );
  }

  @override
  ConsumerState<ExpenseBuilderDialog> createState() => _ExpenseBuilderDialogState();
}

class _ExpenseBuilderDialogState extends ConsumerState<ExpenseBuilderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _payeeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _expenseDate = DateTime.now();
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? _selectedPaymentAccountId;
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;

  int _selectedTaxRateBps = 0;
  bool _isTaxInclusive = false;
  bool _isInterState = false;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.expenseToEdit != null) {
      final e = widget.expenseToEdit!;
      _payeeController.text = e.payee;
      _descriptionController.text = e.description;
      _amountController.text = (e.totalAmountPaise / 100).toStringAsFixed(2);
      _referenceController.text = e.referenceNumber ?? '';
      _notesController.text = e.notes ?? '';
      _expenseDate = e.expenseDate;
      _selectedCategoryId = e.categoryId;
      _selectedCategoryName = e.categoryName;
      _selectedPaymentAccountId = e.paymentAccountId;
      _selectedPaymentMethod = e.paymentMethod;

      if (e.totalGstPaise > 0 && e.taxableAmountPaise > 0) {
        final calcRate = ((e.totalGstPaise * 10000) ~/ e.taxableAmountPaise);
        _selectedTaxRateBps = _closestTaxRateBps(calcRate);
      }
      _isInterState = e.igstPaise > 0;
    }
  }

  int _closestTaxRateBps(int approx) {
    if (approx >= 2500) return 2800;
    if (approx >= 1500) return 1800;
    if (approx >= 900) return 1200;
    if (approx >= 350) return 500;
    return 0;
  }

  @override
  void dispose() {
    _payeeController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _enteredAmountPaise {
    final text = _amountController.text.trim();
    if (text.isEmpty) return 0;
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) return 0;
    return (parsed * 100).round();
  }

  void _recalculate() {
    setState(() {});
  }

  Future<void> _handleSaveDraft() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      setState(() => _errorMessage = 'Please select an expense category');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final expenseService = ref.read(expenseServiceProvider);
      final rawAmount = _enteredAmountPaise;

      final taxCalc = expenseService.calculateExpenseTax(
        amountPaise: rawAmount,
        taxRateBasisPoints: _selectedTaxRateBps,
        isTaxInclusive: _isTaxInclusive,
        isInterState: _isInterState,
      );

      final now = DateTime.now().toUtc();
      final draftExpense = Expense(
        id: widget.expenseToEdit?.id ?? const Uuid().v4(),
        businessId: widget.business.id,
        expenseNumber: widget.expenseToEdit?.expenseNumber,
        categoryId: _selectedCategoryId!,
        categoryName: _selectedCategoryName,
        expenseDate: _expenseDate,
        payee: _payeeController.text.trim(),
        description: _descriptionController.text.trim(),
        taxableAmountPaise: taxCalc.taxableAmountPaise,
        cgstPaise: taxCalc.cgstPaise,
        sgstPaise: taxCalc.sgstPaise,
        igstPaise: taxCalc.igstPaise,
        totalGstPaise: taxCalc.totalTaxPaise,
        totalAmountPaise: taxCalc.totalAmountPaise,
        paymentAccountId: _selectedPaymentAccountId,
        paymentMethod: _selectedPaymentMethod,
        referenceNumber: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        status: ExpenseStatus.draft,
        createdAt: widget.expenseToEdit?.createdAt ?? now,
        updatedAt: now,
      );

      final saved = widget.expenseToEdit == null
          ? await expenseService.createDraft(draftExpense)
          : await expenseService.updateDraft(draftExpense);

      ref.invalidate(expensesListProvider(widget.business.id));
      ref.invalidate(expenseSummaryProvider(widget.business.id));

      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
      });
    }
  }

  Future<void> _handlePostExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      setState(() => _errorMessage = 'Please select an expense category');
      return;
    }
    if (_selectedPaymentAccountId == null) {
      setState(() => _errorMessage = 'Please select a Cash or Bank holding account');
      return;
    }
    if (_enteredAmountPaise <= 0) {
      setState(() => _errorMessage = 'Expense amount must be greater than zero to post');
      return;
    }

    // Require confirmation before posting per requirement 8
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Expense Posting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Post expense of ₹${(_enteredAmountPaise / 100).toStringAsFixed(2)} to ${_payeeController.text}?'),
            const SizedBox(height: 8),
            const Text(
              'This will allocate an official sequential expense number, post balanced double-entry accounting records, and deduct the selected payment account balance. Posted expenses cannot be edited.',
              style: TextStyle(fontSize: 13, color: BillzoColors.neutralText),
            ),
          ],
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

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final expenseService = ref.read(expenseServiceProvider);
      final rawAmount = _enteredAmountPaise;

      final taxCalc = expenseService.calculateExpenseTax(
        amountPaise: rawAmount,
        taxRateBasisPoints: _selectedTaxRateBps,
        isTaxInclusive: _isTaxInclusive,
        isInterState: _isInterState,
      );

      final now = DateTime.now().toUtc();
      final draftExpense = Expense(
        id: widget.expenseToEdit?.id ?? const Uuid().v4(),
        businessId: widget.business.id,
        categoryId: _selectedCategoryId!,
        categoryName: _selectedCategoryName,
        expenseDate: _expenseDate,
        payee: _payeeController.text.trim(),
        description: _descriptionController.text.trim(),
        taxableAmountPaise: taxCalc.taxableAmountPaise,
        cgstPaise: taxCalc.cgstPaise,
        sgstPaise: taxCalc.sgstPaise,
        igstPaise: taxCalc.igstPaise,
        totalGstPaise: taxCalc.totalTaxPaise,
        totalAmountPaise: taxCalc.totalAmountPaise,
        paymentAccountId: _selectedPaymentAccountId,
        paymentMethod: _selectedPaymentMethod,
        referenceNumber: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        status: ExpenseStatus.draft,
        createdAt: widget.expenseToEdit?.createdAt ?? now,
        updatedAt: now,
      );

      // Save draft first if new
      final savedDraft = widget.expenseToEdit == null
          ? await expenseService.createDraft(draftExpense)
          : await expenseService.updateDraft(draftExpense);

      // Post atomically
      final posted = await expenseService.postExpense(
        savedDraft.id,
        paymentAccountId: _selectedPaymentAccountId,
      );

      ref.invalidate(expensesListProvider(widget.business.id));
      ref.invalidate(expenseSummaryProvider(widget.business.id));
      ref.invalidate(cashBankAccountsProvider(widget.business.id));

      if (mounted) {
        Navigator.of(context).pop(posted);
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
      });
    }
  }

  void _showAddCustomCategoryDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Custom Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Category Name',
                hintText: 'e.g. Software Subscriptions',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx).pop();

              final service = ref.read(expenseServiceProvider);
              final now = DateTime.now().toUtc();
              final cat = ExpenseCategory(
                id: const Uuid().v4(),
                businessId: widget.business.id,
                name: name,
                accountCode: '5199',
                isPredefined: false,
                isActive: true,
                createdAt: now,
                updatedAt: now,
              );
              await service.createCategory(cat);
              ref.invalidate(expenseCategoriesProvider(widget.business.id));
              setState(() {
                _selectedCategoryId = cat.id;
                _selectedCategoryName = cat.name;
              });
            },
            child: const Text('Save Category'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider(widget.business.id));
    final accountsAsync = ref.watch(cashBankAccountsProvider(widget.business.id));
    final expenseService = ref.watch(expenseServiceProvider);

    // Live calculation
    final rawAmount = _enteredAmountPaise;
    final taxCalc = expenseService.calculateExpenseTax(
      amountPaise: rawAmount,
      taxRateBasisPoints: _selectedTaxRateBps,
      isTaxInclusive: _isTaxInclusive,
      isInterState: _isInterState,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.expenseToEdit == null ? 'Record Expense' : 'Edit Expense Draft',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BillzoColors.dangerRed.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: BillzoColors.dangerRed.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: BillzoColors.dangerRed, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              // Form fields scrollable area
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Row 1: Category & Expense Date
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Category Dropdown
                            Expanded(
                              flex: 3,
                              child: categoriesAsync.when(
                                loading: () => const LinearProgressIndicator(),
                                error: (e, _) => Text('Error loading categories: $e'),
                                data: (categories) {
                                  // Ensure selection exists in list
                                  if (_selectedCategoryId == null && categories.isNotEmpty) {
                                    _selectedCategoryId = categories.first.id;
                                    _selectedCategoryName = categories.first.name;
                                  }

                                  return DropdownButtonFormField<String>(
                                    initialValue: _selectedCategoryId,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'Expense Category *',
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 20),
                                        tooltip: 'Add Custom Category',
                                        onPressed: _showAddCustomCategoryDialog,
                                      ),
                                    ),
                                    items: categories.map((cat) {
                                      return DropdownMenuItem(
                                        value: cat.id,
                                        child: Text(cat.name, overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedCategoryId = val;
                                        final found = categories.firstWhere((c) => c.id == val);
                                        _selectedCategoryName = found.name;
                                      });
                                    },
                                    validator: (v) => v == null ? 'Category is required' : null,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Date Picker Field
                            Expanded(
                              flex: 2,
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _expenseDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) {
                                    setState(() => _expenseDate = picked);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Expense Date *',
                                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                                  ),
                                  child: Text(
                                    DateFormat('dd MMM yyyy').format(_expenseDate),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Row 2: Payee / Vendor & Description
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _payeeController,
                                decoration: const InputDecoration(
                                  labelText: 'Payee / Vendor Name *',
                                  hintText: 'e.g. Reliance Energy, Landlord, Swiggy',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Payee is required' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _descriptionController,
                                decoration: const InputDecoration(
                                  labelText: 'Description / Purpose',
                                  hintText: 'e.g. Office electricity bill for September',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Row 3: Amount, GST Rate, Inclusive/Exclusive, Interstate
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Base Amount
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _amountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Amount (₹) *',
                                  prefixText: '₹ ',
                                  hintText: '0.00',
                                ),
                                onChanged: (_) => _recalculate(),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Amount required';
                                  final num = double.tryParse(v);
                                  if (num == null || num <= 0) return 'Invalid amount';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            // GST Rate Dropdown
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                initialValue: _selectedTaxRateBps,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'GST Slab'),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('0% (Exempt/Nil)')),
                                  DropdownMenuItem(value: 500, child: Text('5% GST')),
                                  DropdownMenuItem(value: 1200, child: Text('12% GST')),
                                  DropdownMenuItem(value: 1800, child: Text('18% GST')),
                                  DropdownMenuItem(value: 2800, child: Text('28% GST')),
                                ],
                                onChanged: (val) {
                                  setState(() => _selectedTaxRateBps = val ?? 0);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Toggles
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckboxListTile(
                                    title: const Text('Tax Inclusive', style: TextStyle(fontSize: 13)),
                                    value: _isTaxInclusive,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    onChanged: (val) {
                                      setState(() => _isTaxInclusive = val ?? false);
                                    },
                                  ),
                                  CheckboxListTile(
                                    title: const Text('Inter-state (IGST)', style: TextStyle(fontSize: 13)),
                                    value: _isInterState,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    onChanged: (val) {
                                      setState(() => _isInterState = val ?? false);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Row 4: Payment Method, Cash/Bank Holding Account, Reference
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Payment Method
                            Expanded(
                              child: DropdownButtonFormField<PaymentMethod>(
                                initialValue: _selectedPaymentMethod,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Payment Method *'),
                                items: PaymentMethod.values.map((m) {
                                  return DropdownMenuItem(
                                    value: m,
                                    child: Text(m.displayName, overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedPaymentMethod = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Payment Account
                            Expanded(
                              flex: 2,
                              child: accountsAsync.when(
                                loading: () => const LinearProgressIndicator(),
                                error: (e, _) => Text('Error loading accounts: $e'),
                                data: (accounts) {
                                  if (_selectedPaymentAccountId == null && accounts.isNotEmpty) {
                                    final def = accounts.firstWhere(
                                      (a) => _selectedPaymentMethod.isBankSettled ? a.isBank : a.isCash,
                                      orElse: () => accounts.first,
                                    );
                                    _selectedPaymentAccountId = def.id;
                                  }

                                  return DropdownButtonFormField<String>(
                                    initialValue: _selectedPaymentAccountId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Paid From Account (Cash / Bank) *',
                                    ),
                                    items: accounts.map((acc) {
                                      return DropdownMenuItem(
                                        value: acc.id,
                                        child: Text(
                                          '${acc.name} (${acc.accountType.displayName}) — Bal: ₹${(acc.currentBalancePaise / 100).toStringAsFixed(2)}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) => setState(() => _selectedPaymentAccountId = val),
                                    validator: (v) => v == null ? 'Account required' : null,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Reference Number
                            Expanded(
                              child: TextFormField(
                                controller: _referenceController,
                                decoration: const InputDecoration(
                                  labelText: 'Ref / Voucher #',
                                  hintText: 'e.g. UTR-12849, CHQ-001',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Notes field
                        TextFormField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Notes / Remarks',
                            hintText: 'Optional internal expense notes',
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Live Tax & Total Calculation Card
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Taxable Amount:', style: TextStyle(fontSize: 13, color: BillzoColors.neutralText)),
                                  Text(
                                    Money.fromPaise(taxCalc.taxableAmountPaise).formatted,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              if (taxCalc.cgstPaise > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('CGST:', style: TextStyle(fontSize: 13, color: BillzoColors.neutralText)),
                                    Text(
                                      Money.fromPaise(taxCalc.cgstPaise).formatted,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                              if (taxCalc.sgstPaise > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('SGST:', style: TextStyle(fontSize: 13, color: BillzoColors.neutralText)),
                                    Text(
                                      Money.fromPaise(taxCalc.sgstPaise).formatted,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                              if (taxCalc.igstPaise > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('IGST:', style: TextStyle(fontSize: 13, color: BillzoColors.neutralText)),
                                    Text(
                                      Money.fromPaise(taxCalc.igstPaise).formatted,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Expense Amount:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                  Text(
                                    Money.fromPaise(taxCalc.totalAmountPaise).formatted,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: BillzoColors.primaryBlue,
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
              ),

              const SizedBox(height: 16),
              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _handleSaveDraft,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save Draft'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _handlePostExpense,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Post Expense'),
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
