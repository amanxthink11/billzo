import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

// --- Filter State Notifiers ---

class PaymentSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void setQuery(String q) => state = q;
  void clear() => state = '';
}

final paymentSearchQueryProvider =
    NotifierProvider<PaymentSearchQueryNotifier, String>(
  PaymentSearchQueryNotifier.new,
);

class PaymentCustomerFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setCustomer(String? custId) => state = custId;
  void clear() => state = null;
}

final paymentCustomerFilterProvider =
    NotifierProvider<PaymentCustomerFilterNotifier, String?>(
  PaymentCustomerFilterNotifier.new,
);

class PaymentStatusFilterNotifier extends Notifier<PaymentStatus?> {
  @override
  PaymentStatus? build() => null;
  void setStatus(PaymentStatus? s) => state = s;
  void clear() => state = null;
}

final paymentStatusFilterProvider =
    NotifierProvider<PaymentStatusFilterNotifier, PaymentStatus?>(
  PaymentStatusFilterNotifier.new,
);

class PaymentMethodFilterNotifier extends Notifier<PaymentMethod?> {
  @override
  PaymentMethod? build() => null;
  void setMethod(PaymentMethod? m) => state = m;
  void clear() => state = null;
}

final paymentMethodFilterProvider =
    NotifierProvider<PaymentMethodFilterNotifier, PaymentMethod?>(
  PaymentMethodFilterNotifier.new,
);

class PaymentDateRangeNotifier
    extends Notifier<({DateTime? start, DateTime? end})> {
  @override
  ({DateTime? start, DateTime? end}) build() => (start: null, end: null);
  void setRange(DateTime? start, DateTime? end) =>
      state = (start: start, end: end);
  void clear() => state = (start: null, end: null);
}

final paymentDateRangeProvider =
    NotifierProvider<PaymentDateRangeNotifier, ({DateTime? start, DateTime? end})>(
  PaymentDateRangeNotifier.new,
);

// --- Data Providers ---

/// Returns paginated payments for a business adhering to active search and filter states.
final paymentsListProvider =
    FutureProvider.family<List<Payment>, String>((ref, businessId) async {
  final service = ref.watch(paymentServiceProvider);
  final search = ref.watch(paymentSearchQueryProvider);
  final custId = ref.watch(paymentCustomerFilterProvider);
  final status = ref.watch(paymentStatusFilterProvider);
  final method = ref.watch(paymentMethodFilterProvider);
  final dateRange = ref.watch(paymentDateRangeProvider);

  return service.getPayments(
    businessId: businessId,
    customerId: custId,
    status: status,
    method: method,
    startDate: dateRange.start,
    endDate: dateRange.end,
    searchQuery: search,
    limit: 100,
    offset: 0,
  );
});

/// Returns total payment records count for active filters.
final paymentsCountProvider =
    FutureProvider.family<int, String>((ref, businessId) async {
  final service = ref.watch(paymentServiceProvider);
  final search = ref.watch(paymentSearchQueryProvider);
  final custId = ref.watch(paymentCustomerFilterProvider);
  final status = ref.watch(paymentStatusFilterProvider);
  final method = ref.watch(paymentMethodFilterProvider);
  final dateRange = ref.watch(paymentDateRangeProvider);

  return service.getPaymentsCount(
    businessId: businessId,
    customerId: custId,
    status: status,
    method: method,
    startDate: dateRange.start,
    endDate: dateRange.end,
    searchQuery: search,
  );
});

/// Retrieves all active cash and bank accounts for a business.
final cashBankAccountsProvider =
    FutureProvider.family<List<CashBankAccount>, String>((ref, businessId) async {
  final service = ref.watch(paymentServiceProvider);
  return service.getCashBankAccounts(businessId);
});

/// Retrieves customer outstanding invoices for allocation.
final customerOutstandingInvoicesProvider = FutureProvider.family<
    List<Invoice>,
    ({String businessId, String customerId})>((ref, args) async {
  final service = ref.watch(paymentServiceProvider);
  return service.getOutstandingInvoicesForCustomer(
    args.businessId,
    args.customerId,
  );
});

/// Previews next payment number for a business.
final paymentSequencePreviewProvider =
    FutureProvider.family<String, String>((ref, businessId) async {
  final service = ref.watch(paymentServiceProvider);
  return service.getNextPaymentNumberPreview(businessId);
});
