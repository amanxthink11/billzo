import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/screens/cash_bank/cash_bank_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final testBiz = Business(
    id: 'biz-widget-cash-bank',
    name: 'Zenith Apex Corp',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final now = DateTime.now().toUtc();

  final testAccounts = [
    CashBankAccount(
      id: 'acc-cash-1',
      businessId: testBiz.id,
      name: 'Main Counter Cash',
      accountType: CashBankAccountType.cash,
      openingBalancePaise: 100000,
      currentBalancePaise: 750000, // ₹7,500.00
      isDefault: true,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    ),
    CashBankAccount(
      id: 'acc-bank-1',
      businessId: testBiz.id,
      name: 'ICICI Current Account',
      accountType: CashBankAccountType.bank,
      bankName: 'ICICI Bank',
      accountNumber: '001122334455',
      ifscCode: 'ICIC0000011',
      openingBalancePaise: 5000000,
      currentBalancePaise: 12500000, // ₹1,25,000.00
      isDefault: true,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  testWidgets('CashBankScreen renders title, overview KPIs, and account cards', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          cashBankAccountsProvider(testBiz.id).overrideWith((ref) => Future.value(testAccounts)),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: CashBankScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Action button
    expect(find.text('Cash & Bank Accounts'), findsOneWidget);
    expect(find.text('Add Account'), findsOneWidget);

    // Verify Overview KPI Cards
    expect(find.text('Total Liquidity'), findsOneWidget);
    expect(find.text('Cash on Hand'), findsOneWidget);
    expect(find.text('Bank Balances'), findsOneWidget);
    expect(find.text('Active Accounts'), findsOneWidget);

    // Verify Account Cards
    expect(find.text('Main Counter Cash'), findsOneWidget);
    expect(find.text('ICICI Current Account'), findsOneWidget);
    expect(find.text('ICICI Bank • • • • 4455'), findsOneWidget);
    expect(find.text('IFSC: ICIC0000011'), findsOneWidget);

    // Verify Add Account Dialog opens
    await tester.tap(find.text('Add Account'));
    await tester.pumpAndSettle();

    expect(find.text('Add Cash / Bank Account'), findsOneWidget);
    expect(find.text('Account Nickname *'), findsOneWidget);
    expect(find.text('Save Account'), findsOneWidget);
  });
}
