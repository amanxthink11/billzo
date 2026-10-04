import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';

/// Repository contract for payment persistence, statutory posting, cancellation, and cash/bank operations.
abstract class IPaymentRepository {
  /// Saves a draft payment without ledger entries or invoice allocations.
  Future<Payment> createDraft(Payment payment);

  /// Updates an existing draft payment.
  Future<Payment> updateDraft(Payment payment);

  /// Deletes a draft payment.
  Future<void> deleteDraft(String paymentId);

  /// Retrieves a payment by its unique ID with all allocations joined.
  Future<Payment?> getPaymentById(String id);

  /// Returns paginated payments matching the given query filters.
  Future<List<Payment>> getPayments({
    required String businessId,
    String? customerId,
    String? supplierId,
    PaymentStatus? status,
    PaymentMethod? method,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  });

  /// Counts total payments matching the given query filters.
  Future<int> getPaymentsCount({
    required String businessId,
    String? customerId,
    String? supplierId,
    PaymentStatus? status,
    PaymentMethod? method,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  });

  /// Atomically posts a payment, allocates against invoices or purchases, updates customer/supplier balance,
  /// posts double-entry accounting records, and records audit logs.
  Future<Payment> postPayment(Payment payment);

  /// Atomically cancels a posted payment, reversing all allocations, restoring customer/supplier
  /// and invoice/purchase balances, posting reversing accounting records, and recording audit logs.
  Future<Payment> cancelPayment(String paymentId, {required String cancellationReason});

  /// Returns all payments received from a specific customer.
  Future<List<Payment>> getPaymentsForCustomer(String customerId);

  /// Returns all payments made to a specific supplier.
  Future<List<Payment>> getPaymentsForSupplier(String supplierId);

  /// Returns all payment records that allocated funds to a specific invoice.
  Future<List<Payment>> getPaymentsForInvoice(String invoiceId);

  /// Returns all payment records that allocated funds to a specific purchase bill.
  Future<List<Payment>> getPaymentsForPurchase(String purchaseId);

  /// Retrieves all finalized or partially-paid invoices for a customer that have positive outstanding balances.
  Future<List<Invoice>> getOutstandingInvoicesForCustomer(String businessId, String customerId);

  /// Retrieves all active cash and bank holding accounts for a business.
  Future<List<CashBankAccount>> getCashBankAccounts(String businessId);

  /// Retrieves a specific cash/bank account by ID.
  Future<CashBankAccount?> getCashBankAccountById(String id);

  /// Creates a new cash or bank holding account.
  Future<CashBankAccount> createCashBankAccount(CashBankAccount account);

  /// Updates an existing cash or bank holding account.
  Future<CashBankAccount> updateCashBankAccount(CashBankAccount account);

  /// Computes a preview of the next statutory payment sequence number without consuming it.
  Future<String> getNextPaymentNumberPreview(String businessId);
}
