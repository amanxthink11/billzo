import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/reports/csv_export_helper.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_report_repository.dart';
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
  late SqliteReportRepository reportRepo;

  late Business business;
  late Party customer;
  late Party supplier;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_aging_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    reportRepo = SqliteReportRepository(dbHelper);

    business = await businessRepo.createBusiness(
      Business(
        id: 'biz-aging-test',
        name: 'Prime Retailers',
        phone: '9888800000',
        stateCode: '27',
        stateName: 'Maharashtra',
        currencyCode: 'INR',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    customer = await partyRepo.createParty(
      Party(
        id: 'cust-aging',
        businessId: business.id,
        name: 'Omega Tech Distributors',
        phone: '9888800001',
        partyType: PartyType.customer,
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    supplier = await partyRepo.createParty(
      Party(
        id: 'supp-aging',
        businessId: business.id,
        name: 'Zenith Logistics Ltd',
        phone: '9888800002',
        partyType: PartyType.supplier,
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
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

  group('Receivables & Payables Aging Analysis Tests', () {
    test('Calculates receivables aging across all 5 standard buckets', () async {
      final asOf = DateTime(2026, 4, 1);
      final db = await dbHelper.database;

      Future<void> insertInvoice({
        required String id,
        required String number,
        required DateTime dueDate,
        required int totalPaise,
        required int paidPaise,
      }) async {
        final dateStr = dueDate.subtract(const Duration(days: 15)).toIso8601String();
        await db.insert('invoices', {
          'id': id,
          'business_id': business.id,
          'customer_id': customer.id,
          'invoice_number': number,
          'invoice_date': dateStr,
          'due_date': dueDate.toIso8601String(),
          'place_of_supply_state_code': '27',
          'invoice_type': 'TAX_INVOICE',
          'status': paidPaise > 0 ? (totalPaise == paidPaise ? 'PAID' : 'PARTIAL') : 'FINALIZED',
          'subtotal_paise': totalPaise,
          'discount_paise': 0,
          'taxable_amount_paise': totalPaise,
          'cgst_paise': 0,
          'sgst_paise': 0,
          'igst_paise': 0,
          'cess_paise': 0,
          'round_off_paise': 0,
          'total_amount_paise': totalPaise,
          'paid_amount_paise': paidPaise,
          'balance_amount_paise': totalPaise - paidPaise,
          'created_at': dateStr,
          'updated_at': dateStr,
        });
      }

      // 1. Current (due tomorrow: 2026-04-02) -> 10,000 INR
      await insertInvoice(
        id: 'inv-cur',
        number: 'INV-CUR',
        dueDate: DateTime(2026, 4, 2),
        totalPaise: 1000000,
        paidPaise: 0,
      );

      // 2. Overdue 1-30 days (due 2026-03-20 -> 12 days overdue) -> 20,000 INR
      await insertInvoice(
        id: 'inv-1-30',
        number: 'INV-30',
        dueDate: DateTime(2026, 3, 20),
        totalPaise: 2000000,
        paidPaise: 0,
      );

      // 3. Overdue 31-60 days (due 2026-02-15 -> 45 days overdue) -> 30,000 INR, 10,000 paid -> 20,000 remaining
      await insertInvoice(
        id: 'inv-31-60',
        number: 'INV-60',
        dueDate: DateTime(2026, 2, 15),
        totalPaise: 3000000,
        paidPaise: 1000000,
      );

      // 4. Overdue 61-90 days (due 2026-01-15 -> 76 days overdue) -> 40,000 INR
      await insertInvoice(
        id: 'inv-61-90',
        number: 'INV-90',
        dueDate: DateTime(2026, 1, 15),
        totalPaise: 4000000,
        paidPaise: 0,
      );

      // 5. Overdue 90+ days (due 2025-12-01 -> 121 days overdue) -> 50,000 INR
      await insertInvoice(
        id: 'inv-90-plus',
        number: 'INV-90P',
        dueDate: DateTime(2025, 12, 1),
        totalPaise: 5000000,
        paidPaise: 0,
      );

      // 6. Fully paid invoice (should be completely excluded)
      await insertInvoice(
        id: 'inv-paid',
        number: 'INV-PAID',
        dueDate: DateTime(2025, 12, 1),
        totalPaise: 10000000,
        paidPaise: 10000000,
      );

      final report = await reportRepo.getReceivablesAgingReport(
        business.id,
        asOfDate: asOf,
      );

      expect(report.items.length, equals(1));
      final item = report.items.first;
      expect(item.partyName, equals('Omega Tech Distributors'));
      expect(item.currentPaise, equals(1000000));
      expect(item.days1To30Paise, equals(2000000));
      expect(item.days31To60Paise, equals(2000000)); // 30,000 - 10,000 paid = 20,000
      expect(item.days61To90Paise, equals(4000000));
      expect(item.days90PlusPaise, equals(5000000));
      expect(item.totalOutstandingPaise, equals(14000000)); // 1,40,000 INR

      // Check report aggregates
      expect(report.totalCurrentPaise, equals(1000000));
      expect(report.totalDays1To30Paise, equals(2000000));
      expect(report.totalDays31To60Paise, equals(2000000));
      expect(report.totalDays61To90Paise, equals(4000000));
      expect(report.totalDays90PlusPaise, equals(5000000));
      expect(report.totalOutstandingPaise, equals(14000000));

      // Test CSV Export
      final csv = CsvExportHelper.exportReceivablesAging(report);
      expect(csv.contains('Omega Tech Distributors'), isTrue);
      expect(csv.contains('140000.00'), isTrue);
    });

    test('Calculates payables aging accurately for supplier orders', () async {
      final asOf = DateTime(2026, 4, 1);
      final db = await dbHelper.database;
      final dateStr = DateTime(2026, 2, 15).toIso8601String();

      // Overdue purchase order (due 2026-03-01 -> 31 days overdue)
      await db.insert('purchases', {
        'id': 'po-1',
        'business_id': business.id,
        'supplier_id': supplier.id,
        'purchase_number': 'PUR-2026-001',
        'purchase_date': dateStr,
        'due_date': DateTime(2026, 3, 1).toIso8601String(),
        'status': 'PARTIAL',
        'subtotal_paise': 5000000,
        'discount_paise': 0,
        'taxable_amount_paise': 5000000,
        'cgst_paise': 0,
        'sgst_paise': 0,
        'igst_paise': 0,
        'round_off_paise': 0,
        'total_amount_paise': 5000000,
        'paid_amount_paise': 1000000,
        'balance_amount_paise': 4000000,
        'created_at': dateStr,
        'updated_at': dateStr,
      });

      final report = await reportRepo.getPayablesAgingReport(
        business.id,
        asOfDate: asOf,
      );

      expect(report.items.length, equals(1));
      final item = report.items.first;
      expect(item.partyName, equals('Zenith Logistics Ltd'));
      expect(item.days31To60Paise, equals(4000000));
      expect(item.totalOutstandingPaise, equals(4000000));

      final csv = CsvExportHelper.exportPayablesAging(report);
      expect(csv.contains('Zenith Logistics Ltd'), isTrue);
      expect(csv.contains('40000.00'), isTrue);
    });
  });
}
