import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/catalog/product_repository.dart';
import 'package:billzo/domain/catalog/product_validator.dart';
import 'package:billzo/domain/inventory/inventory_ledger_entry.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [IProductRepository] with stock ledger tracking.
class SqliteProductRepository implements IProductRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  SqliteProductRepository(this._dbHelper);

  @override
  Future<Product> createProduct(Product product, {String? openingStockNotes}) async {
    // 1. Domain validation
    final validation = ProductValidator.validate(product);
    if (validation.hasErrors) {
      throw ArgumentError(
        'Validation failed for product: ${validation.errors.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
      );
    }

    // 2. SKU uniqueness check
    if (product.sku != null && product.sku!.trim().isNotEmpty) {
      final taken = await isSkuTaken(product.businessId, product.sku!.trim());
      if (taken) {
        throw StateError('SKU "${product.sku!.trim()}" is already assigned to another item in this business');
      }
    }

    final id = product.id.isEmpty ? _uuid.v4() : product.id;
    final now = DateTime.now().toUtc();
    final initialStock = product.isGoods ? product.openingStock : 0.0;

    final toInsert = product.copyWith(
      id: id,
      name: product.name.trim(),
      sku: product.sku?.trim().toUpperCase(),
      hsnSacCode: product.hsnSacCode?.trim(),
      openingStock: initialStock,
      currentStock: initialStock,
      createdAt: now,
      updatedAt: now,
    );

    // 3. Atomically persist product and opening stock movement in stock_movements
    await _dbHelper.transaction((txn) async {
      var taxRateId = toInsert.taxRateId;
      if (taxRateId == null || taxRateId.isEmpty) {
        // Fallback to active 0% tax rate or any existing tax rate for business
        final taxRates = await txn.query(
          'tax_rates',
          columns: ['id'],
          where: 'business_id = ?',
          whereArgs: [toInsert.businessId],
          orderBy: 'rate_basis_points ASC',
          limit: 1,
        );
        if (taxRates.isNotEmpty) {
          taxRateId = taxRates.first['id'] as String;
        }
      }

      final finalProduct = toInsert.copyWith(taxRateId: taxRateId);

      await txn.insert(
        'products',
        finalProduct.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );

      if (finalProduct.isGoods && finalProduct.openingStock > 0.0) {
        final scaledQty = (finalProduct.openingStock * 1000).round();
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'business_id': finalProduct.businessId,
          'product_id': finalProduct.id,
          'reference_id': finalProduct.id,
          'reference_type': 'OPENING_STOCK',
          'movement_date': now.toIso8601String(),
          'quantity_delta': scaledQty,
          'balance_after': scaledQty,
          'unit_cost_paise': finalProduct.purchasePricePaise,
          'notes': openingStockNotes ?? 'Opening Stock Entry',
          'created_at': now.toIso8601String(),
        });
      }
    });

    return toInsert;
  }

  @override
  Future<Product> updateProduct(Product product) async {
    final validation = ProductValidator.validate(product);
    if (validation.hasErrors) {
      throw ArgumentError(
        'Validation failed for product: ${validation.errors.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
      );
    }

    if (product.sku != null && product.sku!.trim().isNotEmpty) {
      final taken = await isSkuTaken(
        product.businessId,
        product.sku!.trim(),
        excludeProductId: product.id,
      );
      if (taken) {
        throw StateError('SKU "${product.sku!.trim()}" is already assigned to another item');
      }
    }

    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final updated = product.copyWith(
      name: product.name.trim(),
      sku: product.sku?.trim().toUpperCase(),
      hsnSacCode: product.hsnSacCode?.trim(),
      updatedAt: now,
    );

    final count = await db.update(
      'products',
      updated.toMap(),
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [product.id],
    );

    if (count == 0) {
      throw StateError('Product ${product.id} not found or has been deleted');
    }

    return updated;
  }

  @override
  Future<Product?> getProductById(String id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'products',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return Product.fromMap(results.first);
  }

  @override
  Future<List<Product>> getProducts({
    required String businessId,
    ItemType? typeFilter,
    String? categoryId,
    String? searchQuery,
    bool includeInactive = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    final queryData = _buildProductQuery(
      businessId: businessId,
      typeFilter: typeFilter,
      categoryId: categoryId,
      searchQuery: searchQuery,
      includeInactive: includeInactive,
    );

    final results = await db.query(
      'products',
      where: queryData.whereClause,
      whereArgs: queryData.whereArgs,
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
      offset: offset,
    );

    return results.map(Product.fromMap).toList();
  }

  @override
  Future<int> countProducts({
    required String businessId,
    ItemType? typeFilter,
    String? categoryId,
    String? searchQuery,
    bool includeInactive = false,
  }) async {
    final db = await _dbHelper.database;
    final queryData = _buildProductQuery(
      businessId: businessId,
      typeFilter: typeFilter,
      categoryId: categoryId,
      searchQuery: searchQuery,
      includeInactive: includeInactive,
    );

    final results = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE ${queryData.whereClause}',
      queryData.whereArgs,
    );

    if (results.isEmpty) return 0;
    return (results.first['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<bool> isSkuTaken(String businessId, String sku, {String? excludeProductId}) async {
    final db = await _dbHelper.database;
    final StringBuffer where = StringBuffer(
      'business_id = ? AND UPPER(sku) = ? AND deleted_at IS NULL',
    );
    final List<dynamic> args = [businessId, sku.toUpperCase()];

    if (excludeProductId != null) {
      where.write(' AND id != ?');
      args.add(excludeProductId);
    }

    final results = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE ${where.toString()}',
      args,
    );

    final count = results.isNotEmpty ? ((results.first['count'] as num?)?.toInt() ?? 0) : 0;
    return count > 0;
  }

  @override
  Future<bool> isProductNameTaken(String businessId, String name, {String? excludeProductId}) async {
    final db = await _dbHelper.database;
    final StringBuffer where = StringBuffer(
      'business_id = ? AND LOWER(name) = ? AND deleted_at IS NULL',
    );
    final List<dynamic> args = [businessId, name.trim().toLowerCase()];

    if (excludeProductId != null && excludeProductId.isNotEmpty) {
      where.write(' AND id != ?');
      args.add(excludeProductId);
    }

    final results = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE ${where.toString()}',
      args,
    );

    final count = results.isNotEmpty ? ((results.first['count'] as num?)?.toInt() ?? 0) : 0;
    return count > 0;
  }

  @override
  Future<void> setProductActiveStatus(String id, bool isActive) async {
    final db = await _dbHelper.database;
    await db.update(
      'products',
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  @override
  Future<void> softDeleteProduct(String id) async {
    final db = await _dbHelper.database;
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'products',
      {
        'is_active': 0,
        'deleted_at': nowStr,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<InventoryLedgerEntry>> getStockLedger(String productId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'movement_date DESC, created_at DESC',
    );
    return results.map((row) {
      final qtyScaled = row['quantity_delta'] as int? ?? 0;
      final balanceScaled = row['balance_after'] as int? ?? 0;
      return InventoryLedgerEntry(
        id: row['id'] as String,
        businessId: row['business_id'] as String,
        productId: row['product_id'] as String,
        transactionType: (row['reference_type'] as String? ?? 'OPENING_STOCK').toLowerCase(),
        referenceType: 'MANUAL',
        referenceId: row['reference_id'] as String,
        quantityChanged: qtyScaled / 1000.0,
        stockBefore: (balanceScaled - qtyScaled) / 1000.0,
        stockAfter: balanceScaled / 1000.0,
        costPerUnitPaise: row['unit_cost_paise'] as int? ?? 0,
        notes: row['notes'] as String?,
        transactionDate: DateTime.parse(row['movement_date'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  _ProductQueryData _buildProductQuery({
    required String businessId,
    ItemType? typeFilter,
    String? categoryId,
    String? searchQuery,
    bool includeInactive = false,
  }) {
    final StringBuffer whereClause = StringBuffer('business_id = ? AND deleted_at IS NULL');
    final List<dynamic> whereArgs = [businessId];

    if (!includeInactive) {
      whereClause.write(' AND is_active = 1');
    }

    if (typeFilter != null) {
      whereClause.write(' AND track_inventory = ?');
      whereArgs.add(typeFilter == ItemType.product ? 1 : 0);
    }

    if (categoryId != null && categoryId.isNotEmpty) {
      whereClause.write(' AND category_id = ?');
      whereArgs.add(categoryId);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      whereClause.write(' AND (name LIKE ? OR sku LIKE ? OR hsn_sac LIKE ?)');
      whereArgs.addAll([term, term, term]);
    }

    return _ProductQueryData(whereClause.toString(), whereArgs);
  }
}

class _ProductQueryData {
  final String whereClause;
  final List<dynamic> whereArgs;
  _ProductQueryData(this.whereClause, this.whereArgs);
}
