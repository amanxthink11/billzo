import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';

/// Repository interface for Sales Invoices.
abstract class IInvoiceRepository {
  /// Saves a new draft invoice.
  ///
  /// Draft invoices do NOT deduct stock, post ledger entries, or consume
  /// official sequential invoice numbers.
  Future<Invoice> saveDraft(Invoice invoice);

  /// Updates an existing draft invoice and its line items.
  Future<Invoice> updateDraft(Invoice invoice);

  /// Finalizes an invoice inside an atomic database transaction.
  ///
  /// Atomically:
  /// 1. Allocates the next statutory sequential invoice number.
  /// 2. Updates invoice status to [InvoiceStatus.finalized].
  /// 3. Deducts physical inventory for goods items and creates [stock_movements] records.
  /// 4. Posts balanced double-entry accounting records to [ledger_entries].
  /// 5. Updates the customer's outstanding receivable balance.
  /// 6. Records an audit log.
  ///
  /// If any error occurs during this process, all changes are rolled back.
  Future<Invoice> finalizeInvoice(Invoice invoice);

  /// Cancels a finalized invoice safely inside an atomic database transaction.
  ///
  /// Preserves the original invoice record, marks it [InvoiceStatus.cancelled],
  /// reverses deducted stock via compensating stock movements, reverses
  /// ledger entries, and updates the customer's balance.
  Future<Invoice> cancelInvoice(String invoiceId, {required String cancellationReason});

  /// Deletes a draft invoice. Finalized or cancelled invoices cannot be deleted.
  Future<void> deleteDraft(String invoiceId);

  /// Retrieves an invoice by its unique ID, including all line items and customer details.
  Future<Invoice?> getInvoiceById(String id);

  /// Retrieves an invoice by its statutory invoice number within a business.
  Future<Invoice?> getInvoiceByNumber(String businessId, String invoiceNumber);

  /// Retrieves a paginated list of invoices matching optional filter criteria.
  Future<List<Invoice>> getInvoices({
    required String businessId,
    InvoiceStatus? status,
    String? customerId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  });

  /// Counts the total number of invoices matching filter criteria.
  Future<int> countInvoices({
    required String businessId,
    InvoiceStatus? status,
    String? customerId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Previews the next statutory sequential invoice number for a business
  /// without consuming or incrementing the sequence counter.
  Future<String> getNextInvoiceNumberPreview(String businessId);
}
