import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/catalog/tax_rate.dart';
import 'package:billzo/domain/catalog/unit_of_measurement.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/screens/catalog/product_form_dialog.dart';

/// Modal dialog for rapid product/service search and selection in the invoice builder.
class ProductSelectDialog extends ConsumerStatefulWidget {
  final String businessId;

  const ProductSelectDialog({
    super.key,
    required this.businessId,
  });

  @override
  ConsumerState<ProductSelectDialog> createState() => _ProductSelectDialogState();
}

class _ProductSelectDialogState extends ConsumerState<ProductSelectDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  Map<String, UnitOfMeasurement> _unitsMap = {};
  Map<String, TaxRate> _taxRatesMap = {};
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final productRepo = ref.read(productRepositoryProvider);
    final unitRepo = ref.read(unitRepositoryProvider);
    final taxRateRepo = ref.read(taxRateRepositoryProvider);

    try {
      final units = await unitRepo.getUnits(widget.businessId);
      final taxRates = await taxRateRepo.getTaxRates(widget.businessId);
      final products = await productRepo.getProducts(
        businessId: widget.businessId,
        searchQuery: _query.trim().isEmpty ? null : _query.trim(),
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _unitsMap = {for (final u in units) u.id: u};
          _taxRatesMap = {for (final t in taxRates) t.id: t};
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Product / Service',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar + Add Product Button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search by item name, SKU, or HSN/SAC code...',
                        prefixIcon: const Icon(Icons.search, size: 20, color: BillzoColors.neutralText),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _query = '';
                                  _loadData();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: BillzoColors.border),
                        ),
                      ),
                      onChanged: (val) {
                        _query = val;
                        _loadData();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: const Text('New Item'),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final newProduct = await showDialog<Product>(
                        context: context,
                        builder: (_) => ProductFormDialog(businessId: widget.businessId),
                      );
                      if (newProduct != null) {
                        nav.pop(newProduct);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Product List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _products.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 48, color: BillzoColors.neutralText),
                                const SizedBox(height: 8),
                                Text(
                                  _query.isEmpty ? 'No items found in catalog' : 'No matching items for "$_query"',
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: BillzoColors.neutralText),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Click "+ New Item" above to add products to your catalog.',
                                  style: TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _products.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, color: BillzoColors.border),
                            itemBuilder: (context, index) {
                              final product = _products[index];
                              final unit = _unitsMap[product.unitId];
                              final taxRate = product.taxRateId != null ? _taxRatesMap[product.taxRateId] : null;
                              final unitCode = unit?.code ?? 'PCS';
                              final taxDisplay = taxRate != null ? '${(taxRate.rateBasisPoints / 100).toStringAsFixed(0)}%' : '0%';

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: product.isGoods ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    product.isGoods ? Icons.inventory_2_outlined : Icons.design_services_outlined,
                                    size: 20,
                                    color: product.isGoods ? BillzoColors.successGreen : BillzoColors.primaryBlue,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        product.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '₹${product.sellingPrice.toIndianRupeeString()}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: BillzoColors.primaryBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        if (product.sku != null && product.sku!.isNotEmpty) ...[
                                          Text('SKU: ${product.sku!}', style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                                          const SizedBox(width: 8),
                                        ],
                                        if (product.hsnSacCode != null && product.hsnSacCode!.isNotEmpty) ...[
                                          Text('${product.isService ? 'SAC' : 'HSN'}: ${product.hsnSacCode!}', style: const TextStyle(fontSize: 11, color: BillzoColors.neutralText)),
                                          const SizedBox(width: 8),
                                        ],
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('GST: $taxDisplay', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                                        ),
                                        const SizedBox(width: 6),
                                        if (product.isTaxInclusive)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEF3C7),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('MRP Inclusive', style: TextStyle(fontSize: 10, color: Color(0xFF92400E))),
                                          ),
                                      ],
                                    ),
                                    if (product.isGoods)
                                      Row(
                                        children: [
                                          Icon(
                                            product.currentStock <= (product.lowStockThreshold ?? 5)
                                                ? Icons.warning_amber_rounded
                                                : Icons.check_circle_outline,
                                            size: 14,
                                            color: product.currentStock <= (product.lowStockThreshold ?? 5)
                                                ? BillzoColors.dangerRed
                                                : BillzoColors.successGreen,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Stock: ${product.currentStock.toStringAsFixed(unit?.allowDecimal == true ? 2 : 0)} $unitCode',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: product.currentStock <= (product.lowStockThreshold ?? 5)
                                                  ? BillzoColors.dangerRed
                                                  : BillzoColors.darkSlate,
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      const Text(
                                        'Service (No Stock)',
                                        style: TextStyle(fontSize: 11, color: BillzoColors.neutralText, fontStyle: FontStyle.italic),
                                      ),
                                  ],
                                ),
                                hoverColor: const Color(0xFFEFF6FF),
                                onTap: () => Navigator.of(context).pop(product),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
