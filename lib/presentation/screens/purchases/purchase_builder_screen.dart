import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/invoice/discount_engine.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/domain/purchase/purchase_validator.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/providers/purchase_providers.dart';
import 'package:billzo/presentation/screens/purchases/supplier_select_dialog.dart';
import 'package:billzo/presentation/screens/sales/product_select_dialog.dart';

/// Screen for creating and editing purchase bills with real-time tax/ITC calculations.
class PurchaseBuilderScreen extends ConsumerStatefulWidget {
  final Business business;
  final Purchase? purchaseToEdit;

  const PurchaseBuilderScreen({
    super.key,
    required this.business,
    this.purchaseToEdit,
  });

  @override
  ConsumerState<PurchaseBuilderScreen> createState() => _PurchaseBuilderScreenState();
}

class _PurchaseItemDraft {
  final String id;
  String? productId;
  String description;
  String? hsnSac;
  int quantityScaled;
  String unit;
  int ratePaise;
  DiscountType discountType;
  num discountValue;
  int taxRateBasisPoints;
  ItcEligibility itcEligibility;
  bool isTaxInclusive = false;

  // Controllers
  final TextEditingController descController;
  final TextEditingController hsnController;
  final TextEditingController qtyController;
  final TextEditingController rateController;
  final TextEditingController discountController;

  _PurchaseItemDraft({
    required this.id,
    this.productId,
    this.description = '',
    this.hsnSac,
    this.quantityScaled = 1000,
    this.unit = 'PCS',
    this.ratePaise = 0,
    this.discountType = DiscountType.percentage,
    this.discountValue = 0,
    this.taxRateBasisPoints = 1800,
    this.itcEligibility = ItcEligibility.eligible,
  })  : descController = TextEditingController(text: description),
        hsnController = TextEditingController(text: hsnSac ?? ''),
        qtyController = TextEditingController(
          text: (quantityScaled / 1000.0).toStringAsFixed(quantityScaled % 1000 == 0 ? 0 : 3),
        ),
        rateController = TextEditingController(
          text: ratePaise > 0 ? (ratePaise / 100.0).toStringAsFixed(2) : '',
        ),
        discountController = TextEditingController(
          text: discountValue > 0 ? discountValue.toString() : '',
        );

  void dispose() {
    descController.dispose();
    hsnController.dispose();
    qtyController.dispose();
    rateController.dispose();
    discountController.dispose();
  }
}

class _PurchaseBuilderScreenState extends ConsumerState<PurchaseBuilderScreen> {
  final Uuid _uuid = const Uuid();
  Party? _supplier;
  final TextEditingController _supplierInvoiceNoController = TextEditingController();
  DateTime? _supplierInvoiceDate;
  DateTime _purchaseDate = DateTime.now();
  DateTime? _dueDate;
  final TextEditingController _notesController = TextEditingController();

  final List<_PurchaseItemDraft> _items = [];
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isDuplicateSupplierInvoice = false;

  final List<int> _taxRatesBps = [0, 500, 1200, 1800, 2800];

  @override
  void initState() {
    super.initState();
    _dueDate = DateTime.now().add(const Duration(days: 30));
    _supplierInvoiceDate = DateTime.now();

    if (widget.purchaseToEdit != null) {
      _initFromExisting(widget.purchaseToEdit!);
    } else {
      _addNewItem();
    }

    _supplierInvoiceNoController.addListener(_onSupplierInvoiceNoChanged);
  }

  void _initFromExisting(Purchase p) async {
    _supplierInvoiceNoController.text = p.supplierInvoiceNumber ?? '';
    _supplierInvoiceDate = p.supplierInvoiceDate;
    _purchaseDate = p.purchaseDate;
    _dueDate = p.dueDate;
    _notesController.text = p.notes ?? '';

    // Load supplier party
    final partyRepo = ref.read(partyRepositoryProvider);
    final supplierParty = await partyRepo.getPartyById(p.supplierId);
    if (mounted) setState(() => _supplier = supplierParty);

    _items.clear();
    for (final item in p.items) {
      final draft = _PurchaseItemDraft(
        id: item.id,
        productId: item.productId,
        description: item.description ?? item.productName,
        hsnSac: item.hsnSac,
        quantityScaled: item.quantityScaled,
        unit: item.unit,
        ratePaise: item.ratePaise,
        discountType: item.discountPaise > 0 ? DiscountType.fixed : DiscountType.percentage,
        discountValue: item.discountPaise > 0 ? (item.discountPaise / 100.0) : 0,
        taxRateBasisPoints: item.taxRateBasisPoints,
        itcEligibility: item.isItcEligible ? ItcEligibility.eligible : ItcEligibility.ineligible,
      );
      _items.add(draft);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _supplierInvoiceNoController.removeListener(_onSupplierInvoiceNoChanged);
    _supplierInvoiceNoController.dispose();
    _notesController.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _onSupplierInvoiceNoChanged() async {
    final invNo = _supplierInvoiceNoController.text.trim();
    if (invNo.isEmpty || _supplier == null) {
      if (_isDuplicateSupplierInvoice) {
        setState(() => _isDuplicateSupplierInvoice = false);
      }
      return;
    }

    final service = ref.read(purchaseServiceProvider);
    final isDup = await service.checkDuplicateSupplierInvoice(
      businessId: widget.business.id,
      supplierId: _supplier!.id,
      supplierInvoiceNumber: invNo,
      excludePurchaseId: widget.purchaseToEdit?.id,
    );

    if (mounted && isDup != _isDuplicateSupplierInvoice) {
      setState(() => _isDuplicateSupplierInvoice = isDup);
    }
  }

  void _addNewItem() {
    setState(() {
      _items.add(_PurchaseItemDraft(id: _uuid.v4()));
    });
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  void _onProductPicked(_PurchaseItemDraft itemDraft) async {
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => ProductSelectDialog(businessId: widget.business.id),
    );

    if (product != null && mounted) {
      setState(() {
        itemDraft.productId = product.id;
        itemDraft.description = product.name;
        itemDraft.descController.text = product.name;
        itemDraft.hsnSac = product.hsnCode;
        itemDraft.hsnController.text = product.hsnCode ?? '';
        itemDraft.unit = product.unit;
        // Purchase cost
        if (product.purchasePricePaise > 0) {
          itemDraft.ratePaise = product.purchasePricePaise;
          itemDraft.rateController.text = (product.purchasePricePaise / 100.0).toStringAsFixed(2);
        }
      });
    }
  }

  bool get _isInterState {
    final supplierState = (_supplier?.billingStateCode ?? _supplier?.billingStateName)?.toLowerCase().trim();
    final businessState = widget.business.stateCode.toLowerCase().trim();
    if (supplierState == null) return false;
    return supplierState != businessState;
  }

  LineTaxBreakdown _calculateLineTax(_PurchaseItemDraft item) {
    final service = ref.read(purchaseServiceProvider);

    int cgstBps = 0;
    int sgstBps = 0;
    int igstBps = 0;

    if (_isInterState) {
      igstBps = item.taxRateBasisPoints;
    } else {
      cgstBps = item.taxRateBasisPoints ~/ 2;
      sgstBps = item.taxRateBasisPoints ~/ 2;
    }

    return service.calculateLine(
      rateOrMrpPaise: item.ratePaise,
      quantityScaled: item.quantityScaled,
      discountType: item.discountType,
      discountValue: item.discountValue,
      rateBasisPoints: item.taxRateBasisPoints,
      cgstBasisPoints: cgstBps,
      sgstBasisPoints: sgstBps,
      igstBasisPoints: igstBps,
      isTaxInclusive: item.isTaxInclusive,
      isInterState: _isInterState,
    );
  }

  InvoiceTaxCalculation get _totals {
    final service = ref.read(purchaseServiceProvider);
    final lines = _items.map(_calculateLineTax).toList();
    return service.calculatePurchaseTotals(lines: lines, enableRoundOff: true);
  }

  int get _eligibleItcPaise {
    int total = 0;
    for (final item in _items) {
      if (item.itcEligibility == ItcEligibility.eligible) {
        final lineTax = _calculateLineTax(item);
        total += lineTax.totalTaxAmountPaise;
      }
    }
    return total;
  }

  int get _ineligibleItcPaise {
    int total = 0;
    for (final item in _items) {
      if (item.itcEligibility == ItcEligibility.ineligible) {
        final lineTax = _calculateLineTax(item);
        total += lineTax.totalTaxAmountPaise;
      }
    }
    return total;
  }

  Future<void> _submit({required bool finalize}) async {
    setState(() => _errorMessage = null);

    if (_supplier == null) {
      setState(() => _errorMessage = 'Please select a supplier for this purchase bill.');
      return;
    }

    final supplierInvNo = _supplierInvoiceNoController.text.trim();
    if (finalize && supplierInvNo.isEmpty) {
      setState(() => _errorMessage = 'Supplier invoice number is mandatory for finalized bills.');
      return;
    }

    // Check items
    final now = DateTime.now().toUtc();
    final List<PurchaseItem> domainItems = [];
    for (final draft in _items) {
      if (draft.description.trim().isEmpty) {
        setState(() => _errorMessage = 'All purchase items must have a description or product name.');
        return;
      }
      if (draft.quantityScaled <= 0) {
        setState(() => _errorMessage = 'Item "${draft.description}" must have quantity greater than zero.');
        return;
      }
      if (draft.ratePaise < 0) {
        setState(() => _errorMessage = 'Item "${draft.description}" cannot have negative rate.');
        return;
      }

      final lineCalc = _calculateLineTax(draft);
      domainItems.add(
        PurchaseItem(
          id: draft.id.isEmpty ? _uuid.v4() : draft.id,
          purchaseId: widget.purchaseToEdit?.id ?? '',
          productId: draft.productId ?? '',
          productName: draft.description.trim(),
          description: draft.description.trim(),
          hsnSac: draft.hsnSac?.trim().isEmpty ?? true ? null : draft.hsnSac!.trim(),
          quantityScaled: draft.quantityScaled,
          unitCode: draft.unit,
          purchaseRatePaise: draft.ratePaise,
          discountPaise: lineCalc.discountPaise,
          taxableAmountPaise: lineCalc.taxableAmountPaise,
          taxRateId: 'DEFAULT',
          rateBasisPoints: draft.taxRateBasisPoints,
          cgstRateBasisPoints: lineCalc.cgstRateBasisPoints,
          cgstAmountPaise: lineCalc.cgstAmountPaise,
          sgstRateBasisPoints: lineCalc.sgstRateBasisPoints,
          sgstAmountPaise: lineCalc.sgstAmountPaise,
          igstRateBasisPoints: lineCalc.igstRateBasisPoints,
          igstAmountPaise: lineCalc.igstAmountPaise,
          totalAmountPaise: lineCalc.lineTotalPaise,
          isItcEligible: draft.itcEligibility == ItcEligibility.eligible,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final totals = _totals;

    final purchase = Purchase(
      id: widget.purchaseToEdit?.id ?? _uuid.v4(),
      businessId: widget.business.id,
      supplierId: _supplier!.id,
      supplierName: _supplier!.name,
      supplierGstin: _supplier!.gstin,
      purchaseNumber: widget.purchaseToEdit?.purchaseNumber ?? (finalize ? '' : 'DRAFT'),
      supplierInvoiceNumber: supplierInvNo.isEmpty ? null : supplierInvNo,
      supplierInvoiceDate: _supplierInvoiceDate ?? _purchaseDate,
      purchaseDate: _purchaseDate,
      dueDate: _dueDate ?? _purchaseDate.add(const Duration(days: 30)),
      placeOfSupplyStateCode: _supplier?.billingStateCode ?? widget.business.stateCode,
      subtotalPaise: totals.subtotalPaise,
      discountPaise: totals.discountPaise,
      taxableAmountPaise: totals.taxableAmountPaise,
      cgstPaise: totals.cgstPaise,
      sgstPaise: totals.sgstPaise,
      igstPaise: totals.igstPaise,
      roundOffPaise: totals.roundOffPaise,
      totalAmountPaise: totals.totalAmountPaise,
      paidAmountPaise: widget.purchaseToEdit?.paidAmountPaise ?? 0,
      balanceAmountPaise: totals.totalAmountPaise - (widget.purchaseToEdit?.paidAmountPaise ?? 0),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      status: finalize ? PurchaseStatus.finalized : PurchaseStatus.draft,
      items: domainItems,
      createdAt: widget.purchaseToEdit?.createdAt ?? now,
      updatedAt: now,
      finalizedAt: finalize ? now : null,
    );

    // Validate invariants
    final validation = PurchaseValidator.validate(purchase);
    if (validation.hasErrors) {
      setState(() => _errorMessage = validation.firstError);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(purchaseServiceProvider);
      if (finalize) {
        await service.finalizePurchase(purchase);
      } else {
        if (widget.purchaseToEdit != null) {
          await service.updateDraft(purchase);
        } else {
          await service.saveDraft(purchase);
        }
      }

      ref.invalidate(purchasesListProvider);
      ref.invalidate(partiesListProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(finalize ? 'Purchase bill finalized successfully!' : 'Purchase draft saved.'),
            backgroundColor: finalize ? BillzoColors.successGreen : BillzoColors.primaryBlue,
          ),
        );
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
    final totals = _totals;

    return Scaffold(
      backgroundColor: BillzoColors.canvasLight,
      appBar: AppBar(
        backgroundColor: BillzoColors.cardSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.purchaseToEdit != null ? 'Edit Purchase Bill (Draft)' : 'New Purchase Bill',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: BillzoColors.darkSlate),
        ),
        actions: [
          OutlinedButton(
            onPressed: _isSubmitting ? null : () => _submit(finalize: false),
            child: const Text('Save Draft'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: BillzoColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: _isSubmitting ? null : () => _submit(finalize: true),
            icon: const Icon(Icons.check, size: 18),
            label: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Finalize Purchase', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: SingleChildScrollView(
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

            // Duplicate Supplier Invoice Warning Banner
            if (_isDuplicateSupplierInvoice) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: BillzoColors.accentOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BillzoColors.accentOrange.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: BillzoColors.accentOrange, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Warning: A purchase bill with this supplier invoice number already exists for this supplier.',
                        style: TextStyle(color: BillzoColors.darkSlate, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Section 1: Supplier & Dates Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: BillzoColors.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BillzoColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Supplier & Invoice Information',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Supplier Picker
                      Expanded(
                        flex: 3,
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDialog<Party>(
                              context: context,
                              builder: (_) => SupplierSelectDialog(businessId: widget.business.id),
                            );
                            if (picked != null) {
                              setState(() => _supplier = picked);
                              _onSupplierInvoiceNoChanged();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: BillzoColors.border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.people_outline, color: BillzoColors.primaryBlue, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _supplier?.name ?? 'Click to select Supplier *',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: _supplier != null ? BillzoColors.darkSlate : BillzoColors.primaryBlue,
                                        ),
                                      ),
                                      if (_supplier?.gstin != null) ...[
                                        Text('GSTIN: ${_supplier!.gstin}', style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                                      ],
                                      if (_supplier != null) ...[
                                        Text(
                                          'Current Payable: ${Money.formatPaise(_supplier!.currentBalancePaise)}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillzoColors.dangerRed),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down, color: BillzoColors.neutralText),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Supplier Invoice #
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _supplierInvoiceNoController,
                          decoration: InputDecoration(
                            labelText: 'Supplier Invoice # *',
                            hintText: 'e.g. INV-98421',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Supplier Invoice Date
                      Expanded(
                        flex: 2,
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _supplierInvoiceDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) setState(() => _supplierInvoiceDate = picked);
                          },
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: BillzoColors.border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Supplier Invoice Date', style: TextStyle(fontSize: 10, color: BillzoColors.neutralText)),
                                    Text(
                                      _supplierInvoiceDate != null ? dateFormat.format(_supplierInvoiceDate!) : 'Pick Date',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.calendar_today, size: 16, color: BillzoColors.neutralText),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      // Purchase Date
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _purchaseDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) setState(() => _purchaseDate = picked);
                          },
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: BillzoColors.border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Bill Entry Date', style: TextStyle(fontSize: 10, color: BillzoColors.neutralText)),
                                    Text(dateFormat.format(_purchaseDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const Icon(Icons.calendar_today, size: 16, color: BillzoColors.neutralText),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Due Date
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) setState(() => _dueDate = picked);
                          },
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: BillzoColors.border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Payment Due Date', style: TextStyle(fontSize: 10, color: BillzoColors.neutralText)),
                                    Text(
                                      _dueDate != null ? dateFormat.format(_dueDate!) : 'Not Set',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.event_available, size: 16, color: BillzoColors.neutralText),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Supply Type Indicator
                      Expanded(
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: BillzoColors.canvasLight,
                            border: Border.all(color: BillzoColors.border),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isInterState ? Icons.public : Icons.location_on_outlined,
                                size: 18,
                                color: BillzoColors.primaryBlue,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('GST Supply Type', style: TextStyle(fontSize: 10, color: BillzoColors.neutralText)),
                                  Text(
                                    _isInterState ? 'Inter-state (IGST)' : 'Intra-state (CGST + SGST)',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Section 2: Items Table Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: BillzoColors.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BillzoColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Items & Line Totals',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BillzoColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Row'),
                        onPressed: _addNewItem,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: BillzoColors.canvasLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 4, child: Text('Item / Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('HSN/SAC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('Qty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('Unit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('Rate (₹)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('Tax %', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('ITC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('Line Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        SizedBox(width: 36),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Table Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final item = _items[idx];
                      final lineCalc = _calculateLineTax(item);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: BillzoColors.border),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Description / Product picker
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.inventory_2_outlined, size: 18, color: BillzoColors.primaryBlue),
                                    tooltip: 'Pick from Catalog',
                                    onPressed: () => _onProductPicked(item),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: item.descController,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        hintText: 'Item name or description',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) => item.description = val,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // HSN
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: item.hsnController,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'HSN',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) => item.hsnSac = val,
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Quantity
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: item.qtyController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: '1',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) {
                                  final numVal = double.tryParse(val) ?? 0;
                                  setState(() => item.quantityScaled = (numVal * 1000).round());
                                },
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Unit
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: TextEditingController(text: item.unit),
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'PCS',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) => item.unit = val.toUpperCase().trim(),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Rate
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: item.rateController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                decoration: const InputDecoration(
                                  prefixText: '₹ ',
                                  hintText: '0.00',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) {
                                  final numVal = double.tryParse(val) ?? 0;
                                  setState(() => item.ratePaise = (numVal * 100).round());
                                },
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Tax Rate %
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                initialValue: item.taxRateBasisPoints,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                                items: _taxRatesBps.map((bps) {
                                  return DropdownMenuItem(
                                    value: bps,
                                    child: Text('${(bps / 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => item.taxRateBasisPoints = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),

                            // ITC Eligibility toggle
                            Expanded(
                              flex: 2,
                              child: Tooltip(
                                message: 'Input Tax Credit: ${item.itcEligibility.displayName}',
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      item.itcEligibility = item.itcEligibility == ItcEligibility.eligible
                                          ? ItcEligibility.ineligible
                                          : ItcEligibility.eligible;
                                    });
                                  },
                                  child: Container(
                                    height: 34,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: item.itcEligibility == ItcEligibility.eligible
                                          ? BillzoColors.successGreen.withValues(alpha: 0.1)
                                          : BillzoColors.neutralText.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.itcEligibility == ItcEligibility.eligible ? 'ITC YES' : 'NO ITC',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: item.itcEligibility == ItcEligibility.eligible
                                            ? BillzoColors.successGreen
                                            : BillzoColors.neutralText,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Line Total
                            Expanded(
                              flex: 3,
                              child: Text(
                                Money.formatPaise(lineCalc.lineTotalPaise),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                                textAlign: TextAlign.right,
                              ),
                            ),

                            // Delete Action
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: BillzoColors.dangerRed),
                              tooltip: 'Remove Row',
                              onPressed: () => _removeItem(idx),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Section 3: Bottom Calculation and Summary
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Notes & Terms
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: BillzoColors.cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BillzoColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bill Notes & Internal Remarks',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Enter internal notes, terms, or GRN details...',
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // Grand Totals Card
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: BillzoColors.cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BillzoColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Payment & Tax Summary',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                        ),
                        const SizedBox(height: 14),

                        _summaryLine('Taxable Subtotal:', Money.formatPaise(totals.grossTaxableAmountPaise)),
                        if (totals.totalDiscountPaise > 0) ...[
                          const SizedBox(height: 6),
                          _summaryLine('Discounts:', '-${Money.formatPaise(totals.totalDiscountPaise)}', color: BillzoColors.dangerRed),
                        ],
                        if (totals.totalCgstPaise > 0) ...[
                          const SizedBox(height: 6),
                          _summaryLine('CGST:', Money.formatPaise(totals.totalCgstPaise)),
                        ],
                        if (totals.totalSgstPaise > 0) ...[
                          const SizedBox(height: 6),
                          _summaryLine('SGST:', Money.formatPaise(totals.totalSgstPaise)),
                        ],
                        if (totals.totalIgstPaise > 0) ...[
                          const SizedBox(height: 6),
                          _summaryLine('IGST:', Money.formatPaise(totals.totalIgstPaise)),
                        ],
                        if (totals.roundOffPaise != 0) ...[
                          const SizedBox(height: 6),
                          _summaryLine('Round-Off:', Money.formatPaise(totals.roundOffPaise)),
                        ],

                        const Divider(height: 20),
                        _summaryLine('Total Payable:', Money.formatPaise(totals.finalPayablePaise), isBold: true, fontSize: 18, color: BillzoColors.primaryBlue),
                        const SizedBox(height: 12),

                        // ITC Notice
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: BillzoColors.canvasLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Eligible Input GST:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  Text(Money.formatPaise(_eligibleItcPaise), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.successGreen)),
                                ],
                              ),
                              if (_ineligibleItcPaise > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Ineligible ITC (Sec 17(5)):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                    Text(Money.formatPaise(_ineligibleItcPaise), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
