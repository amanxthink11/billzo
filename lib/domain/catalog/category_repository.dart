import 'package:billzo/domain/catalog/category.dart';

/// Repository interface for Category persistence and lifecycle management.
abstract class ICategoryRepository {
  Future<Category> createCategory(Category category);
  Future<Category> updateCategory(Category category);
  Future<Category?> getCategoryById(String id);
  Future<List<Category>> getCategories(String businessId, {bool includeInactive = false, String? searchQuery});
  Future<void> setCategoryActiveStatus(String id, bool isActive);
  Future<bool> canDeleteCategory(String id);
  Future<void> softDeleteCategory(String id);
}
