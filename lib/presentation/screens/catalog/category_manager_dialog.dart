import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/catalog/category.dart';
import 'package:billzo/presentation/providers/catalog_providers.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Modal dialog to manage product/service categories.
class CategoryManagerDialog extends ConsumerStatefulWidget {
  final String businessId;

  const CategoryManagerDialog({super.key, required this.businessId});

  @override
  ConsumerState<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends ConsumerState<CategoryManagerDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final service = ref.read(catalogServiceProvider);
      await service.createCategory(
        Category(
          id: '',
          businessId: widget.businessId,
          name: name,
          description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      _nameController.clear();
      _descController.clear();
      ref.invalidate(categoriesListProvider);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesListProvider);

    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 600),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.category_outlined, color: BillzoColors.primaryBlue, size: 24),
                  const SizedBox(width: 12),
                  const Text('Manage Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),

            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                color: BillzoColors.dangerRed.withValues(alpha: 0.1),
                child: Text(_error!, style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13)),
              ),

            // Add Category Form
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'New Category Name *',
                        hintText: 'e.g. Electronics, Services',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isCreating ? null : _addCategory,
                    child: _isCreating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Add'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // List of Categories
            Expanded(
              child: categoriesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Error: $e')),
                data: (categories) {
                  if (categories.isEmpty) {
                    return const Center(
                      child: Text('No categories created yet.', style: TextStyle(color: BillzoColors.neutralText)),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    itemCount: categories.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.folder_outlined, size: 18, color: BillzoColors.primaryBlue),
                        ),
                        title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: cat.description != null ? Text(cat.description!, style: const TextStyle(fontSize: 12)) : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: BillzoColors.dangerRed),
                          tooltip: 'Delete Category',
                          onPressed: () async {
                            try {
                              final service = ref.read(catalogServiceProvider);
                              await service.deleteCategory(cat.id);
                              ref.invalidate(categoriesListProvider);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.toString().replaceFirst('StateError: ', '')),
                                    backgroundColor: BillzoColors.dangerRed,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
