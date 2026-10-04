import 'package:billzo/domain/invoice/discount_engine.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_repository.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';

/// Application service orchestrating the sales invoicing workflow.
class InvoiceService {
  final IInvoiceRepository _repository;

  InvoiceService(this._repository);

  /// Saves or updates a draft invoice.
  Future<Invoice> saveDraft(Invoice invoice) {
    return _repository.saveDraft(invoice);
  }

  /// Updates an existing draft invoice.
  Future<Invoice> updateDraft(Invoice invoice) {
    return _repository.updateDraft(invoice);
  }

  /// Atomically finalizes an invoice, allocating sequence numbers, deducting stock,
  /// and posting double-entry general ledger entries.
  Future<Invoice> finalizeInvoice(Invoice invoice) {
    return _repository.finalizeInvoice(invoice);
  }

  /// Safely cancels a finalized invoice, restoring stock and posting reversing ledger entries.
  Future<Invoice> cancelInvoice(String invoiceId, {required String cancellationReason}) {
    return _repository.cancelInvoice(invoiceId, cancellationReason: cancellationReason);
  }

  /// Deletes an un-finalized draft invoice.
  Future<void> deleteDraft(String invoiceId) {
    return _repository.deleteDraft(invoiceId);
  }

  /// Retrieves an invoice by its unique ID.
  Future<Invoice?> getInvoiceById(String id) {
    return _repository.getInvoiceById(id);
  }

  /// Retrieves a paginated list of invoices matching filters.
  Future<List<Invoice>> getInvoices({
    required String businessId,
    InvoiceStatus? status,
    String? customerId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) {
    return _repository.getInvoices(
      businessId: businessId,
      status: status,
      customerId: customerId,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
      limit: limit,
      offset: offset,
    );
  }

  /// Counts the total number of matching invoices.
  Future<int> countInvoices({
    required String businessId,
    InvoiceStatus? status,
    String? customerId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _repository.countInvoices(
      businessId: businessId,
      status: status,
      customerId: customerId,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Previews the next sequential invoice number.
  Future<String> getNextInvoiceNumberPreview(String businessId) {
    return _repository.getNextInvoiceNumberPreview(businessId);
  }

  /// Helper to calculate line item breakdown using TaxEngine.
  LineTaxBreakdown calculateLine({
    required int rateOrMrpPaise,
    required int quantityScaled,
    required DiscountType discountType,
    required num discountValue,
    required int rateBasisPoints,
    required int cgstBasisPoints,
    required int sgstBasisPoints,
    required int igstBasisPoints,
    int cessBasisPoints = 0,
    bool isTaxInclusive = false,
    required bool isInterState,
  }) {
    // 1. Calculate discount
    final grossNumerator = rateOrMrpPaise * quantityScaled;
    final grossAmountPaise = (grossNumerator + 500) ~/ 1000;
    final discountPaise = DiscountEngine.calculateDiscountPaise(
      grossPaise: grossAmountPaise,
      type: discountType,
      value: discountValue,
    );

    // 2. Compute taxes
    return TaxEngine.calculateLine(
      rateOrMrpPaise: rateOrMrpPaise,
      quantityScaled: quantityScaled,
      discountPaise: discountPaise,
      rateBasisPoints: rateBasisPoints,
      cgstBasisPoints: cgstBasisPoints,
      sgstBasisPoints: sgstBasisPoints,
      igstBasisPoints: igstBasisPoints,
      cessBasisPoints: cessBasisPoints,
      isTaxInclusive: isTaxInclusive,
      isInterState: isInterState,
    );
  }

  /// Helper to calculate full invoice totals from line breakdowns.
  InvoiceTaxCalculation calculateInvoiceTotals({
    required List<LineTaxBreakdown> lines,
    bool enableRoundOff = true,
  }) {
    return TaxEngine.calculateInvoice(
      lines: lines,
      enableRoundOff: enableRoundOff,
    );
  }
}
