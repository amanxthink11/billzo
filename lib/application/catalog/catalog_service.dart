import 'package:billzo/domain/catalog/category.dart';
import 'package:billzo/domain/catalog/category_repository.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/catalog/product_repository.dart';
import 'package:billzo/domain/catalog/tax_rate.dart';
import 'package:billzo/domain/catalog/tax_rate_repository.dart';
import 'package:billzo/domain/catalog/unit_of_measurement.dart';
import 'package:billzo/domain/catalog/unit_repository.dart';
import 'package:billzo/domain/inventory/inventory_ledger_entry.dart';

/// Application service orchestrating the Product Catalog, Categories, Units, and Tax Rates.
class CatalogService {
  final IProductRepository _productRepository;
  final ICategoryRepository _categoryRepository;
  final IUnitRepository _unitRepository;
  final ITaxRateRepository _taxRateRepository;

  CatalogService(
    this._productRepository,
    this._categoryRepository,
    this._unitRepository,
    this._taxRateRepository,
  );

  // Products & Services
  Future<Product> createProduct(Product product, {String? openingStockNotes}) async {
    return _productRepository.createProduct(product, openingStockNotes: openingStockNotes);
  }

  Future<Product> updateProduct(Product product) async {
    return _productRepository.updateProduct(product);
  }

  Future<Product?> getProductById(String id) async {
    return _productRepository.getProductById(id);
  }

  Future<List<Product>> getProducts({
    required String businessId,
    ItemType? typeFilter,
    String? categoryId,
    String? searchQuery,
    bool includeInactive = false,
    int limit = 50,
    int offset = 0,
  }) async {
    return _productRepository.getProducts(
      businessId: businessId,
      typeFilter: typeFilter,
      categoryId: categoryId,
      searchQuery: searchQuery,
      includeInactive: includeInactive,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> countProducts({
    required String businessId,
    ItemType? typeFilter,
    String? categoryId,
    String? searchQuery,
    bool includeInactive = false,
  }) async {
    return _productRepository.countProducts(
      businessId: businessId,
      typeFilter: typeFilter,
      categoryId: categoryId,
      searchQuery: searchQuery,
      includeInactive: includeInactive,
    );
  }

  Future<void> deactivateProduct(String id) async {
    await _productRepository.setProductActiveStatus(id, false);
  }

  Future<void> reactivateProduct(String id) async {
    await _productRepository.setProductActiveStatus(id, true);
  }

  Future<void> deleteProduct(String id) async {
    await _productRepository.softDeleteProduct(id);
  }

  Future<List<InventoryLedgerEntry>> getStockLedger(String productId) async {
    return _productRepository.getStockLedger(productId);
  }

  // Categories
  Future<Category> createCategory(Category category) async {
    return _categoryRepository.createCategory(category);
  }

  Future<Category> updateCategory(Category category) async {
    return _categoryRepository.updateCategory(category);
  }

  Future<List<Category>> getCategories(String businessId, {bool includeInactive = false, String? searchQuery}) async {
    return _categoryRepository.getCategories(businessId, includeInactive: includeInactive, searchQuery: searchQuery);
  }

  Future<void> deleteCategory(String id) async {
    await _categoryRepository.softDeleteCategory(id);
  }

  // Units
  Future<UnitOfMeasurement> createUnit(UnitOfMeasurement unit) async {
    return _unitRepository.createUnit(unit);
  }

  Future<List<UnitOfMeasurement>> getUnits(String businessId) async {
    return _unitRepository.getUnits(businessId);
  }

  // Tax Rates
  Future<List<TaxRate>> getTaxRates(String businessId, {bool includeInactive = false}) async {
    return _taxRateRepository.getTaxRates(businessId, includeInactive: includeInactive);
  }
}
