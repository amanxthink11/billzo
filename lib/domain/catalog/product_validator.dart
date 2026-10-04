import 'package:billzo/domain/catalog/product.dart';

/// Validation result containing error messages keyed by field name.
class ProductValidationResult {
  final Map<String, String> errors;

  const ProductValidationResult(this.errors);

  bool get isValid => errors.isEmpty;
  bool get hasErrors => errors.isNotEmpty;
  String? getError(String field) => errors[field];
}

/// Domain validator for products and services outside widgets.
class ProductValidator {
  ProductValidator._();

  static final RegExp _hsnRegex = RegExp(r'^[0-9]{2,8}$');
  static final RegExp _sacRegex = RegExp(r'^[0-9]{6}$');
  static final RegExp _skuRegex = RegExp(r'^[a-zA-Z0-9\-_./]{2,40}$');

  /// Validates a [Product] entity.
  static ProductValidationResult validate(Product product) {
    final Map<String, String> errors = {};

    // 1. Name
    final trimmedName = product.name.trim();
    if (trimmedName.isEmpty) {
      errors['name'] = 'Product or service name is required';
    } else if (trimmedName.length < 2) {
      errors['name'] = 'Name must be at least 2 characters';
    }

    // 2. Unit
    if (product.unitId.trim().isEmpty) {
      errors['unit_id'] = 'Unit of measurement is required';
    }

    // 3. Selling Price
    if (product.sellingPricePaise < 0) {
      errors['selling_price'] = 'Selling price cannot be negative';
    }

    // 4. Purchase Price
    if (product.purchasePricePaise < 0) {
      errors['purchase_price'] = 'Purchase price cannot be negative';
    }

    // 5. MRP
    if (product.mrpPaise != null && product.mrpPaise! < product.sellingPricePaise) {
      errors['mrp'] = 'MRP cannot be less than selling price';
    }

    // 6. Minimum Selling Price
    if (product.minimumSellingPricePaise != null &&
        product.minimumSellingPricePaise! > product.sellingPricePaise) {
      errors['minimum_selling_price'] = 'Minimum selling price cannot exceed regular selling price';
    }

    // 7. Stock Constraints
    if (product.isService) {
      if (product.openingStock != 0.0) {
        errors['opening_stock'] = 'Services cannot hold physical inventory';
      }
    } else {
      if (product.openingStock < 0.0) {
        errors['opening_stock'] = 'Opening stock cannot be negative';
      }
    }

    // 8. HSN / SAC Code
    if (product.hsnSacCode != null && product.hsnSacCode!.trim().isNotEmpty) {
      final code = product.hsnSacCode!.trim();
      if (product.isGoods) {
        if (!_hsnRegex.hasMatch(code)) {
          errors['hsn_sac'] = 'Goods HSN must be 2 to 8 digits (e.g. 8471, 84713010)';
        }
      } else {
        if (!_sacRegex.hasMatch(code)) {
          errors['hsn_sac'] = 'Services SAC must be a 6-digit code (e.g. 998313)';
        }
      }
    }

    // 9. SKU
    if (product.sku != null && product.sku!.trim().isNotEmpty) {
      final sku = product.sku!.trim();
      if (!_skuRegex.hasMatch(sku)) {
        errors['sku'] = 'SKU contains invalid characters (use alphanumeric, dash, dot, slash)';
      }
    }

    return ProductValidationResult(errors);
  }
}
