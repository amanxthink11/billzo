import 'package:billzo/domain/invoice/discount_engine.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_repository.dart';
import 'package:billzo/domain/purchase/purchase_return.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';

/// Application service orchestrating the purchase, debit note, and accounts payable workflow.
class PurchaseService {
  final IPurchaseRepository _repository;

  PurchaseService(this._repository);

  /// Saves a new draft purchase bill.
  Future<Purchase> saveDraft(Purchase purchase) {
    return _repository.saveDraft(purchase);
  }

  /// Updates an existing draft purchase bill.
  Future<Purchase> updateDraft(Purchase purchase) {
    return _repository.updateDraft(purchase);
  }

  /// Atomically finalizes a purchase bill, allocating internal sequence number,
  /// updating inventory stock, increasing supplier payable, and posting balanced ledger entries.
  Future<Purchase> finalizePurchase(Purchase purchase) {
    return _repository.finalizePurchase(purchase);
  }

  /// Safely cancels a finalized purchase bill, reversing inventory stock,
  /// restoring supplier balance, reversing input GST / ITC, and posting reversing ledger entries.
  Future<Purchase> cancelPurchase(String purchaseId, {required String cancellationReason}) {
    return _repository.cancelPurchase(purchaseId, cancellationReason: cancellationReason);
  }

  /// Deletes an un-finalized draft purchase bill.
  Future<void> deleteDraft(String purchaseId) {
    return _repository.deleteDraft(purchaseId);
  }

  /// Records a purchase return / debit note against an original finalized purchase.
  Future<PurchaseReturn> recordReturn(PurchaseReturn purchaseReturn) {
    return _repository.recordReturn(purchaseReturn);
  }

  /// Retrieves a purchase bill by its ID with all line items joined.
  Future<Purchase?> getPurchaseById(String id) {
    return _repository.getPurchaseById(id);
  }

  /// Retrieves a paginated list of purchase bills matching filters.
  Future<List<Purchase>> getPurchases({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) {
    return _repository.getPurchases(
      businessId: businessId,
      status: status,
      supplierId: supplierId,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
      limit: limit,
      offset: offset,
    );
  }

  /// Counts the total number of matching purchase bills.
  Future<int> countPurchases({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _repository.countPurchases(
      businessId: businessId,
      status: status,
      supplierId: supplierId,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Previews the next statutory internal purchase number.
  Future<String> getNextPurchaseNumberPreview(String businessId) {
    return _repository.getNextPurchaseNumberPreview(businessId);
  }

  /// Checks if a supplier invoice number already exists for this supplier.
  Future<bool> checkDuplicateSupplierInvoice({
    required String businessId,
    required String supplierId,
    required String supplierInvoiceNumber,
    String? excludePurchaseId,
  }) {
    return _repository.checkDuplicateSupplierInvoice(
      businessId: businessId,
      supplierId: supplierId,
      supplierInvoiceNumber: supplierInvoiceNumber,
      excludePurchaseId: excludePurchaseId,
    );
  }

  /// Calculates total purchased, total paid, and outstanding payable for a supplier.
  Future<SupplierAccountsPayableSummary> getSupplierAccountsPayableSummary(
    String businessId,
    String supplierId,
  ) {
    return _repository.getSupplierAccountsPayableSummary(businessId, supplierId);
  }

  /// Retrieves all outstanding purchases for a supplier.
  Future<List<Purchase>> getOutstandingPurchasesForSupplier(
    String businessId,
    String supplierId,
  ) {
    return _repository.getOutstandingPurchasesForSupplier(businessId, supplierId);
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

  /// Helper to calculate full purchase bill totals from line breakdowns.
  InvoiceTaxCalculation calculatePurchaseTotals({
    required List<LineTaxBreakdown> lines,
    bool enableRoundOff = true,
  }) {
    return TaxEngine.calculateInvoice(
      lines: lines,
      enableRoundOff: enableRoundOff,
    );
  }
}
