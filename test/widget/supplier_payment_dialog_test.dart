import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/application/purchase/purchase_service.dart';
import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_repository.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/screens/payments/supplier_payment_dialog.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

class FakePurchaseRepository implements IPurchaseRepository {
  final List<Purchase> purchases;
  FakePurchaseRepository(this.purchases);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<Purchase>> getPurchases({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async => purchases;
}

void main() {
  final now = DateTime.now().toUtc();
  final testBiz = Business(
    id: 'biz-supp-pay-w',
    name: 'Zenith Retails',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: now,
    updatedAt: now,
  );

  final testSupplier = Party(
    id: 'supp-w-1',
    businessId: testBiz.id,
    partyType: PartyType.supplier,
    name: 'Apex Fasteners Inc',
    phone: '9822334455',
    currentBalancePaise: 500000,
    createdAt: now,
    updatedAt: now,
  );

  final testAccount = CashBankAccount(
    id: 'acc-w-bank',
    businessId: testBiz.id,
    name: 'Primary Checking A/C',
    accountType: CashBankAccountType.bank,
    openingBalancePaise: 10000000,
    currentBalancePaise: 10000000,
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );

  final testPurchase = Purchase(
    id: 'pur-w-outstanding',
    businessId: testBiz.id,
    supplierId: testSupplier.id,
    supplierName: testSupplier.name,
    purchaseNumber: 'PUR-2026-0045',
    supplierInvoiceNumber: 'INV-APEX-45',
    supplierInvoiceDate: now,
    purchaseDate: now,
    dueDate: now.add(const Duration(days: 30)),
    placeOfSupplyStateCode: '27',
    status: PurchaseStatus.finalized,
    subtotalPaise: 500000,
    taxableAmountPaise: 500000,
    cgstPaise: 0,
    sgstPaise: 0,
    igstPaise: 0,
    roundOffPaise: 0,
    totalAmountPaise: 500000,
    paidAmountPaise: 0,
    balanceAmountPaise: 500000,
    itcEligibility: ItcEligibility.eligible,
    items: const [],
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('SupplierPaymentDialog renders title, supplier selector, amount input, and action buttons', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakePurchaseRepository([testPurchase]);
    final fakeService = PurchaseService(fakeRepo);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          partiesListProvider.overrideWith((ref) => Future.value([testSupplier])),
          cashBankAccountsProvider(testBiz.id).overrideWith((ref) => Future.value([testAccount])),
          purchaseServiceProvider.overrideWithValue(fakeService),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: SupplierPaymentDialog(
              business: testBiz,
              preselectedSupplier: testSupplier,
              preselectedPurchase: testPurchase,
              prefilledAmountPaise: 500000,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title
    expect(find.text('Record Supplier Payment'), findsOneWidget);
    expect(find.text('Disburse funds to supplier and reconcile outstanding purchase bills.'), findsOneWidget);

    // Verify Preselected Supplier
    expect(find.textContaining('Apex Fasteners Inc'), findsWidgets);

    // Verify Actions
    expect(find.text('Save Draft'), findsOneWidget);
    expect(find.text('Post Payment'), findsOneWidget);
  });
}
