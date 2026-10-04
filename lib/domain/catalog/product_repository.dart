import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/inventory/inventory_ledger_entry.dart';

/// Repository interface for Product and Service catalog persistence.
abstract class IProductRepository {
  /// Creates a new product. If opening stock > 0, atomically inserts an opening_stock inventory ledger entry.
  Future<Product> createProduct(Product product, {String? openingStockNotes});

  /// Updates an existing product.
  Future<Product> updateProduct(Product product);

  /// Retrieves a product by ID.
  Future<Product?> getProductById(String id);

  /// Queries paginated products with filtering and search.
  Future<List<Product>> getProducts({
    required String businessId,
    ItemType? typeFilter,
    String? categoryId,
    String? searchQuery,
    bool includeInactive = false,
    int limit = 50,
    int offset = 0,
  });

  /// Counts matching products for pagination.
  Future<int> countProducts({
    required String businessId,
    ItemType? typeFilter,
    String? categoryId,
    String? searchQuery,
    bool includeInactive = false,
  });

  /// Checks if an SKU is already used within the business.
  Future<bool> isSkuTaken(String businessId, String sku, {String? excludeProductId});

  /// Checks if a product/service name is already used within the business (case-insensitive).
  Future<bool> isProductNameTaken(String businessId, String name, {String? excludeProductId});

  /// Toggles active/inactive state.
  Future<void> setProductActiveStatus(String id, bool isActive);

  /// Marks product as deleted (soft delete).
  Future<void> softDeleteProduct(String id);

  /// Returns stock movements recorded in the inventory ledger.
  Future<List<InventoryLedgerEntry>> getStockLedger(String productId);
}
