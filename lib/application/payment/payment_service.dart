import 'package:uuid/uuid.dart';

import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_repository.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/domain/payment/payment_validator.dart';
import 'package:billzo/domain/purchase/purchase.dart';

/// Application Service coordinating customer payments, allocations, cancellations, and cash/bank operations.
class PaymentService {
  final IPaymentRepository _paymentRepository;
  final Uuid _uuid = const Uuid();

  PaymentService(this._paymentRepository);

  /// Validates payment domain invariants.
  PaymentValidationResult validatePayment(Payment payment) {
    return PaymentValidator.validate(payment);
  }

  /// Automatically allocates an incoming payment amount against outstanding invoices in FIFO order.
  List<PaymentAllocation> autoAllocateAmount({
    required int amountPaise,
    required List<Invoice> outstandingInvoices,
    String paymentId = '',
  }) {
    if (amountPaise <= 0 || outstandingInvoices.isEmpty) return [];

    final List<PaymentAllocation> allocations = [];
    int remainingToAllocate = amountPaise;
    final now = DateTime.now().toUtc();

    for (final invoice in outstandingInvoices) {
      if (remainingToAllocate <= 0) break;
      if (invoice.balanceAmountPaise <= 0) continue;

      final allocatedAmount = remainingToAllocate < invoice.balanceAmountPaise
          ? remainingToAllocate
          : invoice.balanceAmountPaise;

      allocations.add(
        PaymentAllocation(
          id: _uuid.v4(),
          paymentId: paymentId,
          documentId: invoice.id,
          documentType: 'TAX_INVOICE',
          allocatedAmountPaise: allocatedAmount,
          invoiceNumber: invoice.invoiceNumber,
          invoiceDate: invoice.invoiceDate,
          invoiceTotalPaise: invoice.totalAmountPaise,
          invoiceOutstandingBeforePaise: invoice.balanceAmountPaise,
          createdAt: now,
          updatedAt: now,
        ),
      );

      remainingToAllocate -= allocatedAmount;
    }

    return allocations;
  }

  /// Automatically allocates a supplier payment amount against outstanding purchases in FIFO order.
  List<PaymentAllocation> autoAllocatePurchases({
    required int amountPaise,
    required List<Purchase> outstandingPurchases,
    String paymentId = '',
  }) {
    if (amountPaise <= 0 || outstandingPurchases.isEmpty) return [];

    final List<PaymentAllocation> allocations = [];
    int remainingToAllocate = amountPaise;
    final now = DateTime.now().toUtc();

    for (final purchase in outstandingPurchases) {
      if (remainingToAllocate <= 0) break;
      if (purchase.balanceAmountPaise <= 0) continue;

      final allocatedAmount = remainingToAllocate < purchase.balanceAmountPaise
          ? remainingToAllocate
          : purchase.balanceAmountPaise;

      allocations.add(
        PaymentAllocation(
          id: _uuid.v4(),
          paymentId: paymentId,
          documentId: purchase.id,
          documentType: 'PURCHASE',
          allocatedAmountPaise: allocatedAmount,
          invoiceNumber: purchase.purchaseNumber,
          invoiceDate: purchase.purchaseDate,
          invoiceTotalPaise: purchase.totalAmountPaise,
          invoiceOutstandingBeforePaise: purchase.balanceAmountPaise,
          createdAt: now,
          updatedAt: now,
        ),
      );

      remainingToAllocate -= allocatedAmount;
    }

    return allocations;
  }

  /// Records a new payment in draft or posted state.
  Future<Payment> recordPayment({
    required String businessId,
    required String customerId,
    String? customerName,
    String? customerPhone,
    required DateTime paymentDate,
    required PaymentMethod paymentMethod,
    required int amountPaise,
    String? accountId,
    String? referenceNumber,
    String? notes,
    List<PaymentAllocation> allocations = const [],
    bool isDraft = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    final payment = Payment(
      id: id,
      businessId: businessId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      paymentNumber: isDraft ? 'DRAFT' : '',
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      amountPaise: amountPaise,
      accountId: accountId,
      referenceNumber: referenceNumber,
      notes: notes,
      status: isDraft ? PaymentStatus.draft : PaymentStatus.posted,
      allocations: allocations.map((a) => a.copyWith(paymentId: id)).toList(),
      createdAt: now,
      updatedAt: now,
    );

    if (isDraft) {
      return _paymentRepository.createDraft(payment);
    } else {
      return _paymentRepository.postPayment(payment);
    }
  }

  /// Records a new supplier payment in draft or posted state.
  Future<Payment> recordSupplierPayment({
    required String businessId,
    required String supplierId,
    String? supplierName,
    String? supplierPhone,
    required DateTime paymentDate,
    required PaymentMethod paymentMethod,
    required int amountPaise,
    String? accountId,
    String? referenceNumber,
    String? notes,
    List<PaymentAllocation> allocations = const [],
    bool isDraft = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    final payment = Payment(
      id: id,
      businessId: businessId,
      customerId: supplierId,
      partyType: PartyType.supplier,
      customerName: supplierName,
      customerPhone: supplierPhone,
      paymentNumber: isDraft ? 'DRAFT' : '',
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      amountPaise: amountPaise,
      accountId: accountId,
      referenceNumber: referenceNumber,
      notes: notes,
      status: isDraft ? PaymentStatus.draft : PaymentStatus.posted,
      allocations: allocations.map((a) => a.copyWith(paymentId: id, documentType: 'PURCHASE')).toList(),
      createdAt: now,
      updatedAt: now,
    );

    if (isDraft) {
      return _paymentRepository.createDraft(payment);
    } else {
      return _paymentRepository.postPayment(payment);
    }
  }

  /// Posts an existing draft payment to finalize allocations and accounting entries.
  Future<Payment> postDraft(Payment draft) async {
    if (draft.status != PaymentStatus.draft) {
      throw StateError('Only draft payments can be posted via postDraft.');
    }
    return _paymentRepository.postPayment(draft);
  }

  /// Cancels a posted payment and reverses accounting and stock allocations.
  Future<Payment> cancelPayment(String paymentId, {required String reason}) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('A cancellation reason is required.');
    }
    return _paymentRepository.cancelPayment(paymentId, cancellationReason: reason);
  }

  /// Deletes a draft payment.
  Future<void> deleteDraft(String paymentId) async {
    return _paymentRepository.deleteDraft(paymentId);
  }

  /// Retrieves a payment by ID.
  Future<Payment?> getPaymentById(String id) {
    return _paymentRepository.getPaymentById(id);
  }

  /// Returns paginated payments matching query criteria.
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
  }) {
    return _paymentRepository.getPayments(
      businessId: businessId,
      customerId: customerId,
      supplierId: supplierId,
      status: status,
      method: method,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
      limit: limit,
      offset: offset,
    );
  }

  /// Counts total payments matching query criteria.
  Future<int> getPaymentsCount({
    required String businessId,
    String? customerId,
    String? supplierId,
    PaymentStatus? status,
    PaymentMethod? method,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    return _paymentRepository.getPaymentsCount(
      businessId: businessId,
      customerId: customerId,
      supplierId: supplierId,
      status: status,
      method: method,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
    );
  }

  /// Returns all payments made to a specific supplier.
  Future<List<Payment>> getPaymentsForSupplier(String supplierId) {
    return _paymentRepository.getPaymentsForSupplier(supplierId);
  }

  /// Returns all payment records that allocated funds to a specific purchase bill.
  Future<List<Payment>> getPaymentsForPurchase(String purchaseId) {
    return _paymentRepository.getPaymentsForPurchase(purchaseId);
  }

  /// Retrieves all customer invoices eligible for payment allocation.
  Future<List<Invoice>> getOutstandingInvoicesForCustomer(String businessId, String customerId) {
    return _paymentRepository.getOutstandingInvoicesForCustomer(businessId, customerId);
  }

  /// Retrieves all cash and bank accounts.
  Future<List<CashBankAccount>> getCashBankAccounts(String businessId) {
    return _paymentRepository.getCashBankAccounts(businessId);
  }

  /// Creates a cash or bank account.
  Future<CashBankAccount> createCashBankAccount(CashBankAccount account) {
    return _paymentRepository.createCashBankAccount(account);
  }

  /// Preview next payment sequence number.
  Future<String> getNextPaymentNumberPreview(String businessId) {
    return _paymentRepository.getNextPaymentNumberPreview(businessId);
  }
}
