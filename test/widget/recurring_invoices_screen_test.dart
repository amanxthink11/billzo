import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/recurring_providers.dart';
import 'package:billzo/presentation/screens/recurring/recurring_invoices_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final testBiz = Business(
    id: 'biz-widget-rec',
    name: 'Zenith Retails',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    currencyCode: 'INR',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final testProfiles = [
    RecurringInvoice(
      id: 'rec-w-1',
      businessId: testBiz.id,
      customerId: 'cust-1',
      customerName: 'Tata Consultancy Services',
      profileName: 'Monthly AMC Support',
      frequency: RecurringFrequency.monthly,
      startDate: DateTime(2026, 1, 1),
      nextRunDate: DateTime(2026, 4, 1),
      status: RecurringInvoiceStatus.active,
      items: [
        RecurringInvoiceItem(
          id: 'item-w-1',
          recurringInvoiceId: 'rec-w-1',
          productId: 'p-1',
          taxRateId: 't-1',
          productName: 'Server Monitoring',
          quantity: 1,
          unitCode: 'NOS',
          ratePaise: 2500000,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
    RecurringInvoice(
      id: 'rec-w-2',
      businessId: testBiz.id,
      customerId: 'cust-2',
      customerName: 'Infosys Technologies',
      profileName: 'Quarterly Software License',
      frequency: RecurringFrequency.quarterly,
      startDate: DateTime(2026, 1, 1),
      nextRunDate: DateTime(2026, 4, 1),
      status: RecurringInvoiceStatus.paused,
      items: [
        RecurringInvoiceItem(
          id: 'item-w-2',
          recurringInvoiceId: 'rec-w-2',
          productId: 'p-2',
          taxRateId: 't-1',
          productName: 'ERP User License',
          quantity: 5,
          unitCode: 'NOS',
          ratePaise: 1000000,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];

  testWidgets('RecurringInvoicesScreen renders title, KPIs, filter chips, and profile items', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          recurringInvoicesProvider(testBiz.id).overrideWith((ref) => Future.value(testProfiles)),
          missedSchedulesProvider(testBiz.id).overrideWith((ref) => Future.value([])),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: RecurringInvoicesScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Action
    expect(find.text('Recurring Invoices'), findsOneWidget);
    expect(find.text('New Profile'), findsOneWidget);

    // Verify KPI summary cards
    expect(find.text('Active Profiles'), findsOneWidget);
    expect(find.text('Paused Profiles'), findsOneWidget);
    expect(find.text('Monthly Recurring (MRR)'), findsOneWidget);

    // Verify Filter chips
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Active'), findsWidgets);
    expect(find.text('Paused'), findsWidgets);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);

    // Verify Profiles rendered in list
    expect(find.text('Monthly AMC Support'), findsOneWidget);
    expect(find.text('Tata Consultancy Services'), findsOneWidget);
    expect(find.text('Quarterly Software License'), findsOneWidget);
    expect(find.text('Infosys Technologies'), findsOneWidget);
  });
}
