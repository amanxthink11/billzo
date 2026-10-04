import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:billzo/domain/catalog/category.dart';
import 'package:billzo/domain/catalog/category_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [ICategoryRepository].
class SqliteCategoryRepository implements ICategoryRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  SqliteCategoryRepository(this._dbHelper);

  @override
  Future<Category> createCategory(Category category) async {
    final trimmedName = category.name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Category name cannot be empty');
    }

    final db = await _dbHelper.database;
    final id = category.id.isEmpty ? _uuid.v4() : category.id;
    final now = DateTime.now().toUtc();

    final toInsert = category.copyWith(
      id: id,
      name: trimmedName,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert(
      'product_categories',
      toInsert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );

    return toInsert;
  }

  @override
  Future<Category> updateCategory(Category category) async {
    final trimmedName = category.name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Category name cannot be empty');
    }

    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final updated = category.copyWith(name: trimmedName, updatedAt: now);

    final count = await db.update(
      'product_categories',
      updated.toMap(),
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [category.id],
    );

    if (count == 0) {
      throw StateError('Category ${category.id} not found or has been deleted');
    }

    return updated;
  }

  @override
  Future<Category?> getCategoryById(String id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'product_categories',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return Category.fromMap(results.first);
  }

  @override
  Future<List<Category>> getCategories(
    String businessId, {
    bool includeInactive = false,
    String? searchQuery,
  }) async {
    final db = await _dbHelper.database;
    final StringBuffer whereClause = StringBuffer('business_id = ? AND deleted_at IS NULL');
    final List<dynamic> whereArgs = [businessId];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      whereClause.write(' AND name LIKE ?');
      whereArgs.add('%${searchQuery.trim()}%');
    }

    final results = await db.query(
      'product_categories',
      where: whereClause.toString(),
      whereArgs: whereArgs,
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return results.map(Category.fromMap).toList();
  }

  @override
  Future<void> setCategoryActiveStatus(String id, bool isActive) async {
    // In product_categories, inactive categories can be represented or soft-deleted
    final db = await _dbHelper.database;
    await db.update(
      'product_categories',
      {
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }

  @override
  Future<bool> canDeleteCategory(String id) async {
    final db = await _dbHelper.database;

    // Check if any active products reference this category
    final productRefs = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE category_id = ? AND deleted_at IS NULL',
      [id],
    );
    final int productCount = (productRefs.first['count'] as num?)?.toInt() ?? 0;
    if (productCount > 0) return false;

    // Check if any active sub-categories reference this category
    final childRefs = await db.rawQuery(
      'SELECT COUNT(*) as count FROM product_categories WHERE parent_category_id = ? AND deleted_at IS NULL',
      [id],
    );
    final int childCount = (childRefs.first['count'] as num?)?.toInt() ?? 0;
    return childCount == 0;
  }

  @override
  Future<void> softDeleteCategory(String id) async {
    final safe = await canDeleteCategory(id);
    if (!safe) {
      throw StateError(
        'Cannot delete category: existing products or sub-categories are associated with it. '
        'Reassign or delete associated items first.',
      );
    }

    final db = await _dbHelper.database;
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'product_categories',
      {
        'deleted_at': nowStr,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
