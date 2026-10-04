import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Search query state for sales invoices list.
class InvoiceSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  @override
  set state(String value) => super.state = value;
}

final invoiceSearchQueryProvider =
    NotifierProvider<InvoiceSearchQueryNotifier, String>(InvoiceSearchQueryNotifier.new);

/// Selected status filter for sales invoices list.
class InvoiceStatusFilterNotifier extends Notifier<InvoiceStatus?> {
  @override
  InvoiceStatus? build() => null;

  @override
  set state(InvoiceStatus? value) => super.state = value;
}

final invoiceStatusFilterProvider =
    NotifierProvider<InvoiceStatusFilterNotifier, InvoiceStatus?>(InvoiceStatusFilterNotifier.new);

/// Selected date range filter for sales invoices list.
class InvoiceDateRangeNotifier extends Notifier<DateTimeRange?> {
  @override
  DateTimeRange? build() => null;

  @override
  set state(DateTimeRange? value) => super.state = value;
}

final invoiceDateRangeProvider =
    NotifierProvider<InvoiceDateRangeNotifier, DateTimeRange?>(InvoiceDateRangeNotifier.new);

/// Reactive list of sales invoices matching the active business and filters.
final invoicesListProvider = FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final business = ref.watch(activeBusinessProvider).value;
  if (business == null) return [];

  final service = ref.watch(invoiceServiceProvider);
  final searchQuery = ref.watch(invoiceSearchQueryProvider);
  final status = ref.watch(invoiceStatusFilterProvider);
  final dateRange = ref.watch(invoiceDateRangeProvider);

  return service.getInvoices(
    businessId: business.id,
    status: status,
    searchQuery: searchQuery.trim().isEmpty ? null : searchQuery.trim(),
    startDate: dateRange?.start,
    endDate: dateRange?.end,
    limit: 100,
  );
});

/// Count of sales invoices matching the active filters.
final invoicesCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final business = ref.watch(activeBusinessProvider).value;
  if (business == null) return 0;

  final service = ref.watch(invoiceServiceProvider);
  final searchQuery = ref.watch(invoiceSearchQueryProvider);
  final status = ref.watch(invoiceStatusFilterProvider);
  final dateRange = ref.watch(invoiceDateRangeProvider);

  return service.countInvoices(
    businessId: business.id,
    status: status,
    searchQuery: searchQuery.trim().isEmpty ? null : searchQuery.trim(),
    startDate: dateRange?.start,
    endDate: dateRange?.end,
  );
});

/// Family provider for loading a specific invoice by its ID.
final invoiceDetailProvider = FutureProvider.autoDispose.family<Invoice?, String>((ref, id) async {
  final service = ref.watch(invoiceServiceProvider);
  return service.getInvoiceById(id);
});

/// Previews the next statutory sequential invoice number.
final nextInvoiceNumberPreviewProvider = FutureProvider.autoDispose<String>((ref) async {
  final business = ref.watch(activeBusinessProvider).value;
  if (business == null) return 'INV-2026-0001';

  final service = ref.watch(invoiceServiceProvider);
  return service.getNextInvoiceNumberPreview(business.id);
});
