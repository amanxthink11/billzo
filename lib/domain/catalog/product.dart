import 'package:flutter/foundation.dart';
import 'package:billzo/core/money/money.dart';

/// Type of item: Goods (inventory tracked) or Service (non-inventory).
enum ItemType {
  product,
  service;

  String get dbValue => name;

  static ItemType fromDbValue(String value) {
    switch (value.toLowerCase()) {
      case 'product':
      case 'goods':
        return ItemType.product;
      case 'service':
        return ItemType.service;
      default:
        return ItemType.product;
    }
  }

  String get displayName {
    switch (this) {
      case ItemType.product:
        return 'Goods';
      case ItemType.service:
        return 'Service';
    }
  }
}

/// Catalog item representing a product (goods) or service.
@immutable
class Product {
  final String id;
  final String businessId;
  final String? categoryId;
  final String unitId;
  final String? taxRateId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? hsnSacCode;
  final String? description;
  final ItemType itemType;
  final int purchasePricePaise;
  final int sellingPricePaise;
  final int? mrpPaise;
  final int? minimumSellingPricePaise;
  final int? wholesalePricePaise;
  final bool isTaxInclusive;
  final double openingStock;
  final double currentStock;
  final double? lowStockThreshold;
  final String? imagePath;
  final bool isActive;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.businessId,
    this.categoryId,
    required this.unitId,
    this.taxRateId,
    required this.name,
    this.sku,
    this.barcode,
    this.hsnSacCode,
    this.description,
    this.itemType = ItemType.product,
    this.purchasePricePaise = 0,
    required this.sellingPricePaise,
    this.mrpPaise,
    this.minimumSellingPricePaise,
    this.wholesalePricePaise,
    this.isTaxInclusive = false,
    this.openingStock = 0.0,
    this.currentStock = 0.0,
    this.lowStockThreshold = 5.0,
    this.imagePath,
    this.isActive = true,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isService => itemType == ItemType.service;
  bool get isGoods => itemType == ItemType.product;
  bool get isLowStock => isGoods && lowStockThreshold != null && currentStock <= lowStockThreshold!;

  Money get purchasePrice => Money.fromPaise(purchasePricePaise);
  Money get sellingPrice => Money.fromPaise(sellingPricePaise);
  Money? get mrp => mrpPaise != null ? Money.fromPaise(mrpPaise!) : null;

  String? get hsnCode => hsnSacCode;
  String get unit => unitId;

  Product copyWith({
    String? id,
    String? businessId,
    String? categoryId,
    String? unitId,
    String? taxRateId,
    String? name,
    String? sku,
    String? barcode,
    String? hsnSacCode,
    String? description,
    ItemType? itemType,
    int? purchasePricePaise,
    int? sellingPricePaise,
    int? mrpPaise,
    int? minimumSellingPricePaise,
    int? wholesalePricePaise,
    bool? isTaxInclusive,
    double? openingStock,
    double? currentStock,
    double? lowStockThreshold,
    String? imagePath,
    bool? isActive,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      categoryId: categoryId ?? this.categoryId,
      unitId: unitId ?? this.unitId,
      taxRateId: taxRateId ?? this.taxRateId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      hsnSacCode: hsnSacCode ?? this.hsnSacCode,
      description: description ?? this.description,
      itemType: itemType ?? this.itemType,
      purchasePricePaise: purchasePricePaise ?? this.purchasePricePaise,
      sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      minimumSellingPricePaise: minimumSellingPricePaise ?? this.minimumSellingPricePaise,
      wholesalePricePaise: wholesalePricePaise ?? this.wholesalePricePaise,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      openingStock: openingStock ?? this.openingStock,
      currentStock: currentStock ?? this.currentStock,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      imagePath: imagePath ?? this.imagePath,
      isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'category_id': categoryId,
      'unit_id': unitId,
      'tax_rate_id': taxRateId,
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'hsn_sac': hsnSacCode,
      'description': description,
      'selling_price_paise': sellingPricePaise,
      'purchase_price_paise': purchasePricePaise,
      'mrp_paise': mrpPaise ?? 0,
      'is_tax_inclusive': isTaxInclusive ? 1 : 0,
      'track_inventory': isGoods ? 1 : 0,
      'current_stock': (currentStock * 1000).round(),
      'low_stock_threshold': (lowStockThreshold ?? 5.0).round(),
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': isDeleted ? updatedAt.toIso8601String() : null,
      'sync_version': 1,
      'sync_status': 'synced',
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final trackInventory = map['track_inventory'] as int? ?? 1;
    final itemType = (trackInventory == 0 || map['item_type'] == 'service')
        ? ItemType.service
        : ItemType.product;
    final rawCurrentStock = map['current_stock'] as num? ?? 0;
    // Current stock stored scaled by 1000 in database
    final currentStock = rawCurrentStock > 0 ? (rawCurrentStock / 1000.0) : 0.0;
    final rawOpeningStock = map['opening_stock'] as num?;
    final openingStock = rawOpeningStock != null ? (rawOpeningStock / 1000.0) : currentStock;

    return Product(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      categoryId: map['category_id'] as String?,
      unitId: map['unit_id'] as String,
      taxRateId: map['tax_rate_id'] as String?,
      name: map['name'] as String,
      sku: map['sku'] as String?,
      barcode: map['barcode'] as String?,
      hsnSacCode: (map['hsn_sac'] ?? map['hsn_sac_code']) as String?,
      description: map['description'] as String?,
      itemType: itemType,
      purchasePricePaise: map['purchase_price_paise'] as int? ?? 0,
      sellingPricePaise: map['selling_price_paise'] as int? ?? 0,
      mrpPaise: (map['mrp_paise'] as int? ?? 0) > 0 ? map['mrp_paise'] as int : null,
      minimumSellingPricePaise: map['minimum_selling_price_paise'] as int?,
      wholesalePricePaise: map['wholesale_price_paise'] as int?,
      isTaxInclusive: (map['is_tax_inclusive'] as int? ?? 0) == 1,
      openingStock: openingStock,
      currentStock: currentStock,
      lowStockThreshold: (map['low_stock_threshold'] as num?)?.toDouble(),
      imagePath: map['image_path'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      isDeleted: map['deleted_at'] != null || (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
