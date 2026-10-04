import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/catalog_providers.dart';
import 'package:billzo/presentation/screens/catalog/products_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final testBiz = Business(
    id: 'biz-widget-prod',
    name: 'Apex Supermarket',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final testProducts = [
    Product(
      id: 'prod-1',
      businessId: testBiz.id,
      name: 'Fortune Sunlite Sunflower Oil 1L',
      sku: 'OIL-SUN-01',
      itemType: ItemType.product,
      unitId: 'unit-ltr',
      hsnSacCode: '1512',
      sellingPricePaise: 16500,
      purchasePricePaise: 14000,
      mrpPaise: 18000,
      openingStock: 50.0,
      currentStock: 50.0,
      lowStockThreshold: 10,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
    Product(
      id: 'serv-1',
      businessId: testBiz.id,
      name: 'Home Delivery Service',
      sku: 'SRV-DEL-01',
      itemType: ItemType.service,
      unitId: 'unit-pcs',
      hsnSacCode: '9968',
      sellingPricePaise: 5000,
      purchasePricePaise: 0,
      openingStock: 0,
      currentStock: 0,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  ];

  testWidgets('ProductsScreen renders catalog table with goods and service items', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          productsListProvider.overrideWith((ref) => Future.value(testProducts)),
          categoriesListProvider.overrideWith((ref) => Future.value([])),
          unitsListProvider.overrideWith((ref) => Future.value([])),
          taxRatesListProvider.overrideWith((ref) => Future.value([])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: ProductsScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Action elements
    expect(find.text('Search by item name, SKU, HSN...'), findsOneWidget);
    expect(find.text('New Product'), findsOneWidget);
    expect(find.text('New Service'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Units'), findsOneWidget);

    // Verify Product & Service entries in DataTable
    expect(find.text('Fortune Sunlite Sunflower Oil 1L'), findsOneWidget);
    expect(find.text('SKU: OIL-SUN-01'), findsOneWidget);
    expect(find.text('Home Delivery Service'), findsOneWidget);
    expect(find.text('SKU: SRV-DEL-01'), findsOneWidget);

    // Tap New Product to verify dialog opening
    await tester.tap(find.text('New Product'));
    await tester.pumpAndSettle();

    // Verify dialog appears
    expect(find.text('Add New Goods'), findsOneWidget);
    expect(find.text('Goods Name *'), findsOneWidget);
    expect(find.text('Selling Price (₹) *'), findsOneWidget);
  });
}
