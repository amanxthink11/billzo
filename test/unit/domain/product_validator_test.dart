import 'package:flutter_test/flutter_test.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/catalog/product_validator.dart';

void main() {
  group('ProductValidator Domain Tests', () {
    final now = DateTime.now().toUtc();

    test('Valid Goods item passes validation', () {
      final product = Product(
        id: 'prod-1',
        businessId: 'biz-1',
        unitId: 'unit-pcs',
        name: 'Wireless Ergonomic Mouse',
        sku: 'MOU-WL-01',
        barcode: '8901234567890',
        hsnSacCode: '84716060',
        itemType: ItemType.product,
        purchasePricePaise: 80000,
        sellingPricePaise: 120000,
        mrpPaise: 149900,
        openingStock: 25.0,
        currentStock: 25.0,
        lowStockThreshold: 5.0,
        createdAt: now,
        updatedAt: now,
      );

      final result = ProductValidator.validate(product);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('Valid Service item passes validation', () {
      final service = Product(
        id: 'serv-1',
        businessId: 'biz-1',
        unitId: 'unit-hrs',
        name: 'IT Consultancy & Installation',
        sku: 'SRV-CONSULT',
        hsnSacCode: '998313', // 6-digit SAC
        itemType: ItemType.service,
        sellingPricePaise: 500000,
        openingStock: 0.0,
        createdAt: now,
        updatedAt: now,
      );

      final result = ProductValidator.validate(service);
      expect(result.isValid, isTrue);
    });

    test('Name is required and must be at least 2 characters', () {
      final empty = Product(
        id: '1',
        businessId: 'biz-1',
        unitId: 'unit-1',
        name: ' ',
        sellingPricePaise: 1000,
        createdAt: now,
        updatedAt: now,
      );
      expect(ProductValidator.validate(empty).errors['name'], contains('required'));

      final short = empty.copyWith(name: 'A');
      expect(ProductValidator.validate(short).errors['name'], contains('at least 2'));
    });

    test('Unit of measurement is strictly required', () {
      final noUnit = Product(
        id: '1',
        businessId: 'biz-1',
        unitId: '   ',
        name: 'Sample Item',
        sellingPricePaise: 1000,
        createdAt: now,
        updatedAt: now,
      );
      expect(ProductValidator.validate(noUnit).errors['unit_id'], contains('required'));
    });

    test('Rejects negative prices', () {
      final negativeSelling = Product(
        id: '1',
        businessId: 'biz-1',
        unitId: 'unit-1',
        name: 'Sample Item',
        sellingPricePaise: -500,
        purchasePricePaise: -200,
        createdAt: now,
        updatedAt: now,
      );
      final result = ProductValidator.validate(negativeSelling);
      expect(result.errors['selling_price'], contains('cannot be negative'));
      expect(result.errors['purchase_price'], contains('cannot be negative'));
    });

    test('Rejects MRP less than selling price', () {
      final invalidMrp = Product(
        id: '1',
        businessId: 'biz-1',
        unitId: 'unit-1',
        name: 'Sample Item',
        sellingPricePaise: 10000,
        mrpPaise: 8000, // MRP is less than selling price
        createdAt: now,
        updatedAt: now,
      );
      expect(ProductValidator.validate(invalidMrp).errors['mrp'], contains('cannot be less than selling price'));
    });

    test('Service cannot have opening stock > 0', () {
      final serviceWithStock = Product(
        id: '1',
        businessId: 'biz-1',
        unitId: 'unit-1',
        name: 'Consulting Service',
        itemType: ItemType.service,
        sellingPricePaise: 1000,
        openingStock: 10.0,
        createdAt: now,
        updatedAt: now,
      );
      expect(
        ProductValidator.validate(serviceWithStock).errors['opening_stock'],
        contains('Services cannot hold physical inventory'),
      );
    });

    test('Goods HSN must be 2 to 8 numeric digits', () {
      final invalidHsn1 = Product(
        id: '1',
        businessId: 'biz-1',
        unitId: 'unit-1',
        name: 'Goods Item',
        itemType: ItemType.product,
        sellingPricePaise: 1000,
        hsnSacCode: '1', // 1 digit - too short
        createdAt: now,
        updatedAt: now,
      );
      expect(ProductValidator.validate(invalidHsn1).errors['hsn_sac'], contains('2 to 8 digits'));

      final invalidHsnAlpha = invalidHsn1.copyWith(hsnSacCode: '8471ABCD');
      expect(ProductValidator.validate(invalidHsnAlpha).errors['hsn_sac'], contains('2 to 8 digits'));

      final validHsn4 = invalidHsn1.copyWith(hsnSacCode: '8471');
      expect(ProductValidator.validate(validHsn4).isValid, isTrue);

      final validHsn8 = invalidHsn1.copyWith(hsnSacCode: '84713010');
      expect(ProductValidator.validate(validHsn8).isValid, isTrue);
    });

    test('Service SAC must be exactly 6 digits', () {
      final invalidSac = Product(
        id: '1',
        businessId: 'biz-1',
        unitId: 'unit-1',
        name: 'Service Item',
        itemType: ItemType.service,
        sellingPricePaise: 1000,
        hsnSacCode: '9983', // 4 digits
        createdAt: now,
        updatedAt: now,
      );
      expect(ProductValidator.validate(invalidSac).errors['hsn_sac'], contains('6-digit code'));

      final validSac = invalidSac.copyWith(hsnSacCode: '998313');
      expect(ProductValidator.validate(validSac).isValid, isTrue);
    });
  });
}
