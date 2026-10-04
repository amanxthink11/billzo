import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/invoice_providers.dart';
import 'package:billzo/presentation/screens/sales/sales_invoices_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final testBiz = Business(
    id: 'biz-widget-sales',
    name: 'Zenith Retails',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final testInvoices = [
    Invoice(
      id: 'inv-w-1',
      businessId: testBiz.id,
      invoiceNumber: 'INV-2026-0001',
      customerId: 'cust-1',
      customerName: 'Reliance Industries',
      customerPhone: '9876543210',
      invoiceDate: DateTime(2026, 10, 1),
      dueDate: DateTime(2026, 10, 15),
      placeOfSupplyStateCode: '27',
      status: InvoiceStatus.finalized,
      subtotalPaise: 1000000,
      taxableAmountPaise: 1000000,
      cgstPaise: 90000,
      sgstPaise: 90000,
      igstPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: 1180000,
      balanceAmountPaise: 1180000,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
    Invoice(
      id: 'inv-w-2',
      businessId: testBiz.id,
      invoiceNumber: 'DRAFT',
      customerId: 'cust-2',
      customerName: 'Tata Consultancy',
      customerPhone: '9876500000',
      invoiceDate: DateTime(2026, 10, 1),
      dueDate: DateTime(2026, 10, 15),
      placeOfSupplyStateCode: '27',
      status: InvoiceStatus.draft,
      subtotalPaise: 500000,
      taxableAmountPaise: 500000,
      cgstPaise: 25000,
      sgstPaise: 25000,
      igstPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: 550000,
      balanceAmountPaise: 550000,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  ];

  testWidgets('SalesInvoicesScreen renders title, KPIs, search toolbar, and invoice table', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          invoicesListProvider.overrideWith((ref) => Future.value(testInvoices)),
          invoicesCountProvider.overrideWith((ref) => Future.value(testInvoices.length)),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: SalesInvoicesScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Action
    expect(find.text('Sales Invoices'), findsOneWidget);
    expect(find.text('New Invoice [F2]'), findsOneWidget);

    // Verify KPI summary metric chips
    expect(find.text('Total Sales'), findsOneWidget);
    expect(find.text('Outstanding Receivables'), findsOneWidget);
    expect(find.text('Finalized Invoices'), findsOneWidget);
    expect(find.text('Open Drafts'), findsOneWidget);

    // Verify Search hint
    expect(find.text('Search by invoice number, customer, phone, or GSTIN...'), findsOneWidget);

    // Verify table records
    expect(find.text('INV-2026-0001'), findsOneWidget);
    expect(find.text('Reliance Industries'), findsOneWidget);
    expect(find.text('Tata Consultancy'), findsOneWidget);
    expect(find.text('FINALIZED'), findsOneWidget);
    expect(find.text('DRAFT'), findsNWidgets(2)); // Invoice number & Status badge
  });
}
