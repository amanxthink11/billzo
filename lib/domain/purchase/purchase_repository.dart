import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_return.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';

/// Summary statistics for Accounts Payable regarding a specific supplier.
class SupplierAccountsPayableSummary {
  final int totalPurchasesCount;
  final int totalPurchasedPaise;
  final int totalPaidPaise;
  final int outstandingPayablePaise;
  final List<Purchase> recentPurchases;

  int get billCount => totalPurchasesCount;
  int get totalPurchasesPaise => totalPurchasedPaise;

  const SupplierAccountsPayableSummary({
    this.totalPurchasesCount = 0,
    this.totalPurchasedPaise = 0,
    this.totalPaidPaise = 0,
    this.outstandingPayablePaise = 0,
    this.recentPurchases = const [],
  });
}

/// Repository contract for purchases, purchase items, and purchase returns.
abstract class IPurchaseRepository {
  /// Saves a new draft purchase bill.
  Future<Purchase> saveDraft(Purchase purchase);

  /// Updates an existing draft purchase bill.
  Future<Purchase> updateDraft(Purchase purchase);

  /// Deletes an un-finalized draft purchase bill.
  Future<void> deleteDraft(String purchaseId);

  /// Atomically finalizes a purchase bill:
  /// allocates sequential purchase number, increases stock for goods,
  /// posts double-entry accounting entries, and updates supplier balance.
  Future<Purchase> finalizePurchase(Purchase purchase);

  /// Atomically cancels a finalized purchase bill:
  /// reverses stock movements, reverses accounting entries, restores supplier payable.
  Future<Purchase> cancelPurchase(String purchaseId, {required String cancellationReason});

  /// Retrieves a purchase bill by its ID with line items.
  Future<Purchase?> getPurchaseById(String id);

  /// Retrieves a filtered list of purchases.
  Future<List<Purchase>> getPurchases({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  });

  /// Counts total matching purchases.
  Future<int> getPurchasesCount({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Previews the next sequential internal purchase number.
  Future<String> getNextPurchaseNumberPreview(String businessId);

  /// Checks if a vendor invoice number already exists for this supplier in this business.
  Future<bool> isSupplierInvoiceDuplicate(
    String businessId,
    String supplierId,
    String supplierInvoiceNumber, {
    String? excludePurchaseId,
  });

  /// Creates a purchase return / debit note:
  /// decreases stock, decreases supplier payable, reverses input GST, posts balanced accounting.
  Future<PurchaseReturn> createReturn(PurchaseReturn purchaseReturn);

  /// Retrieves a purchase return / debit note by its ID.
  Future<PurchaseReturn?> getReturnById(String id);

  /// Retrieves all returns belonging to a purchase.
  Future<List<PurchaseReturn>> getReturnsForPurchase(String purchaseId);

  /// Retrieves purchase returns for a business.
  Future<List<PurchaseReturn>> getReturns({
    required String businessId,
    String? supplierId,
    int limit = 50,
    int offset = 0,
  });

  /// Retrieves accounts payable summary for a specific supplier.
  Future<SupplierAccountsPayableSummary> getSupplierSummary(
    String businessId,
    String supplierId,
  );

  /// Retrieves outstanding purchases for payment allocation.
  Future<List<Purchase>> getOutstandingPurchasesForSupplier(
    String businessId,
    String supplierId,
  );

  /// Records a purchase return (alias for createReturn).
  Future<PurchaseReturn> recordReturn(PurchaseReturn purchaseReturn);

  /// Counts total matching purchases (alias for getPurchasesCount).
  Future<int> countPurchases({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Checks if a vendor invoice number already exists (alias for isSupplierInvoiceDuplicate).
  Future<bool> checkDuplicateSupplierInvoice({
    required String businessId,
    required String supplierId,
    required String supplierInvoiceNumber,
    String? excludePurchaseId,
  });

  /// Retrieves accounts payable summary for a specific supplier (alias for getSupplierSummary).
  Future<SupplierAccountsPayableSummary> getSupplierAccountsPayableSummary(
    String businessId,
    String supplierId,
  );
}
