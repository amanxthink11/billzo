import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/core/constants/indian_states.dart';
import 'package:billzo/core/money/money.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/core/utils/number_to_words.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/catalog/tax_rate.dart';
import 'package:billzo/domain/catalog/unit_of_measurement.dart';
import 'package:billzo/domain/invoice/discount_engine.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/invoice_providers.dart';
import 'package:billzo/presentation/screens/sales/customer_select_dialog.dart';
import 'package:billzo/presentation/screens/sales/invoice_detail_screen.dart';
import 'package:billzo/presentation/screens/sales/product_select_dialog.dart';

/// Desktop-optimized Invoice Builder Canvas.
class InvoiceBuilderScreen extends ConsumerStatefulWidget {
  final Business business;
  final Invoice? draftToEdit;

  const InvoiceBuilderScreen({
    super.key,
    required this.business,
    this.draftToEdit,
  });

  @override
  ConsumerState<InvoiceBuilderScreen> createState() => _InvoiceBuilderScreenState();
}

class _InvoiceBuilderScreenState extends ConsumerState<InvoiceBuilderScreen> {
  final _uuid = const Uuid();

  Party? _selectedCustomer;
  late DateTime _invoiceDate;
  late DateTime _dueDate;
  late String _placeOfSupplyStateCode;
  late InvoiceType _invoiceType;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _termsController = TextEditingController();

  List<_BuilderItemEntry> _items = [];
  Map<String, TaxRate> _taxRatesMap = {};
  Map<String, UnitOfMeasurement> _unitsMap = {};

  bool _isLoading = false;
  String _previewNumber = 'Loading...';

  @override
  void initState() {
    super.initState();
    final draft = widget.draftToEdit;

    final hasGstin = widget.business.gstin != null && widget.business.gstin!.trim().isNotEmpty;
    _invoiceDate = draft?.invoiceDate ?? DateTime.now();
    _dueDate = draft?.dueDate ?? DateTime.now().add(const Duration(days: 15));
    _placeOfSupplyStateCode = draft?.placeOfSupplyStateCode ?? widget.business.stateCode;
    _invoiceType = draft?.invoiceType ?? (hasGstin ? InvoiceType.taxInvoice : InvoiceType.billOfSupply);
    _notesController.text = draft?.notes ?? '';
    _termsController.text = draft?.termsAndConditions ?? 'Payment due within 15 days of invoice date.';

    _loadMasters();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _termsController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMasters() async {
    final taxRateRepo = ref.read(taxRateRepositoryProvider);
    final unitRepo = ref.read(unitRepositoryProvider);
    final partyRepo = ref.read(partyRepositoryProvider);
    final invoiceService = ref.read(invoiceServiceProvider);
    final businessRepo = ref.read(businessRepositoryProvider);

    final taxRates = await taxRateRepo.getTaxRates(widget.business.id);
    final units = await unitRepo.getUnits(widget.business.id);
    final nextNumber = await invoiceService.getNextInvoiceNumberPreview(widget.business.id);
    final settings = await businessRepo.getBusinessSettings(widget.business.id);

    if (mounted) {
      setState(() {
        _taxRatesMap = {for (final t in taxRates) t.id: t};
        _unitsMap = {for (final u in units) u.id: u};
        _previewNumber = nextNumber;
        if (widget.draftToEdit == null && settings != null) {
          if (settings.defaultInvoiceTerms != null && settings.defaultInvoiceTerms!.isNotEmpty) {
            _termsController.text = settings.defaultInvoiceTerms!;
          }
          if (settings.defaultInvoiceNotes != null && settings.defaultInvoiceNotes!.isNotEmpty) {
            _notesController.text = settings.defaultInvoiceNotes!;
          }
        }
      });
    }

    if (widget.draftToEdit != null) {
      final draft = widget.draftToEdit!;
      final cust = await partyRepo.getPartyById(draft.customerId);
      if (mounted) {
        setState(() {
          _selectedCustomer = cust;
          _items = draft.items.map((i) {
            final entry = _BuilderItemEntry(
              id: i.id,
              productId: i.productId,
              productName: i.productName,
              hsnSac: i.hsnSac,
              unitCode: i.unitCode,
              ratePaise: i.ratePaise,
              mrpPaise: i.mrpPaise,
              taxRateId: i.taxRateId,
              isTaxInclusive: i.isTaxInclusive,
              trackInventory: i.trackInventory,
              initialQuantity: i.quantity,
              initialDiscountValue: i.discountPaise / 100.0,
              initialDiscountType: DiscountType.fixed,
            );
            entry.addListener(_recalculate);
            return entry;
          }).toList();
        });
      }
    }
  }

  void _recalculate() {
    setState(() {});
  }

  bool get _isInterState {
    return TaxEngine.isInterState(
      businessStateCode: widget.business.stateCode,
      placeOfSupplyStateCode: _placeOfSupplyStateCode,
    );
  }

  List<LineTaxBreakdown> _computeLineBreakdowns() {
    final isInterState = _isInterState;
    final breakdowns = <LineTaxBreakdown>[];

    for (final item in _items) {
      final taxRate = _taxRatesMap[item.taxRateId];
      final rateBps = taxRate?.rateBasisPoints ?? 0;
      final cgstBps = taxRate?.cgstBasisPoints ?? 0;
      final sgstBps = taxRate?.sgstBasisPoints ?? 0;
      final igstBps = taxRate?.igstBasisPoints ?? 0;

      final qtyScaled = (item.quantity * 1000).round();
      final ratePaise = item.ratePaise;

      final grossNumerator = ratePaise * qtyScaled;
      final grossAmountPaise = (grossNumerator + 500) ~/ 1000;

      final discountPaise = DiscountEngine.calculateDiscountPaise(
        grossPaise: grossAmountPaise,
        type: item.discountType,
        value: item.discountValue,
      );

      final breakdown = TaxEngine.calculateLine(
        rateOrMrpPaise: ratePaise,
        quantityScaled: qtyScaled,
        discountPaise: discountPaise,
        rateBasisPoints: rateBps,
        cgstBasisPoints: cgstBps,
        sgstBasisPoints: sgstBps,
        igstBasisPoints: igstBps,
        cessBasisPoints: 0,
        isTaxInclusive: item.isTaxInclusive,
        isInterState: isInterState,
      );

      breakdowns.add(breakdown);
    }

    return breakdowns;
  }

  InvoiceTaxCalculation _computeTotals() {
    final breakdowns = _computeLineBreakdowns();
    return TaxEngine.calculateInvoice(lines: breakdowns, enableRoundOff: true);
  }

  void _addItemFromProduct(Product product) {
    // Find tax rate id or fallback to default
    String taxRateId = product.taxRateId ?? '';
    if (taxRateId.isEmpty && _taxRatesMap.isNotEmpty) {
      taxRateId = _taxRatesMap.values.first.id;
    }

    final unit = _unitsMap[product.unitId];
    final unitCode = unit?.code ?? 'PCS';

    final entry = _BuilderItemEntry(
      id: _uuid.v4(),
      productId: product.id,
      productName: product.name,
      hsnSac: product.hsnSacCode,
      unitCode: unitCode,
      ratePaise: product.sellingPricePaise,
      mrpPaise: product.mrpPaise ?? 0,
      taxRateId: taxRateId,
      isTaxInclusive: product.isTaxInclusive,
      trackInventory: product.isGoods,
      initialQuantity: 1.0,
      initialDiscountValue: 0.0,
      initialDiscountType: DiscountType.fixed,
    );

    entry.addListener(_recalculate);

    setState(() {
      _items.add(entry);
    });
  }

  Future<void> _pickCustomer() async {
    final customer = await showDialog<Party>(
      context: context,
      builder: (_) => CustomerSelectDialog(businessId: widget.business.id),
    );
    if (customer != null) {
      setState(() {
        _selectedCustomer = customer;
        if (customer.billingStateCode != null && customer.billingStateCode!.isNotEmpty) {
          _placeOfSupplyStateCode = customer.billingStateCode!;
        }
      });
    }
  }

  Future<void> _pickProduct() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => ProductSelectDialog(businessId: widget.business.id),
    );
    if (product != null) {
      _addItemFromProduct(product);
    }
  }

  Invoice _buildInvoiceAggregate({required bool isDraft}) {
    final totals = _computeTotals();
    final breakdowns = _computeLineBreakdowns();
    final now = DateTime.now().toUtc();

    final invoiceItems = <InvoiceItem>[];
    for (int i = 0; i < _items.length; i++) {
      final entry = _items[i];
      final b = breakdowns[i];
      invoiceItems.add(
        InvoiceItem(
          id: entry.id,
          invoiceId: widget.draftToEdit?.id ?? '',
          productId: entry.productId,
          taxRateId: entry.taxRateId,
          productName: entry.productName,
          hsnSac: entry.hsnSac,
          quantityScaled: (entry.quantity * 1000).round(),
          unitCode: entry.unitCode,
          ratePaise: entry.ratePaise,
          mrpPaise: entry.mrpPaise,
          discountPaise: b.discountPaise,
          taxableAmountPaise: b.taxableAmountPaise,
          cgstRateBasisPoints: b.cgstRateBasisPoints,
          cgstAmountPaise: b.cgstAmountPaise,
          sgstRateBasisPoints: b.sgstRateBasisPoints,
          sgstAmountPaise: b.sgstAmountPaise,
          igstRateBasisPoints: b.igstRateBasisPoints,
          igstAmountPaise: b.igstAmountPaise,
          cessRateBasisPoints: b.cessRateBasisPoints,
          cessAmountPaise: b.cessAmountPaise,
          totalAmountPaise: b.lineTotalPaise,
          isTaxInclusive: entry.isTaxInclusive,
          trackInventory: entry.trackInventory,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    return Invoice(
      id: widget.draftToEdit?.id ?? _uuid.v4(),
      businessId: widget.business.id,
      customerId: _selectedCustomer!.id,
      invoiceNumber: widget.draftToEdit?.invoiceNumber ?? (isDraft ? 'DRAFT' : _previewNumber),
      invoiceDate: _invoiceDate,
      dueDate: _dueDate,
      placeOfSupplyStateCode: _placeOfSupplyStateCode,
      invoiceType: _invoiceType,
      status: isDraft ? InvoiceStatus.draft : InvoiceStatus.finalized,
      subtotalPaise: totals.subtotalPaise,
      discountPaise: totals.discountPaise,
      taxableAmountPaise: totals.taxableAmountPaise,
      cgstPaise: totals.cgstPaise,
      sgstPaise: totals.sgstPaise,
      igstPaise: totals.igstPaise,
      cessPaise: totals.cessPaise,
      roundOffPaise: totals.roundOffPaise,
      totalAmountPaise: totals.totalAmountPaise,
      paidAmountPaise: 0,
      balanceAmountPaise: totals.totalAmountPaise,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      termsAndConditions: _termsController.text.trim().isEmpty ? null : _termsController.text.trim(),
      createdAt: widget.draftToEdit?.createdAt ?? now,
      updatedAt: now,
      items: invoiceItems,
      customerName: _selectedCustomer?.name,
      customerPhone: _selectedCustomer?.phone,
      customerGstin: _selectedCustomer?.gstin,
      customerCompanyName: _selectedCustomer?.companyName,
    );
  }

  Future<void> _saveDraft() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer first.'), backgroundColor: BillzoColors.dangerRed),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item to the invoice.'), backgroundColor: BillzoColors.dangerRed),
      );
      return;
    }

    setState(() => _isLoading = true);
    final service = ref.read(invoiceServiceProvider);

    try {
      final invoice = _buildInvoiceAggregate(isDraft: true);
      final saved = await service.saveDraft(invoice);
      ref.invalidate(invoicesListProvider);
      ref.invalidate(invoicesCountProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Draft saved successfully: ${saved.invoiceNumber}'),
            backgroundColor: BillzoColors.primaryBlue,
          ),
        );
        Navigator.of(context).pop(saved);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving draft: $e'), backgroundColor: BillzoColors.dangerRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finalizeInvoice() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer to finalize invoice.'), backgroundColor: BillzoColors.dangerRed),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item to finalize invoice.'), backgroundColor: BillzoColors.dangerRed),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalize Tax Invoice'),
        content: const Text(
          'Finalizing will allocate an official sequential invoice number, deduct stock for goods, and post double-entry general ledger entries. This action cannot be edited.\n\nDo you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finalize & Issue'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    final service = ref.read(invoiceServiceProvider);

    try {
      final invoice = _buildInvoiceAggregate(isDraft: false);
      final finalized = await service.finalizeInvoice(invoice);

      ref.invalidate(invoicesListProvider);
      ref.invalidate(invoicesCountProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice ${finalized.invoiceNumber} finalized successfully!'),
            backgroundColor: BillzoColors.successGreen,
          ),
        );

        // Open Invoice Detail view
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(
              business: widget.business,
              invoiceId: finalized.id,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error finalizing invoice: $e'), backgroundColor: BillzoColors.dangerRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onCancelOrBack() async {
    if (_items.isEmpty && _selectedCustomer == null) {
      Navigator.of(context).pop();
      return;
    }
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Invoice?'),
        content: const Text('You have unsaved items in this invoice. Are you sure you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.dangerRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (shouldDiscard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _computeTotals();
    final dateFormat = DateFormat('yyyy-MM-dd');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onCancelOrBack();
      },
      child: Scaffold(
        backgroundColor: BillzoColors.canvasLight,
        appBar: AppBar(
          title: Text(
            widget.draftToEdit != null ? 'Edit Invoice Draft (${widget.draftToEdit!.invoiceNumber})' : 'New Sales Invoice',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          backgroundColor: BillzoColors.cardSurface,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back [Esc]',
            onPressed: _onCancelOrBack,
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  'Next #: $_previewNumber',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: BillzoColors.neutralText, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        body: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.f2): _pickProduct,
            const SingleActivator(LogicalKeyboardKey.f3): _pickProduct,
            const SingleActivator(LogicalKeyboardKey.f4): _pickCustomer,
            const SingleActivator(LogicalKeyboardKey.f10): _finalizeInvoice,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveDraft,
            const SingleActivator(LogicalKeyboardKey.escape): _onCancelOrBack,
          },
          child: Focus(
            autofocus: true,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left 70%: Customer & Line Items Canvas
                    Expanded(
                      flex: 7,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Customer & Metadata Card
                            _buildHeaderCard(dateFormat),
                            const SizedBox(height: 16),

                            // 2. Line Items Table Card
                            _buildItemsCard(),
                            const SizedBox(height: 16),

                            // 3. Notes & Terms Card
                            _buildNotesAndTermsCard(),
                          ],
                        ),
                      ),
                    ),

                    // Right 30%: Calculation Summary Card & CTAs
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: double.infinity,
                        margin: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: BillzoColors.cardSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: BillzoColors.border),
                          boxShadow: const [
                            BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Invoice Summary',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: BillzoColors.darkSlate),
                            ),
                            const SizedBox(height: 16),

                            // Summary lines
                            _summaryLine('Items Subtotal', totals.subtotal.toIndianRupeeString()),
                            if (totals.discountPaise > 0)
                              _summaryLine('Total Discount', '- ₹${totals.discount.toIndianRupeeString()}', isGreen: true),
                            _summaryLine('Taxable Amount', totals.taxableAmount.toIndianRupeeString()),

                            const Divider(height: 20, color: BillzoColors.border),

                            // GST details
                            if (_isInterState) ...[
                              _summaryLine('IGST', totals.igst.toIndianRupeeString()),
                            ] else ...[
                              _summaryLine('CGST', totals.cgst.toIndianRupeeString()),
                              _summaryLine('SGST', totals.sgst.toIndianRupeeString()),
                            ],
                            if (totals.cessPaise > 0)
                              _summaryLine('Cess', totals.cess.toIndianRupeeString()),

                            if (totals.roundOffPaise != 0) ...[
                              _summaryLine(
                                'Round Off Adjustment',
                                '${totals.roundOffPaise > 0 ? '+' : ''}${Money.fromPaise(totals.roundOffPaise).formatted}',
                              ),
                            ],

                            const Divider(height: 24, color: BillzoColors.border, thickness: 1.5),

                            // Grand Total
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Grand Total',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                                ),
                                Text(
                                  '₹${totals.totalAmount.toIndianRupeeString()}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: BillzoColors.primaryBlue,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Amount in Words
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: BillzoColors.border),
                              ),
                              child: Text(
                                totals.totalAmount.isZero
                                    ? 'Rupees Zero Only'
                                    : IndianNumberToWords.convert(totals.totalAmount),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: BillzoColors.neutralText,
                                ),
                              ),
                            ),

                            const Spacer(),

                            // Keyboard Shortcuts Hint
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Keyboard Shortcuts:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: BillzoColors.primaryBlue)),
                                  SizedBox(height: 2),
                                  Text('[F2] Add Item  |  [F4] Customer  |  [F10] Finalize', style: TextStyle(fontSize: 11, color: BillzoColors.primaryBlue)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onPressed: _saveDraft,
                                    child: const Text('Save Draft'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: BillzoColors.primaryBlue,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onPressed: _finalizeInvoice,
                                    child: const Text('Finalize [F10]', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
  }

  // --- Sub-Card Builders ---

  Widget _buildHeaderCard(DateFormat dateFormat) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Customer Selection Box
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Customer *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: BillzoColors.darkSlate)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _pickCustomer,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: _selectedCustomer == null ? BillzoColors.dangerRed.withValues(alpha: 0.5) : BillzoColors.border),
                          borderRadius: BorderRadius.circular(8),
                          color: _selectedCustomer != null ? const Color(0xFFF8FAFC) : Colors.white,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedCustomer != null ? Icons.person : Icons.person_add_outlined,
                              size: 20,
                              color: _selectedCustomer != null ? BillzoColors.primaryBlue : BillzoColors.neutralText,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _selectedCustomer != null
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedCustomer!.name,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                        ),
                                        if (_selectedCustomer!.phone != null)
                                          Text(
                                            'Ph: ${_selectedCustomer!.phone!}',
                                            style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText),
                                          ),
                                      ],
                                    )
                                  : const Text(
                                      'Select or Search Customer [F4]',
                                      style: TextStyle(color: BillzoColors.neutralText, fontSize: 13),
                                    ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: BillzoColors.neutralText),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Invoice Date
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Invoice Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _invoiceDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) setState(() => _invoiceDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(color: BillzoColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                dateFormat.format(_invoiceDate),
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.calendar_today, size: 14, color: BillzoColors.neutralText),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Due Date
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Due Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dueDate,
                          firstDate: _invoiceDate,
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) setState(() => _dueDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(color: BillzoColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                dateFormat.format(_dueDate),
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.calendar_today, size: 14, color: BillzoColors.neutralText),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Place of Supply
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Place of Supply', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: BillzoColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _placeOfSupplyStateCode,
                          isExpanded: true,
                          items: IndianStates.all.map((s) {
                            return DropdownMenuItem<String>(
                              value: s.code,
                              child: Text('${s.code} - ${s.name}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (code) {
                            if (code != null) setState(() => _placeOfSupplyStateCode = code);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: BillzoColors.border),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text('Document Type:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: BillzoColors.darkSlate)),
              SegmentedButton<InvoiceType>(
                segments: const [
                  ButtonSegment<InvoiceType>(
                    value: InvoiceType.taxInvoice,
                    label: Text('Tax Invoice'),
                    icon: Icon(Icons.receipt, size: 16),
                  ),
                  ButtonSegment<InvoiceType>(
                    value: InvoiceType.billOfSupply,
                    label: Text('Bill of Supply'),
                    icon: Icon(Icons.description_outlined, size: 16),
                  ),
                ],
                selected: {_invoiceType},
                onSelectionChanged: (Set<InvoiceType> selected) {
                  setState(() => _invoiceType = selected.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (widget.business.gstin == null || widget.business.gstin!.trim().isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Text(
                    'Bill of Supply is statutory for Composition / Unregistered businesses',
                    style: TextStyle(fontSize: 11, color: BillzoColors.primaryBlue, fontWeight: FontWeight.w500),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard() {
    final breakdowns = _computeLineBreakdowns();

    return Container(
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Invoice Items',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: BillzoColors.darkSlate),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BillzoColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.add_shopping_cart, size: 16),
                  label: const Text('Add Item [F2]'),
                  onPressed: _pickProduct,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: BillzoColors.border),

          // Items Table
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 48, color: BillzoColors.neutralText),
                    const SizedBox(height: 8),
                    const Text(
                      'No items added yet',
                      style: TextStyle(fontWeight: FontWeight.w600, color: BillzoColors.neutralText),
                    ),
                    const SizedBox(height: 4),
                    const Text('Click "+ Add Item [F2]" to add goods or services.', style: TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
                  ],
                ),
              ),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3.5), // Product Name & HSN
                1: FixedColumnWidth(80), // Quantity
                2: FixedColumnWidth(60), // Unit
                3: FixedColumnWidth(95), // Rate
                4: FixedColumnWidth(85), // Discount
                5: FixedColumnWidth(110), // Tax Rate
                6: FixedColumnWidth(95), // Line Total
                7: FixedColumnWidth(40), // Delete Action
              },
              children: [
                // Header
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                  children: [
                    _th('Item Description'),
                    _th('Quantity', align: TextAlign.right),
                    _th('Unit', align: TextAlign.center),
                    _th('Rate (₹)', align: TextAlign.right),
                    _th('Disc (₹)', align: TextAlign.right),
                    _th('GST Rate', align: TextAlign.center),
                    _th('Amount (₹)', align: TextAlign.right),
                    const SizedBox.shrink(),
                  ],
                ),

                // Line Item Rows
                for (int i = 0; i < _items.length; i++) ...[
                  _buildItemTableRow(i, _items[i], breakdowns[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }

  TableRow _buildItemTableRow(int index, _BuilderItemEntry item, LineTaxBreakdown breakdown) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: BillzoColors.border.withValues(alpha: 0.5))),
      ),
      children: [
        // Name & HSN
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: BillzoColors.darkSlate),
              ),
              if (item.hsnSac != null && item.hsnSac!.isNotEmpty)
                Text('HSN: ${item.hsnSac!}', style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
            ],
          ),
        ),

        // Quantity Input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: TextField(
            controller: item.quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
        ),

        // Unit
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            item.unitCode,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
          ),
        ),

        // Rate Input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: TextField(
            controller: item.rateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
        ),

        // Discount Input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: TextField(
            controller: item.discountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
        ),

        // Tax Rate Selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              border: Border.all(color: BillzoColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: item.taxRateId,
                isExpanded: true,
                items: _taxRatesMap.values.map((t) {
                  return DropdownMenuItem<String>(
                    value: t.id,
                    child: Text(
                      '${(t.rateBasisPoints / 100).toStringAsFixed(0)}% GST',
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => item.taxRateId = val);
                  }
                },
              ),
            ),
          ),
        ),

        // Line Total
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            Money.fromPaise(breakdown.lineTotalPaise).formattedWithoutSymbol,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BillzoColors.darkSlate),
          ),
        ),

        // Delete Button
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: BillzoColors.dangerRed),
          onPressed: () {
            setState(() {
              _items.removeAt(index);
            });
          },
        ),
      ],
    );
  }

  Widget _th(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: BillzoColors.neutralText),
      ),
    );
  }

  Widget _buildNotesAndTermsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BillzoColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BillzoColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notes (Visible to Customer)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Add remarks, payment notes, or vehicle numbers...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _termsController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Payment conditions, warranty, refund terms...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value, {bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: BillzoColors.neutralText)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isGreen ? BillzoColors.successGreen : BillzoColors.darkSlate,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper model encapsulating dynamic controller state for a builder line item.
class _BuilderItemEntry {
  final String id;
  final String productId;
  final String productName;
  final String? hsnSac;
  final String unitCode;
  String taxRateId;
  final int mrpPaise;
  final bool isTaxInclusive;
  final bool trackInventory;

  final TextEditingController quantityController;
  final TextEditingController rateController;
  final TextEditingController discountController;
  DiscountType discountType;

  _BuilderItemEntry({
    required this.id,
    required this.productId,
    required this.productName,
    this.hsnSac,
    required this.unitCode,
    required int ratePaise,
    required this.mrpPaise,
    required this.taxRateId,
    required this.isTaxInclusive,
    required this.trackInventory,
    double initialQuantity = 1.0,
    double initialDiscountValue = 0.0,
    DiscountType initialDiscountType = DiscountType.fixed,
  })  : discountType = initialDiscountType,
        quantityController = TextEditingController(text: initialQuantity.toStringAsFixed(unitCode == 'PCS' ? 0 : 2)),
        rateController = TextEditingController(text: (ratePaise / 100.0).toStringAsFixed(2)),
        discountController = TextEditingController(text: initialDiscountValue.toStringAsFixed(2));

  double get quantity => double.tryParse(quantityController.text.trim()) ?? 1.0;
  int get ratePaise => Money.fromRupees(double.tryParse(rateController.text.trim()) ?? 0.0).paise;
  double get discountValue => double.tryParse(discountController.text.trim()) ?? 0.0;

  void addListener(VoidCallback listener) {
    quantityController.addListener(listener);
    rateController.addListener(listener);
    discountController.addListener(listener);
  }

  void dispose() {
    quantityController.dispose();
    rateController.dispose();
    discountController.dispose();
  }
}
