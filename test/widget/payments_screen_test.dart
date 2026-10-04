import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/presentation/providers/business_provider.dart';
import 'package:billzo/presentation/providers/invoice_providers.dart';
import 'package:billzo/presentation/providers/payment_providers.dart';
import 'package:billzo/presentation/screens/payments/payments_screen.dart';

class MockActiveBusinessNotifier extends ActiveBusinessNotifier {
  final Business _biz;
  MockActiveBusinessNotifier(this._biz);

  @override
  Future<Business?> build() async => _biz;
}

void main() {
  final testBiz = Business(
    id: 'biz-widget-payments',
    name: 'Zenith Logistics Pvt Ltd',
    tradeName: 'Zenith Logistics',
    phone: '9876543210',
    stateCode: '27',
    stateName: 'Maharashtra',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  final now = DateTime.now().toUtc();

  final testPayments = [
    Payment(
      id: 'pay-w-1',
      businessId: testBiz.id,
      customerId: 'cust-1',
      customerName: 'Tata Motors Fleet',
      customerPhone: '9876543210',
      paymentNumber: 'PAY-2026-27-0001',
      paymentDate: now,
      paymentMethod: PaymentMethod.bankTransfer,
      amountPaise: 5000000, // ₹50,000.00
      accountId: 'acc-bank-1',
      accountName: 'HDFC Corporate Bank',
      referenceNumber: 'NEFT-889900',
      status: PaymentStatus.posted,
      allocations: [
        PaymentAllocation(
          id: 'alloc-w-1',
          paymentId: 'pay-w-1',
          documentId: 'inv-1',
          documentType: 'TAX_INVOICE',
          allocatedAmountPaise: 5000000,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    ),
    Payment(
      id: 'pay-w-2',
      businessId: testBiz.id,
      customerId: 'cust-2',
      customerName: 'Adani Logistics',
      customerPhone: '9888877777',
      paymentNumber: 'PAY-2026-27-0002',
      paymentDate: now,
      paymentMethod: PaymentMethod.cash,
      amountPaise: 1500000, // ₹15,000.00
      accountId: 'acc-cash-1',
      accountName: 'Main Cash Register',
      status: PaymentStatus.posted,
      allocations: [
        PaymentAllocation(
          id: 'alloc-w-2',
          paymentId: 'pay-w-2',
          documentId: 'inv-2',
          documentType: 'TAX_INVOICE',
          allocatedAmountPaise: 1500000,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    ),
    Payment(
      id: 'pay-w-3',
      businessId: testBiz.id,
      customerId: 'cust-3',
      customerName: 'Mahindra Logistics',
      customerPhone: '9777766666',
      paymentNumber: 'DRAFT',
      paymentDate: now,
      paymentMethod: PaymentMethod.upi,
      amountPaise: 250000, // ₹2,500.00
      status: PaymentStatus.draft,
      allocations: const [],
      createdAt: now,
      updatedAt: now,
    ),
  ];

  final testInvoices = [
    Invoice(
      id: 'inv-1',
      businessId: testBiz.id,
      invoiceNumber: 'INV-2026-0001',
      customerId: 'cust-1',
      customerName: 'Tata Motors Fleet',
      invoiceDate: now,
      dueDate: now.add(const Duration(days: 30)),
      placeOfSupplyStateCode: '27',
      status: InvoiceStatus.finalized,
      subtotalPaise: 10000000,
      taxableAmountPaise: 10000000,
      totalAmountPaise: 10000000,
      balanceAmountPaise: 5000000, // ₹50,000 outstanding
      createdAt: now,
      updatedAt: now,
    ),
  ];

  testWidgets('PaymentsScreen renders title, KPIs, search toolbar, and payments table', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(() => MockActiveBusinessNotifier(testBiz)),
          paymentsListProvider(testBiz.id).overrideWith((ref) => Future.value(testPayments)),
          paymentsCountProvider(testBiz.id).overrideWith((ref) => Future.value(testPayments.length)),
          invoicesListProvider.overrideWith((ref) => Future.value(testInvoices)),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PaymentsScreen(business: testBiz),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Action button
    expect(find.text('Payments & Receipts'), findsOneWidget);
    expect(find.text('Record Payment [F4]'), findsOneWidget);

    // Verify KPI summary metric cards
    expect(find.text('Total Received'), findsOneWidget);
    expect(find.text("Today's Receipts"), findsOneWidget);
    expect(find.text('Cash Received'), findsOneWidget);
    expect(find.text('Bank / UPI Received'), findsOneWidget);
    expect(find.text('Outstanding Receivables'), findsOneWidget);

    // Verify Search hint
    expect(find.text('Search by payment number, customer, phone, or reference...'), findsOneWidget);

    // Verify Table Records
    expect(find.text('PAY-2026-27-0001'), findsOneWidget);
    expect(find.text('Tata Motors Fleet'), findsOneWidget);
    expect(find.text('Adani Logistics'), findsOneWidget);
    expect(find.text('Mahindra Logistics'), findsOneWidget);

    // Verify Payment methods and accounts displayed
    expect(find.text('HDFC Corporate Bank'), findsOneWidget);
    expect(find.text('Main Cash Register'), findsOneWidget);
    expect(find.text('Bank Transfer'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);

    // Verify Status badges
    expect(find.text('Posted'), findsNWidgets(2));
    expect(find.text('Draft'), findsOneWidget);

    // Verify Receipt view action icons exist
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(3));
  });
}
