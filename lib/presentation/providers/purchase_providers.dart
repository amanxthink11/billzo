import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_repository.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Search query state for purchases list.
class PurchaseSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  @override
  set state(String value) => super.state = value;
}

final purchaseSearchQueryProvider =
    NotifierProvider<PurchaseSearchQueryNotifier, String>(PurchaseSearchQueryNotifier.new);

/// Selected status filter for purchases list.
class PurchaseStatusFilterNotifier extends Notifier<PurchaseStatus?> {
  @override
  PurchaseStatus? build() => null;

  @override
  set state(PurchaseStatus? value) => super.state = value;
}

final purchaseStatusFilterProvider =
    NotifierProvider<PurchaseStatusFilterNotifier, PurchaseStatus?>(PurchaseStatusFilterNotifier.new);

/// Selected supplier filter for purchases list.
class PurchaseSupplierFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  @override
  set state(String? value) => super.state = value;
}

final purchaseSupplierFilterProvider =
    NotifierProvider<PurchaseSupplierFilterNotifier, String?>(PurchaseSupplierFilterNotifier.new);

/// Selected date range filter for purchases list.
class PurchaseDateRangeNotifier extends Notifier<DateTimeRange?> {
  @override
  DateTimeRange? build() => null;

  @override
  set state(DateTimeRange? value) => super.state = value;
}

final purchaseDateRangeProvider =
    NotifierProvider<PurchaseDateRangeNotifier, DateTimeRange?>(PurchaseDateRangeNotifier.new);

/// Reactive list of purchase bills matching the active business and filters.
final purchasesListProvider = FutureProvider.autoDispose<List<Purchase>>((ref) async {
  final business = ref.watch(activeBusinessProvider).value;
  if (business == null) return [];

  final service = ref.watch(purchaseServiceProvider);
  final searchQuery = ref.watch(purchaseSearchQueryProvider);
  final status = ref.watch(purchaseStatusFilterProvider);
  final supplierId = ref.watch(purchaseSupplierFilterProvider);
  final dateRange = ref.watch(purchaseDateRangeProvider);

  return service.getPurchases(
    businessId: business.id,
    status: status,
    supplierId: supplierId,
    searchQuery: searchQuery.trim().isEmpty ? null : searchQuery.trim(),
    startDate: dateRange?.start,
    endDate: dateRange?.end,
    limit: 100,
  );
});

/// Count of purchase bills matching the active filters.
final purchasesCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final business = ref.watch(activeBusinessProvider).value;
  if (business == null) return 0;

  final service = ref.watch(purchaseServiceProvider);
  final searchQuery = ref.watch(purchaseSearchQueryProvider);
  final status = ref.watch(purchaseStatusFilterProvider);
  final supplierId = ref.watch(purchaseSupplierFilterProvider);
  final dateRange = ref.watch(purchaseDateRangeProvider);

  return service.countPurchases(
    businessId: business.id,
    status: status,
    supplierId: supplierId,
    searchQuery: searchQuery.trim().isEmpty ? null : searchQuery.trim(),
    startDate: dateRange?.start,
    endDate: dateRange?.end,
  );
});

/// Family provider for loading a specific purchase bill by its ID.
final purchaseDetailProvider = FutureProvider.autoDispose.family<Purchase?, String>((ref, id) async {
  final service = ref.watch(purchaseServiceProvider);
  return service.getPurchaseById(id);
});

/// Previews the next statutory internal purchase number.
final nextPurchaseNumberPreviewProvider = FutureProvider.autoDispose<String>((ref) async {
  final business = ref.watch(activeBusinessProvider).value;
  if (business == null) return 'PUR-2026-0001';

  final service = ref.watch(purchaseServiceProvider);
  return service.getNextPurchaseNumberPreview(business.id);
});

/// Provider for supplier accounts payable summary.
final supplierAPSummaryProvider =
    FutureProvider.autoDispose.family<SupplierAccountsPayableSummary, String>((ref, supplierId) async {
  final business = ref.watch(activeBusinessProvider).value;
  if (business == null) {
    return const SupplierAccountsPayableSummary();
  }

  final service = ref.watch(purchaseServiceProvider);
  return service.getSupplierAccountsPayableSummary(business.id, supplierId);
});

/// Provider for outstanding purchases of a supplier.
final supplierOutstandingPurchasesProvider =
    FutureProvider.autoDispose.family<List<Purchase>, String>((ref, supplierId) async {
  final business = ref.watch(activeBusinessProvider).value;
  if (business == null) return [];

  final service = ref.watch(purchaseServiceProvider);
  return service.getOutstandingPurchasesForSupplier(business.id, supplierId);
});
