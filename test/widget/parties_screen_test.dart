import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/party_providers.dart';
import 'package:billzo/presentation/screens/parties/parties_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final testBiz = Business(
    id: 'biz-widget-party',
    name: 'Apex Traders',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final testParties = [
    Party(
      id: 'party-cust-1',
      businessId: testBiz.id,
      name: 'Ramesh Kirana Store',
      partyType: PartyType.customer,
      phone: '9811223344',
      billingStateCode: '27',
      billingStateName: 'Maharashtra',
      openingBalancePaise: 2500000,
      openingBalanceType: OpeningBalanceType.toReceive,
      currentBalancePaise: 2500000,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
    Party(
      id: 'party-supp-1',
      businessId: testBiz.id,
      name: 'Mahalaxmi Wholesalers',
      partyType: PartyType.supplier,
      phone: '9822334455',
      billingStateCode: '27',
      billingStateName: 'Maharashtra',
      openingBalancePaise: 4000000,
      openingBalanceType: OpeningBalanceType.toPay,
      currentBalancePaise: 4000000,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  ];

  testWidgets('PartiesScreen renders party table with customer and supplier records', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          partiesListProvider.overrideWith((ref) => Future.value(testParties)),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PartiesScreen(
              business: testBiz,
              initialTypeFilter: null,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Action elements
    expect(find.text('Search by name, phone, GSTIN...'), findsOneWidget);
    expect(find.text('New Supplier'), findsOneWidget);
    expect(find.text('New Customer'), findsOneWidget);

    // Verify Party data rendered in the table
    expect(find.text('Ramesh Kirana Store'), findsOneWidget);
    expect(find.text('+91 9811223344'), findsOneWidget);
    expect(find.text('Mahalaxmi Wholesalers'), findsOneWidget);
    expect(find.text('+91 9822334455'), findsOneWidget);

    // Tap New Customer button to open dialog
    await tester.tap(find.text('New Customer'));
    await tester.pumpAndSettle();

    // Verify dialog appears
    expect(find.text('Add New Customer'), findsOneWidget);
    expect(find.text('Party Name *'), findsOneWidget);
    expect(find.text('Mobile Phone'), findsOneWidget);
  });
}
