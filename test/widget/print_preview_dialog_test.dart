import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/core/theme/app_theme.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';
import 'package:billzo/presentation/providers/database_providers.dart';
import 'package:billzo/presentation/screens/sales/print_preview_dialog.dart';

void main() {
  late Business testBusiness;
  late Party testCustomer;
  late BusinessSettings testSettings;
  late Invoice testInvoice;

  setUp(() {
    testBusiness = Business(
      id: 'biz-preview-1',
      name: 'Vanguard Electronics Ltd',
      tradeName: 'Vanguard Digital',
      gstin: '27AABCV1234F1Z1',
      stateCode: '27',
      stateName: 'Maharashtra',
      addressLine1: 'Unit 401, Cyber City',
      city: 'Pune',
      pincode: '411028',
      phone: '9888877777',
      email: 'billing@vanguard.io',
      upiId: 'vanguard@icici',
      bankName: 'ICICI Bank',
      bankAccountNumber: '000105001234',
      bankIfsc: 'ICIC0000001',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    testCustomer = Party(
      id: 'cust-preview-1',
      businessId: 'biz-preview-1',
      partyType: PartyType.customer,
      name: 'Aditya Birla Retail',
      phone: '9777766666',
      gstin: '27AAACB1234P1Z3',
      billingAddressLine1: 'Birla Centurion, Worli',
      billingCity: 'Mumbai',
      billingPincode: '400030',
      billingStateCode: '27',
      billingStateName: 'Maharashtra',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    testSettings = BusinessSettings(
      id: 'set-preview-1',
      businessId: 'biz-preview-1',
      printBusinessLogo: true,
      printBankDetails: true,
      printUpiQr: true,
      thermalPrinterType: '80mm',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final item1 = InvoiceItem(
      id: 'item-preview-1',
      invoiceId: 'inv-preview-1',
      productId: 'prod-p1',
      taxRateId: 'tax-18',
      productName: 'Cat6 Ethernet Cable 305m',
      hsnSac: '854449',
      quantityScaled: 2000, // 2 PCS
      unitCode: 'PCS',
      ratePaise: 450000,
      discountPaise: 50000,
      taxableAmountPaise: 850000,
      cgstRateBasisPoints: 900,
      cgstAmountPaise: 76500,
      sgstRateBasisPoints: 900,
      sgstAmountPaise: 76500,
      igstRateBasisPoints: 0,
      igstAmountPaise: 0,
      cessRateBasisPoints: 0,
      cessAmountPaise: 0,
      totalAmountPaise: 1003000,
      createdAt: DateTime.utc(2026, 3, 20),
      updatedAt: DateTime.utc(2026, 3, 20),
    );

    testInvoice = Invoice(
      id: 'inv-preview-1',
      businessId: 'biz-preview-1',
      customerId: 'cust-preview-1',
      customerName: 'Aditya Birla Retail',
      customerPhone: '9777766666',
      customerGstin: '27AAACB1234P1Z3',
      invoiceNumber: 'INV-2026-0888',
      invoiceDate: DateTime.utc(2026, 3, 20),
      dueDate: DateTime.utc(2026, 4, 4),
      placeOfSupplyStateCode: '27',
      invoiceType: InvoiceType.taxInvoice,
      status: InvoiceStatus.finalized,
      subtotalPaise: 900000,
      discountPaise: 50000,
      taxableAmountPaise: 850000,
      cgstPaise: 76500,
      sgstPaise: 76500,
      igstPaise: 0,
      cessPaise: 0,
      roundOffPaise: 0,
      totalAmountPaise: 1003000,
      paidAmountPaise: 0,
      balanceAmountPaise: 1003000,
      items: [item1],
      createdAt: DateTime.utc(2026, 3, 20),
      updatedAt: DateTime.utc(2026, 3, 20),
    );
  });

  testWidgets('PrintPreviewDialog renders invoice meta, toolbar controls, and action buttons', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          printerServiceProvider.overrideWithValue(const PrintingService()),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PrintPreviewDialog(
              business: testBusiness,
              invoice: testInvoice,
              customer: testCustomer,
              settings: testSettings,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // 1. Verify Header details
    expect(find.text('Print Preview: INV-2026-0888'), findsOneWidget);
    expect(find.text('Finalized'), findsOneWidget);
    expect(find.textContaining('Aditya Birla Retail'), findsWidgets);
    expect(find.textContaining('10,030.00'), findsWidgets);

    // 2. Verify Format selection chips
    expect(find.text('Standard A4'), findsOneWidget);
    expect(find.text('80mm POS'), findsOneWidget);
    expect(find.text('58mm POS'), findsOneWidget);
    expect(find.text('Text Receipt'), findsOneWidget);

    // 3. Verify Toggle Chips
    expect(find.text('Logo'), findsOneWidget);
    expect(find.text('Bank Info'), findsOneWidget);
    expect(find.text('UPI QR'), findsOneWidget);

    // 4. Verify Action Bar buttons
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Save PDF'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Print (Ctrl+P)'), findsOneWidget);
  });

  testWidgets('PrintPreviewDialog switches to Plain Text receipt roll view', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          printerServiceProvider.overrideWithValue(const PrintingService()),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PrintPreviewDialog(
              business: testBusiness,
              invoice: testInvoice,
              customer: testCustomer,
              settings: testSettings,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // Tap on Text Receipt format
    await tester.tap(find.text('Text Receipt'));
    await tester.pumpAndSettle();

    // Should now show the POS Receipt Roll
    expect(find.text('POS RECEIPT ROLL'), findsOneWidget);
    expect(find.text('Copy Text'), findsOneWidget);

    // Should contain rendered plain text content
    expect(find.textContaining('Vanguard Digital'), findsWidgets);
    expect(find.textContaining('INV-2026-0888'), findsWidgets);
    expect(find.textContaining('Cat6 Ethernet Cable'), findsWidgets);
    expect(find.textContaining('TOTAL (INR):'), findsWidgets);
    expect(find.textContaining('Scan to Pay via UPI'), findsWidgets);
  });

  testWidgets('PrintPreviewDialog format chips switch properly between formats', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          printerServiceProvider.overrideWithValue(const PrintingService()),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PrintPreviewDialog(
              business: testBusiness,
              invoice: testInvoice,
              customer: testCustomer,
              settings: testSettings,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // Select 80mm POS -> Open Drawer toggle should appear
    await tester.tap(find.text('80mm POS'));
    await tester.pump();
    expect(find.text('Open Drawer'), findsOneWidget);

    // Select 58mm POS
    await tester.tap(find.text('58mm POS'));
    await tester.pump();
    expect(find.text('Open Drawer'), findsOneWidget);

    // Select Standard A4 -> Open Drawer toggle should disappear
    await tester.tap(find.text('Standard A4'));
    await tester.pump();
    expect(find.text('Open Drawer'), findsNothing);
  });

  testWidgets('PrintPreviewDialog toggle chips toggle state on click', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          printerServiceProvider.overrideWithValue(const PrintingService()),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: PrintPreviewDialog(
              business: testBusiness,
              invoice: testInvoice,
              customer: testCustomer,
              settings: testSettings,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // Toggle Logo chip
    final logoChipFinder = find.widgetWithText(FilterChip, 'Logo');
    expect(logoChipFinder, findsOneWidget);
    FilterChip logoChip = tester.widget(logoChipFinder);
    expect(logoChip.selected, isTrue);

    await tester.tap(logoChipFinder);
    await tester.pump();
    logoChip = tester.widget(logoChipFinder);
    expect(logoChip.selected, isFalse);

    // Toggle Bank Info chip
    final bankChipFinder = find.widgetWithText(FilterChip, 'Bank Info');
    expect(bankChipFinder, findsOneWidget);
    FilterChip bankChip = tester.widget(bankChipFinder);
    expect(bankChip.selected, isTrue);

    await tester.tap(bankChipFinder);
    await tester.pump();
    bankChip = tester.widget(bankChipFinder);
    expect(bankChip.selected, isFalse);
  });

  testWidgets('PrintPreviewDialog Close button dismisses dialog when opened via show', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          printerServiceProvider.overrideWithValue(const PrintingService()),
        ],
        child: MaterialApp(
          theme: BillzoTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  PrintPreviewDialog.show(
                    ctx,
                    business: testBusiness,
                    invoice: testInvoice,
                    customer: testCustomer,
                    settings: testSettings,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open the modal
    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Print Preview: INV-2026-0888'), findsOneWidget);

    // Click Close button in action bar
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Print Preview: INV-2026-0888'), findsNothing);
  });
}

