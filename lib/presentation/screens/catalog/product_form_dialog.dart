import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/presentation/providers/catalog_providers.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/screens/catalog/category_manager_dialog.dart';
import 'package:billzo/presentation/screens/catalog/unit_manager_dialog.dart';

/// Modal dialog for creating and editing Products and Services.
class ProductFormDialog extends ConsumerStatefulWidget {
  final String businessId;
  final Product? productToEdit;
  final ItemType initialItemType;

  const ProductFormDialog({
    super.key,
    required this.businessId,
    this.productToEdit,
    this.initialItemType = ItemType.product,
  });

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late ItemType _itemType;
  late TextEditingController _nameController;
  late TextEditingController _skuController;
  late TextEditingController _barcodeController;
  late TextEditingController _hsnSacController;
  late TextEditingController _descriptionController;

  late TextEditingController _sellingPriceController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _mrpController;
  late TextEditingController _wholesalePriceController;

  bool _isTaxInclusive = false;
  String? _selectedCategoryId;
  String? _selectedUnitId;
  String? _selectedTaxRateId;

  late TextEditingController _openingStockController;
  late TextEditingController _openingStockNoteController;
  late TextEditingController _lowStockThresholdController;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;
    _itemType = p?.itemType ?? widget.initialItemType;

    _nameController = TextEditingController(text: p?.name ?? '');
    _skuController = TextEditingController(text: p?.sku ?? '');
    _barcodeController = TextEditingController(text: p?.barcode ?? '');
    _hsnSacController = TextEditingController(text: p?.hsnSacCode ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');

    _sellingPriceController = TextEditingController(
      text: p != null ? (p.sellingPricePaise / 100).toStringAsFixed(2) : '',
    );
    _purchasePriceController = TextEditingController(
      text: p != null && p.purchasePricePaise > 0 ? (p.purchasePricePaise / 100).toStringAsFixed(2) : '',
    );
    _mrpController = TextEditingController(
      text: p?.mrpPaise != null ? (p!.mrpPaise! / 100).toStringAsFixed(2) : '',
    );
    _wholesalePriceController = TextEditingController(
      text: p?.wholesalePricePaise != null ? (p!.wholesalePricePaise! / 100).toStringAsFixed(2) : '',
    );

    _isTaxInclusive = p?.isTaxInclusive ?? false;
    _selectedCategoryId = p?.categoryId;
    _selectedUnitId = p?.unitId;
    _selectedTaxRateId = p?.taxRateId;

    _openingStockController = TextEditingController(
      text: p != null && p.openingStock > 0 ? p.openingStock.toString() : '0',
    );
    _openingStockNoteController = TextEditingController(text: 'Initial opening stock entry');
    _lowStockThresholdController = TextEditingController(
      text: p?.lowStockThreshold != null ? p!.lowStockThreshold.toString() : '5',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _hsnSacController.dispose();
    _descriptionController.dispose();
    _sellingPriceController.dispose();
    _purchasePriceController.dispose();
    _mrpController.dispose();
    _wholesalePriceController.dispose();
    _openingStockController.dispose();
    _openingStockNoteController.dispose();
    _lowStockThresholdController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUnitId == null || _selectedUnitId!.isEmpty) {
      setState(() {
        _errorMessage = 'Please select a unit of measurement';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final name = _nameController.text.trim();
      final isNameTaken = await ref.read(productRepositoryProvider).isProductNameTaken(
        widget.businessId,
        name,
        excludeProductId: widget.productToEdit?.id,
      );
      if (isNameTaken) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'An item named "$name" already exists in your catalog.';
        });
        return;
      }

      final sellingRupees = double.tryParse(_sellingPriceController.text.trim()) ?? 0;
      final sellingPaise = (sellingRupees * 100).round();

      final purchaseRupees = double.tryParse(_purchasePriceController.text.trim()) ?? 0;
      final purchasePaise = (purchaseRupees * 100).round();

      int? mrpPaise;
      if (_mrpController.text.trim().isNotEmpty) {
        final mrpRupees = double.tryParse(_mrpController.text.trim());
        if (mrpRupees != null) mrpPaise = (mrpRupees * 100).round();
      }

      int? wholesalePaise;
      if (_wholesalePriceController.text.trim().isNotEmpty) {
        final wholesaleRupees = double.tryParse(_wholesalePriceController.text.trim());
        if (wholesaleRupees != null) wholesalePaise = (wholesaleRupees * 100).round();
      }

      final openingStock = _itemType == ItemType.service
          ? 0.0
          : (double.tryParse(_openingStockController.text.trim()) ?? 0.0);

      final lowStockThreshold = _itemType == ItemType.service
          ? null
          : (double.tryParse(_lowStockThresholdController.text.trim()) ?? 5.0);

      final product = Product(
        id: widget.productToEdit?.id ?? '',
        businessId: widget.businessId,
        categoryId: _selectedCategoryId,
        unitId: _selectedUnitId!,
        taxRateId: _selectedTaxRateId,
        name: _nameController.text.trim(),
        sku: _skuController.text.trim().isNotEmpty ? _skuController.text.trim().toUpperCase() : null,
        barcode: _barcodeController.text.trim().isNotEmpty ? _barcodeController.text.trim() : null,
        hsnSacCode: _hsnSacController.text.trim().isNotEmpty ? _hsnSacController.text.trim() : null,
        description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
        itemType: _itemType,
        purchasePricePaise: purchasePaise,
        sellingPricePaise: sellingPaise,
        mrpPaise: mrpPaise,
        wholesalePricePaise: wholesalePaise,
        isTaxInclusive: _isTaxInclusive,
        openingStock: widget.productToEdit?.openingStock ?? openingStock,
        currentStock: widget.productToEdit?.currentStock ?? openingStock,
        lowStockThreshold: lowStockThreshold,
        isActive: widget.productToEdit?.isActive ?? true,
        createdAt: widget.productToEdit?.createdAt ?? DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final service = ref.read(catalogServiceProvider);
      if (widget.productToEdit == null) {
        await service.createProduct(
          product,
          openingStockNotes: _openingStockNoteController.text.trim(),
        );
      } else {
        await service.updateProduct(product);
      }

      ref.invalidate(productsListProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '').replaceFirst('StateError: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.productToEdit != null;
    final categoriesAsync = ref.watch(categoriesListProvider);
    final unitsAsync = ref.watch(unitsListProvider);
    final taxRatesAsync = ref.watch(taxRatesListProvider);

    return Dialog(
      backgroundColor: BillzoColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
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
                  Icon(
                    _itemType == ItemType.product ? Icons.inventory_2_outlined : Icons.miscellaneous_services_outlined,
                    color: BillzoColors.primaryBlue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'Edit Item' : 'Add New ${_itemType.displayName}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                color: BillzoColors.dangerRed.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 18, color: BillzoColors.dangerRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!, style: const TextStyle(color: BillzoColors.dangerRed, fontSize: 13)),
                    ),
                  ],
                ),
              ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Item Type Selector
                      const Text('Item Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate)),
                      const SizedBox(height: 8),
                      SegmentedButton<ItemType>(
                        segments: const [
                          ButtonSegment(value: ItemType.product, label: Text('Goods (Inventory Tracked)')),
                          ButtonSegment(value: ItemType.service, label: Text('Service (No Stock)')),
                        ],
                        selected: {_itemType},
                        onSelectionChanged: isEditing
                            ? null
                            : (set) {
                                setState(() {
                                  _itemType = set.first;
                                });
                              },
                      ),
                      const SizedBox(height: 20),

                      // Section 1: Item Identity
                      _buildSectionTitle('Basic Information'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: '${_itemType.displayName} Name *',
                                hintText: _itemType == ItemType.product ? 'e.g. Wireless Mouse M185' : 'e.g. Consulting Service',
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Item name is required';
                                if (val.trim().length < 2) return 'Name must be at least 2 characters';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _skuController,
                              decoration: const InputDecoration(
                                labelText: 'SKU / Item Code',
                                hintText: 'e.g. IT-WM-001',
                              ),
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Category & Unit Row
                      Row(
                        children: [
                          // Category Selector
                          Expanded(
                            flex: 3,
                            child: categoriesAsync.when(
                              loading: () => const LinearProgressIndicator(),
                              error: (e, _) => Text('Error: $e'),
                              data: (cats) {
                                return DropdownButtonFormField<String?>(
                                  initialValue: _selectedCategoryId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Category',
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20, color: BillzoColors.primaryBlue),
                                      tooltip: 'Add Category',
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => CategoryManagerDialog(businessId: widget.businessId),
                                        );
                                      },
                                    ),
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('No Category')),
                                    ...cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedCategoryId = val;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Unit of Measurement Selector
                          Expanded(
                            flex: 2,
                            child: unitsAsync.when(
                              loading: () => const LinearProgressIndicator(),
                              error: (e, _) => Text('Error: $e'),
                              data: (units) {
                                // Default selection if none selected
                                if (_selectedUnitId == null && units.isNotEmpty) {
                                  _selectedUnitId = units.firstWhere((u) => u.isDefault, orElse: () => units.first).id;
                                }

                                return DropdownButtonFormField<String>(
                                  initialValue: _selectedUnitId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Unit *',
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20, color: BillzoColors.primaryBlue),
                                      tooltip: 'Manage Units',
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => UnitManagerDialog(businessId: widget.businessId),
                                        );
                                      },
                                    ),
                                  ),
                                  items: units.map((u) {
                                    return DropdownMenuItem(
                                      value: u.id,
                                      child: Text('${u.shortName} (${u.name})'),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedUnitId = val;
                                    });
                                  },
                                  validator: (val) {
                                    if (val == null || val.isEmpty) return 'Unit is required';
                                    return null;
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 2: Pricing & Taxation
                      _buildSectionTitle('Pricing & Taxation'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _sellingPriceController,
                              decoration: const InputDecoration(
                                labelText: 'Selling Price (₹) *',
                                prefixText: '₹ ',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Selling price is required';
                                final numVal = double.tryParse(val.trim());
                                if (numVal == null || numVal < 0) return 'Enter a valid amount';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _purchasePriceController,
                              decoration: const InputDecoration(
                                labelText: 'Purchase Price (₹)',
                                prefixText: '₹ ',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _mrpController,
                              decoration: const InputDecoration(
                                labelText: 'MRP (₹)',
                                prefixText: '₹ ',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  final mrp = double.tryParse(val.trim()) ?? 0;
                                  final selling = double.tryParse(_sellingPriceController.text.trim()) ?? 0;
                                  if (mrp < selling) {
                                    return 'MRP cannot be less than selling price';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // GST Tax & HSN Row
                      Row(
                        children: [
                          // Tax Rate Selector
                          Expanded(
                            flex: 3,
                            child: taxRatesAsync.when(
                              loading: () => const LinearProgressIndicator(),
                              error: (e, _) => Text('Error: $e'),
                              data: (rates) {
                                return DropdownButtonFormField<String?>(
                                  initialValue: _selectedTaxRateId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'GST Tax Rate'),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('No Tax / Exempt')),
                                    ...rates.map((r) => DropdownMenuItem(value: r.id, child: Text('${r.name} (${r.displayPercentage})'))),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedTaxRateId = val;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),

                          // HSN / SAC Code
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _hsnSacController,
                              decoration: InputDecoration(
                                labelText: _itemType == ItemType.product ? 'HSN Code' : 'SAC Code',
                                hintText: _itemType == ItemType.product ? 'e.g. 8471' : 'e.g. 998313',
                              ),
                              keyboardType: TextInputType.number,
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  final code = val.trim();
                                  if (_itemType == ItemType.product) {
                                    if (!RegExp(r'^[0-9]{2,8}$').hasMatch(code)) {
                                      return 'Goods HSN must be 2-8 digits';
                                    }
                                  } else {
                                    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
                                      return 'Services SAC must be 6 digits';
                                    }
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Tax inclusive checkbox
                      Row(
                        children: [
                          Checkbox(
                            value: _isTaxInclusive,
                            onChanged: (val) {
                              setState(() {
                                _isTaxInclusive = val ?? false;
                              });
                            },
                          ),
                          const Text('Selling price includes GST (Tax-inclusive pricing)', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 3: Stock Management (Goods Only)
                      if (_itemType == ItemType.product) ...[
                        _buildSectionTitle('Inventory & Opening Stock'),
                        const SizedBox(height: 12),
                        if (!isEditing) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _openingStockController,
                                  decoration: const InputDecoration(
                                    labelText: 'Opening Stock Quantity',
                                    helperText: 'Initial stock on hand',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  validator: (val) {
                                    if (val != null && val.trim().isNotEmpty) {
                                      final qty = double.tryParse(val.trim());
                                      if (qty == null || qty < 0) return 'Invalid stock quantity';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _lowStockThresholdController,
                                  decoration: const InputDecoration(
                                    labelText: 'Low Stock Alert Threshold',
                                    helperText: 'Alert when stock falls below this',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _openingStockNoteController,
                            decoration: const InputDecoration(
                              labelText: 'Opening Stock Audit Note',
                              hintText: 'e.g. Initial inventory count from physical register',
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: BillzoColors.canvasLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: BillzoColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, color: BillzoColors.primaryBlue, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  'Current Stock: ${widget.productToEdit!.currentStock} units',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                const Spacer(),
                                Text(
                                  'Opening: ${widget.productToEdit!.openingStock} units',
                                  style: const TextStyle(color: BillzoColors.neutralText, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],

                      // Description
                      _buildSectionTitle('Additional Details'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description / Item Notes',
                          hintText: 'Specifications, warranty terms, or notes',
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: BillzoColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    child: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(isEditing ? 'Save Changes' : 'Create Item'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillzoColors.darkSlate),
    );
  }
}
