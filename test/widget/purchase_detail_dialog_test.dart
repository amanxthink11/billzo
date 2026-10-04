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
import 'package:billzo/presentation/providers/purchase_providers.dart';
import 'package:billzo/presentation/screens/purchases/purchase_detail_dialog.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final now = DateTime.now().toUtc();
  final testBiz = Business(
    id: 'biz-detail-w',
    name: 'Zenith Retails',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: now,
    updatedAt: now,
  );

  final testPurchase = Purchase(
    id: 'pur-detail-1',
    businessId: testBiz.id,
    supplierId: 'supp-1',
    supplierName: 'Tata Steel Ltd',
    purchaseNumber: 'PUR-2026-0099',
    supplierInvoiceNumber: 'TSL-INV-999',
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
    items: [
      PurchaseItem(
        id: 'item-detail-1',
        purchaseId: 'pur-detail-1',
        productId: 'prod-steel-1',
        productName: 'TMT Steel 16mm',
        unitCode: 'KG',
        quantityScaled: 100000,
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
  );

  testWidgets('PurchaseDetailDialog renders purchase number, supplier invoice, line items, and financial summary', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          purchaseDetailProvider('pur-detail-1').overrideWith((ref) => Future.value(testPurchase)),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PurchaseDetailDialog(
              business: testBiz,
              purchaseId: 'pur-detail-1',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Header
    expect(find.text('PUR-2026-0099'), findsOneWidget);
    expect(find.text('Finalized'), findsOneWidget);
    expect(find.textContaining('Tata Steel Ltd'), findsWidgets);
    expect(find.textContaining('TSL-INV-999'), findsWidgets);

    // Verify Item
    expect(find.text('TMT Steel 16mm'), findsOneWidget);

    // Verify Financials
    expect(find.text('₹11,800.00'), findsWidgets);
  });
}
