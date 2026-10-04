import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/domain/catalog/category.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/catalog/tax_rate.dart';
import 'package:billzo/domain/catalog/unit_of_measurement.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

class CatalogItemTypeFilterNotifier extends Notifier<ItemType?> {
  @override
  ItemType? build() => null;
  void setFilter(ItemType? filter) => state = filter;
}

/// Item type filter (Goods, Service, or null for all).
final catalogItemTypeFilterProvider =
    NotifierProvider<CatalogItemTypeFilterNotifier, ItemType?>(CatalogItemTypeFilterNotifier.new);

class CatalogCategoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFilter(String? categoryId) => state = categoryId;
}

/// Category filter (Category ID or null for all).
final catalogCategoryFilterProvider =
    NotifierProvider<CatalogCategoryFilterNotifier, String?>(CatalogCategoryFilterNotifier.new);

class CatalogSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void setQuery(String query) => state = query;
}

/// Search query string for products list.
final catalogSearchQueryProvider =
    NotifierProvider<CatalogSearchQueryNotifier, String>(CatalogSearchQueryNotifier.new);

class SelectedProductNotifier extends Notifier<Product?> {
  @override
  Product? build() => null;
  void select(Product? product) => state = product;
}

/// Selected product for detail / inspection pane.
final selectedProductProvider =
    NotifierProvider<SelectedProductNotifier, Product?>(SelectedProductNotifier.new);

/// Reactive list of products filtered by type, category, and search query.
final productsListProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final businessAsync = ref.watch(activeBusinessProvider);
  final business = businessAsync.value;
  if (business == null) return [];

  final typeFilter = ref.watch(catalogItemTypeFilterProvider);
  final categoryId = ref.watch(catalogCategoryFilterProvider);
  final searchQuery = ref.watch(catalogSearchQueryProvider);
  final service = ref.watch(catalogServiceProvider);

  return service.getProducts(
    businessId: business.id,
    typeFilter: typeFilter,
    categoryId: categoryId,
    searchQuery: searchQuery,
    includeInactive: false,
    limit: 100,
  );
});

/// Reactive list of active categories for the business.
final categoriesListProvider = FutureProvider.autoDispose<List<Category>>((ref) async {
  final businessAsync = ref.watch(activeBusinessProvider);
  final business = businessAsync.value;
  if (business == null) return [];

  final service = ref.watch(catalogServiceProvider);
  return service.getCategories(business.id);
});

/// Reactive list of units of measurement for the business.
final unitsListProvider = FutureProvider.autoDispose<List<UnitOfMeasurement>>((ref) async {
  final businessAsync = ref.watch(activeBusinessProvider);
  final business = businessAsync.value;
  if (business == null) return [];

  final service = ref.watch(catalogServiceProvider);
  return service.getUnits(business.id);
});

/// Reactive list of statutory GST tax rates for the business.
final taxRatesListProvider = FutureProvider.autoDispose<List<TaxRate>>((ref) async {
  final businessAsync = ref.watch(activeBusinessProvider);
  final business = businessAsync.value;
  if (business == null) return [];

  final service = ref.watch(catalogServiceProvider);
  return service.getTaxRates(business.id);
});
