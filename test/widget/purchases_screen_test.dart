import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/providers/purchase_providers.dart';
import 'package:billzo/presentation/screens/purchases/purchases_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final now = DateTime.now().toUtc();
  final testBiz = Business(
    id: 'biz-widget-purchases',
    name: 'Zenith Manufacturing',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: now,
    updatedAt: now,
  );

  final testPurchases = [
    Purchase(
      id: 'pur-w-1',
      businessId: testBiz.id,
      supplierId: 'supp-w-1',
      supplierName: 'Tata Steel Ltd',
      purchaseNumber: 'PUR-2026-0001',
      supplierInvoiceNumber: 'TSL-INV-9021',
      supplierInvoiceDate: now,
      purchaseDate: now,
      dueDate: now.add(const Duration(days: 30)),
      placeOfSupplyStateCode: '27',
      status: PurchaseStatus.finalized,
      subtotalPaise: 1000000,
      taxableAmountPaise: 1000000,
      cgstPaise: 90000,
      sgstPaise: 90000,
      igstPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: 1180000,
      paidAmountPaise: 0,
      balanceAmountPaise: 1180000,
      itcEligibility: ItcEligibility.eligible,
      inputCgstPaise: 90000,
      inputSgstPaise: 90000,
      inputIgstPaise: 0,
      items: [
        PurchaseItem(
          id: 'item-w-1',
          purchaseId: 'pur-w-1',
          productId: 'prod-w-steel',
          productName: 'Steel Rods 12mm',
          unitCode: 'KG',
          quantityScaled: 100000, // 100 kg
          purchaseRatePaise: 10000,
          taxableAmountPaise: 1000000,
          taxRateId: 'tax-18',
          rateBasisPoints: 1800,
          cgstRateBasisPoints: 900,
          cgstAmountPaise: 90000,
          sgstRateBasisPoints: 900,
          sgstAmountPaise: 90000,
          totalAmountPaise: 1180000,
          isItcEligible: true,
          trackInventory: true,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    ),
    Purchase(
      id: 'pur-w-2',
      businessId: testBiz.id,
      supplierId: 'supp-w-2',
      supplierName: 'Jindal Power Supplies',
      purchaseNumber: 'DRAFT-PUR-002',
      supplierInvoiceNumber: 'JPS-884',
      supplierInvoiceDate: now,
      purchaseDate: now,
      dueDate: now.add(const Duration(days: 15)),
      placeOfSupplyStateCode: '27',
      status: PurchaseStatus.draft,
      subtotalPaise: 500000,
      taxableAmountPaise: 500000,
      cgstPaise: 25000,
      sgstPaise: 25000,
      igstPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: 550000,
      paidAmountPaise: 0,
      balanceAmountPaise: 550000,
      itcEligibility: ItcEligibility.eligible,
      items: const [],
      createdAt: now,
      updatedAt: now,
    ),
  ];

  testWidgets('PurchasesScreen renders title, KPIs, search toolbar, and purchase bills table', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          purchasesListProvider.overrideWith((ref) => Future.value(testPurchases)),
          purchasesCountProvider.overrideWith((ref) => Future.value(testPurchases.length)),
          partiesListProvider.overrideWith((ref) => Future.value([])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PurchasesScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Action button
    expect(find.text('Purchases & Accounts Payable'), findsOneWidget);
    expect(find.text('New Purchase Bill'), findsOneWidget);

    // Verify KPI summary metric chips
    expect(find.text('Total Purchases'), findsOneWidget);
    expect(find.text("Today's Purchases"), findsOneWidget);
    expect(find.text('Outstanding Payable'), findsOneWidget);
    expect(find.text('Input Tax Credit (ITC)'), findsOneWidget);

    // Verify Search hint
    expect(find.text('Search purchase #, supplier, or invoice #...'), findsOneWidget);

    // Verify table records
    expect(find.text('PUR-2026-0001'), findsOneWidget);
    expect(find.text('Tata Steel Ltd'), findsOneWidget);
    expect(find.text('TSL-INV-9021'), findsOneWidget);
    expect(find.text('Jindal Power Supplies'), findsOneWidget);
    expect(find.text('Finalized'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });
}
