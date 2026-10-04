import 'package:billzo/core/money/money.dart';

/// Single product item valuation row in the stock report.
class StockValuationItem {
  final String productId;
  final String productName;
  final String? sku;
  final String? categoryName;
  final String unitCode;
  final int currentStock;
  final int currentStockScaled;
  final int purchasePricePaise;
  final int sellingPricePaise;
  final int lowStockThreshold;

  const StockValuationItem({
    required this.productId,
    required this.productName,
    this.sku,
    this.categoryName,
    required this.unitCode,
    required this.currentStock,
    int? currentStockScaled,
    required this.purchasePricePaise,
    required this.sellingPricePaise,
    this.lowStockThreshold = 5,
  }) : currentStockScaled = currentStockScaled ?? (currentStock * 1000);

  Money get purchasePrice => Money.fromPaise(purchasePricePaise);
  Money get sellingPrice => Money.fromPaise(sellingPricePaise);

  int get costValuationPaise =>
      currentStockScaled > 0 ? (currentStockScaled * purchasePricePaise + 500) ~/ 1000 : 0;
  int get retailValuationPaise =>
      currentStockScaled > 0 ? (currentStockScaled * sellingPricePaise + 500) ~/ 1000 : 0;

  Money get costValuation => Money.fromPaise(costValuationPaise);
  Money get retailValuation => Money.fromPaise(retailValuationPaise);

  bool get isLowStock => currentStock <= lowStockThreshold;
  bool get isOutOfStock => currentStock <= 0;
}

/// Comprehensive inventory valuation and stock status report.
class StockValuationReport {
  final String businessId;
  final DateTime asOfDate;
  final List<StockValuationItem> items;
  final DateTime generatedAt;

  const StockValuationReport({
    required this.businessId,
    required this.asOfDate,
    required this.items,
    required this.generatedAt,
  });

  int get totalCostValuationPaise =>
      items.fold<int>(0, (sum, i) => sum + i.costValuationPaise);
  int get totalRetailValuationPaise =>
      items.fold<int>(0, (sum, i) => sum + i.retailValuationPaise);
  int get totalStockQuantity =>
      items.fold<int>(0, (sum, i) => sum + (i.currentStock > 0 ? i.currentStock : 0));
  int get lowStockItemsCount =>
      items.where((i) => i.isLowStock).length;
  int get totalItemsCount => items.length;

  Money get totalCostValuation => Money.fromPaise(totalCostValuationPaise);
  Money get totalRetailValuation => Money.fromPaise(totalRetailValuationPaise);
}
