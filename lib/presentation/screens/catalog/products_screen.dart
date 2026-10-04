import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/presentation/providers/catalog_providers.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/screens/catalog/category_manager_dialog.dart';
import 'package:billzo/presentation/screens/catalog/product_form_dialog.dart';
import 'package:billzo/presentation/screens/catalog/stock_ledger_dialog.dart';
import 'package:billzo/presentation/screens/catalog/unit_manager_dialog.dart';

/// Desktop-first view for managing the Product and Service Catalog.
class ProductsScreen extends ConsumerStatefulWidget {
  final Business business;

  const ProductsScreen({super.key, required this.business});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTypeFilter = ref.watch(catalogItemTypeFilterProvider);
    final productsAsync = ref.watch(productsListProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final unitsAsync = ref.watch(unitsListProvider);
    final taxRatesAsync = ref.watch(taxRatesListProvider);

    // Build lookup maps for categories, units, and tax rates
    final categoriesMap = {
      for (final c in categoriesAsync.value ?? <dynamic>[]) c.id: c.name,
    };
    final unitsMap = {
      for (final u in unitsAsync.value ?? <dynamic>[]) u.id: u.shortName,
    };
    final taxRatesMap = {
      for (final t in taxRatesAsync.value ?? <dynamic>[]) t.id: t.displayPercentage,
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Action Header
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Search Input
                  SizedBox(
                    width: 280,
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by item name, SKU, HSN...',
                        prefixIcon: const Icon(Icons.search, size: 18, color: BillzoColors.neutralText),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(catalogSearchQueryProvider.notifier).setQuery('');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: BillzoColors.border),
                        ),
                      ),
                      onChanged: (val) {
                        ref.read(catalogSearchQueryProvider.notifier).setQuery(val);
                      },
                    ),
                  ),

                  // Filter Chips
                  SegmentedButton<ItemType?>(
                    segments: const [
                      ButtonSegment(value: null, label: Text('All')),
                      ButtonSegment(value: ItemType.product, label: Text('Goods')),
                      ButtonSegment(value: ItemType.service, label: Text('Services')),
                    ],
                    selected: {activeTypeFilter},
                    onSelectionChanged: (set) {
                      ref.read(catalogItemTypeFilterProvider.notifier).setFilter(set.first);
                    },
                  ),
                ],
              ),

              // Actions
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Catalog Management Helpers
                  OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => CategoryManagerDialog(businessId: widget.business.id),
                      );
                    },
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: const Text('Categories'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => UnitManagerDialog(businessId: widget.business.id),
                      );
                    },
                    icon: const Icon(Icons.straighten_outlined, size: 18),
                    label: const Text('Units'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openProductForm(ItemType.service),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Service'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openProductForm(ItemType.product),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Product'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Catalog Table Canvas
          Expanded(
            child: Card(
              child: productsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Text('Error loading products: $err', style: const TextStyle(color: BillzoColors.dangerRed)),
                ),
                data: (products) {
                  if (products.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          headingRowHeight: 48,
                          dataRowMinHeight: 52,
                          dataRowMaxHeight: 58,
                          headingRowColor: WidgetStateProperty.all(BillzoColors.canvasLight),
                          columns: const [
                            DataColumn(label: Text('ITEM NAME & SKU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('CATEGORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('HSN/SAC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('SELLING PRICE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('PURCHASE PRICE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('GST TAX', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('STOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                            DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillzoColors.neutralText))),
                          ],
                          rows: products.map((p) {
                            final unitName = unitsMap[p.unitId] ?? '';
                            final categoryName = p.categoryId != null ? categoriesMap[p.categoryId] : null;
                            final taxRateName = p.taxRateId != null ? taxRatesMap[p.taxRateId] : 'Exempt';

                            return DataRow(
                              cells: [
                                // Name & SKU
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            p.name,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          if (p.isService) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.purple.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('SVC', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.purple)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (p.sku != null)
                                        Text(
                                          'SKU: ${p.sku}',
                                          style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText, fontFamily: 'monospace'),
                                        ),
                                    ],
                                  ),
                                ),

                                // Category
                                DataCell(
                                  Text(
                                    categoryName ?? '—',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),

                                // HSN/SAC
                                DataCell(
                                  Text(
                                    p.hsnSacCode ?? '—',
                                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                                  ),
                                ),

                                // Selling Price
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        p.sellingPrice.formattedWithSymbol,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                      if (p.isTaxInclusive)
                                        const Text('Incl. GST', style: TextStyle(fontSize: 10, color: BillzoColors.neutralText)),
                                    ],
                                  ),
                                ),

                                // Purchase Price
                                DataCell(
                                  Text(
                                    p.purchasePricePaise > 0 ? p.purchasePrice.formattedWithSymbol : '—',
                                    style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                  ),
                                ),

                                // Tax Rate
                                DataCell(
                                  Text(
                                    taxRateName ?? 'Exempt',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),

                                // Stock Level
                                DataCell(
                                  p.isGoods
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${p.currentStock} $unitName',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: p.isLowStock ? BillzoColors.dangerRed : BillzoColors.darkSlate,
                                              ),
                                            ),
                                            if (p.isLowStock) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: BillzoColors.dangerRed.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text('LOW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: BillzoColors.dangerRed)),
                                              ),
                                            ],
                                          ],
                                        )
                                      : const Text('—', style: TextStyle(color: BillzoColors.neutralText)),
                                ),

                                // Actions
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (p.isGoods)
                                        IconButton(
                                          icon: const Icon(Icons.history, size: 18),
                                          tooltip: 'Stock Ledger History',
                                          onPressed: () => _openStockLedger(p),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        tooltip: 'Edit Item',
                                        onPressed: () => _openProductForm(p.itemType, productToEdit: p),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: BillzoColors.dangerRed),
                                        tooltip: 'Delete Item',
                                        onPressed: () => _confirmDelete(p),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inventory_2_outlined, size: 36, color: BillzoColors.primaryBlue),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Products or Services Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add items to your catalog with prices, GST tax rates, and initial opening stock.',
              style: TextStyle(color: BillzoColors.neutralText, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openProductForm(ItemType.service),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Service'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _openProductForm(ItemType.product),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Product'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openProductForm(ItemType defaultType, {Product? productToEdit}) {
    showDialog(
      context: context,
      builder: (_) => ProductFormDialog(
        businessId: widget.business.id,
        initialItemType: defaultType,
        productToEdit: productToEdit,
      ),
    );
  }

  void _openStockLedger(Product product) {
    showDialog(
      context: context,
      builder: (_) => StockLedgerDialog(product: product),
    );
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to delete "${product.name}"? The item will be soft-deleted to maintain invoice and inventory audit integrity.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BillzoColors.dangerRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final service = ref.read(catalogServiceProvider);
      await service.deleteProduct(product.id);
      ref.invalidate(productsListProvider);
    }
  }
}
