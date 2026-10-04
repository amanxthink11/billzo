import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/reports/csv_export_helper.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/catalog/tax_rate.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/reports/gstr1_report.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_report_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_tax_rate_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_unit_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class MockPathProvider implements IAppPathProvider {
  final Directory tempDir;
  MockPathProvider(this.tempDir);

  @override
  Future<String> getDatabaseDirectory() async => tempDir.path;
  @override
  Future<String> getBackupsDirectory() async => tempDir.path;
  @override
  Future<String> getMediaDirectory() async => tempDir.path;
  @override
  Future<String> getExportsDirectory() async => tempDir.path;
}

void main() {
  late Directory tempDir;
  late DatabaseHelper dbHelper;

  late SqliteBusinessRepository businessRepo;
  late SqlitePartyRepository partyRepo;
  late SqliteProductRepository productRepo;
  late SqliteTaxRateRepository taxRepo;
  late SqliteUnitRepository unitRepo;
  late SqliteReportRepository reportRepo;

  late Business business;
  late Party registeredCustomer;
  late Party unregisteredInterstateCustomer;
  late Party unregisteredLocalCustomer;
  late Product product1;
  late Product product2;
  late TaxRate tax18;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_gstr1_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);
    taxRepo = SqliteTaxRateRepository(dbHelper);
    unitRepo = SqliteUnitRepository(dbHelper);
    reportRepo = SqliteReportRepository(dbHelper);

    // Business in Maharashtra (27)
    business = await businessRepo.createBusiness(
      Business(
        id: 'biz-gst-test',
        name: 'Vanguard Systems',
        phone: '9876500000',
        stateCode: '27',
        stateName: 'Maharashtra',
        gstin: '27AABCV1234F1Z9',
        currencyCode: 'INR',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // 1. Registered Customer with GSTIN (B2B)
    registeredCustomer = await partyRepo.createParty(
      Party(
        id: 'cust-b2b',
        businessId: business.id,
        name: 'Apex Industrial Corp',
        phone: '9800000001',
        partyType: PartyType.customer,
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        gstin: '27AAACA1234P1Z2',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // 2. Unregistered Inter-state Customer (Karnataka - 29)
    unregisteredInterstateCustomer = await partyRepo.createParty(
      Party(
        id: 'cust-b2cl',
        businessId: business.id,
        name: 'Bangalore Consumer Club',
        phone: '9800000002',
        partyType: PartyType.customer,
        billingStateCode: '29', // Inter-state
        billingStateName: 'Karnataka',
        gstin: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // 3. Unregistered Local Customer (Maharashtra - 27)
    unregisteredLocalCustomer = await partyRepo.createParty(
      Party(
        id: 'cust-b2cs',
        businessId: business.id,
        name: 'Local Walkin Buyer',
        phone: '9800000003',
        partyType: PartyType.customer,
        billingStateCode: '27', // Intra-state
        billingStateName: 'Maharashtra',
        gstin: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Unit
    final units = await unitRepo.getUnits(business.id);
    final unit = units.firstWhere((u) => u.shortName == 'PCS', orElse: () => units.first);

    final taxes = await taxRepo.getTaxRates(business.id);
    tax18 = taxes.firstWhere((t) => t.rateBasisPoints == 1800, orElse: () => taxes.first);

    product1 = await productRepo.createProduct(
      Product(
        id: 'prod-hsn-1',
        businessId: business.id,
        name: 'Precision Gear 500',
        unitId: unit.id,
        taxRateId: tax18.id,
        itemType: ItemType.product,
        purchasePricePaise: 50000,
        sellingPricePaise: 100000, // 1,000 INR
        hsnSacCode: '8483',
        openingStock: 100.0,
        currentStock: 100.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    product2 = await productRepo.createProduct(
      Product(
        id: 'prod-hsn-2',
        businessId: business.id,
        name: 'Heavy Industrial Motor',
        unitId: unit.id,
        taxRateId: tax18.id,
        itemType: ItemType.product,
        purchasePricePaise: 15000000,
        sellingPricePaise: 30000000, // 3,00,000 INR (> 2.5 Lakhs)
        hsnSacCode: '8501',
        openingStock: 100.0,
        currentStock: 100.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GSTR-1 Portal Table Categorization Tests', () {
    test('Correctly classifies B2B (Table 4), B2CL (Table 5), B2CS (Table 7), and HSN (Table 12)', () async {
      final now = DateTime(2026, 3, 10);
      final db = await dbHelper.database;

      Future<void> insertInvoiceWithItem({
        required String id,
        required String number,
        required String customerId,
        required String pos,
        required DateTime invoiceDate,
        required int subtotalPaise,
        required int taxableAmountPaise,
        required int cgstPaise,
        required int sgstPaise,
        required int igstPaise,
        required int totalAmountPaise,
        required String productId,
        required String productName,
        required String hsnSac,
        required int quantityScaled,
        required String unitCode,
        required int ratePaise,
        required int cgstRateBasisPoints,
        required int sgstRateBasisPoints,
        required int igstRateBasisPoints,
      }) async {
        final dateStr = invoiceDate.toIso8601String();
        await db.insert('invoices', {
          'id': id,
          'business_id': business.id,
          'customer_id': customerId,
          'invoice_number': number,
          'invoice_date': dateStr,
          'due_date': invoiceDate.add(const Duration(days: 30)).toIso8601String(),
          'place_of_supply_state_code': pos,
          'invoice_type': 'TAX_INVOICE',
          'status': 'FINALIZED',
          'subtotal_paise': subtotalPaise,
          'discount_paise': 0,
          'taxable_amount_paise': taxableAmountPaise,
          'cgst_paise': cgstPaise,
          'sgst_paise': sgstPaise,
          'igst_paise': igstPaise,
          'cess_paise': 0,
          'round_off_paise': 0,
          'total_amount_paise': totalAmountPaise,
          'paid_amount_paise': 0,
          'balance_amount_paise': totalAmountPaise,
          'created_at': dateStr,
          'updated_at': dateStr,
        });

        await db.insert('invoice_items', {
          'id': 'item-$id',
          'invoice_id': id,
          'product_id': productId,
          'tax_rate_id': tax18.id,
          'product_name': productName,
          'hsn_sac': hsnSac,
          'quantity': quantityScaled,
          'unit_code': unitCode,
          'rate_paise': ratePaise,
          'mrp_paise': 0,
          'discount_paise': 0,
          'taxable_amount_paise': taxableAmountPaise,
          'cgst_rate_basis_points': cgstRateBasisPoints,
          'cgst_amount_paise': cgstPaise,
          'sgst_rate_basis_points': sgstRateBasisPoints,
          'sgst_amount_paise': sgstPaise,
          'igst_rate_basis_points': igstRateBasisPoints,
          'igst_amount_paise': igstPaise,
          'cess_rate_basis_points': 0,
          'cess_amount_paise': 0,
          'total_amount_paise': totalAmountPaise,
          'created_at': dateStr,
          'updated_at': dateStr,
        });
      }

      // Invoice 1: B2B (Customer has GSTIN)
      await insertInvoiceWithItem(
        id: 'inv-1-b2b',
        number: 'INV-B2B-001',
        customerId: registeredCustomer.id,
        pos: '27',
        invoiceDate: now,
        subtotalPaise: 100000,
        taxableAmountPaise: 100000,
        cgstPaise: 9000,
        sgstPaise: 9000,
        igstPaise: 0,
        totalAmountPaise: 118000,
        productId: product1.id,
        productName: product1.name,
        hsnSac: '8483',
        quantityScaled: 1000,
        unitCode: 'PCS',
        ratePaise: 100000,
        cgstRateBasisPoints: 900,
        sgstRateBasisPoints: 900,
        igstRateBasisPoints: 0,
      );

      // Invoice 2: B2CL (Inter-state unregistered > 2.5 Lakhs: 3 Lakhs)
      await insertInvoiceWithItem(
        id: 'inv-2-b2cl',
        number: 'INV-B2CL-001',
        customerId: unregisteredInterstateCustomer.id,
        pos: '29', // Karnataka
        invoiceDate: now,
        subtotalPaise: 30000000, // 3 Lakhs
        taxableAmountPaise: 30000000,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 5400000, // 18% IGST
        totalAmountPaise: 35400000,
        productId: product2.id,
        productName: product2.name,
        hsnSac: '8501',
        quantityScaled: 1000,
        unitCode: 'PCS',
        ratePaise: 30000000,
        cgstRateBasisPoints: 0,
        sgstRateBasisPoints: 0,
        igstRateBasisPoints: 1800,
      );

      // Invoice 3: B2CS (Local unregistered, any amount)
      await insertInvoiceWithItem(
        id: 'inv-3-b2cs',
        number: 'INV-B2CS-001',
        customerId: unregisteredLocalCustomer.id,
        pos: '27',
        invoiceDate: now,
        subtotalPaise: 50000,
        taxableAmountPaise: 50000,
        cgstPaise: 4500,
        sgstPaise: 4500,
        igstPaise: 0,
        totalAmountPaise: 59000,
        productId: product1.id,
        productName: product1.name,
        hsnSac: '8483',
        quantityScaled: 1000,
        unitCode: 'PCS',
        ratePaise: 50000,
        cgstRateBasisPoints: 900,
        sgstRateBasisPoints: 900,
        igstRateBasisPoints: 0,
      );

      // Query GSTR-1 Report for March 2026
      final gstr1 = await reportRepo.getGstr1Report(
        business.id,
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 31),
      );

      // Verify Table 4 B2B
      expect(gstr1.b2bInvoices.length, equals(1));
      expect(gstr1.b2bInvoices.first.receiverGstin, equals('27AAACA1234P1Z2'));
      expect(gstr1.b2bInvoices.first.invoiceNumber, equals('INV-B2B-001'));
      expect(gstr1.b2bInvoices.first.taxableValuePaise, equals(100000));
      expect(gstr1.b2bInvoices.first.cgstPaise, equals(9000));
      expect(gstr1.b2bInvoices.first.sgstPaise, equals(9000));

      // Verify Table 5 B2CL
      expect(gstr1.b2clInvoices.length, equals(1));
      expect(gstr1.b2clInvoices.first.invoiceNumber, equals('INV-B2CL-001'));
      expect(gstr1.b2clInvoices.first.placeOfSupply, equals('29'));
      expect(gstr1.b2clInvoices.first.taxableValuePaise, equals(30000000));
      expect(gstr1.b2clInvoices.first.igstPaise, equals(5400000));

      // Verify Table 7 B2CS
      expect(gstr1.b2csItems.length, equals(1));
      expect(gstr1.b2csItems.first.placeOfSupply, equals('27'));
      expect(gstr1.b2csItems.first.taxableValuePaise, equals(50000));
      expect(gstr1.b2csItems.first.cgstPaise, equals(4500));
      expect(gstr1.b2csItems.first.sgstPaise, equals(4500));

      // Verify Table 12 HSN Summary
      expect(gstr1.hsnSummary.length, equals(2));
      final gearHsn = gstr1.hsnSummary.firstWhere((h) => h.hsnSac == '8483');
      expect(gearHsn.description, equals('Precision Gear 500'));
      expect(gearHsn.totalQuantity, equals(2)); // from inv1 + inv3 (1 + 1)
      expect(gearHsn.taxableValuePaise, equals(150000));
      expect(gearHsn.cgstPaise, equals(13500));
      expect(gearHsn.sgstPaise, equals(13500));

      final motorHsn = gstr1.hsnSummary.firstWhere((h) => h.hsnSac == '8501');
      expect(motorHsn.totalQuantity, equals(1));
      expect(motorHsn.taxableValuePaise, equals(30000000));
      expect(motorHsn.igstPaise, equals(5400000));
    });

    test('RFC 4180 CSV export generates compliant CSV text', () {
      final csv = CsvExportHelper.exportGstr1B2b([
        Gstr1B2bInvoice(
          receiverGstin: '27AAACA1234P1Z2',
          receiverName: 'Apex Industrial, Corp', // contains comma!
          invoiceNumber: 'INV/001',
          invoiceDate: DateTime(2026, 3, 10),
          invoiceValuePaise: 118000,
          placeOfSupply: '27',
          reverseCharge: 'N',
          invoiceType: 'Regular',
          rateBasisPoints: 1800,
          taxableValuePaise: 100000,
          cgstPaise: 9000,
          sgstPaise: 9000,
          igstPaise: 0,
          cessPaise: 0,
        ),
      ]);

      // RFC 4180 requires wrapping fields with commas in quotes
      expect(csv.contains('"Apex Industrial, Corp"'), isTrue);
      expect(csv.contains('27AAACA1234P1Z2'), isTrue);
      expect(csv.contains('1000.00'), isTrue); // 100000 paise formatted as 1000.00 INR
    });
  });
}
