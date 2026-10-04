import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/recurring/recurring_execution_status.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_execution.dart';
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_recurring_invoice_repository.dart';
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
  late String dbFilePath;
  DatabaseHelper? activeDbHelper;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_rec_persistence_test_');
    dbFilePath = '${tempDir.path}${Platform.pathSeparator}billzo_test.db';
  });

  tearDown(() async {
    if (activeDbHelper != null) {
      try {
        await activeDbHelper!.close();
      } catch (_) {}
    }
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('Recurring profile, item templates, and executions survive application restart', () async {
    // 1. Initial Session
    var dbHelper = DatabaseHelper.createForTesting(
      dbPath: dbFilePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    activeDbHelper = dbHelper;

    final bizRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    final partyRepo = SqlitePartyRepository(dbHelper);
    final prodRepo = SqliteProductRepository(dbHelper);
    final taxRepo = SqliteTaxRateRepository(dbHelper);
    final unitRepo = SqliteUnitRepository(dbHelper);
    var recRepo = SqliteRecurringInvoiceRepository(dbHelper);

    final biz = await bizRepo.createBusiness(
      Business(
        id: 'biz-persist-1',
        name: 'Persistence Enterprise',
        phone: '9988776655',
        stateCode: '29',
        stateName: 'Karnataka',
        currencyCode: 'INR',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final customer = await partyRepo.createParty(
      Party(
        id: 'cust-persist-1',
        businessId: biz.id,
        name: 'Alpha Industries',
        phone: '9888877777',
        partyType: PartyType.customer,
        billingStateCode: '29',
        billingStateName: 'Karnataka',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final taxes = await taxRepo.getTaxRates(biz.id);
    final tax = taxes.first;

    final units = await unitRepo.getUnits(biz.id);
    final unit = units.first;

    final product = await prodRepo.createProduct(
      Product(
        id: 'prod-audit-1',
        businessId: biz.id,
        name: 'Statutory Compliance Audit',
        unitId: unit.id,
        taxRateId: tax.id,
        itemType: ItemType.service,
        purchasePricePaise: 0,
        sellingPricePaise: 2500000,
        hsnSacCode: '998222',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final now = DateTime(2026, 2, 1);
    final profile = RecurringInvoice(
      id: 'rec-persist-alpha',
      businessId: biz.id,
      customerId: customer.id,
      customerName: customer.name,
      profileName: 'Quarterly Audit Retainer',
      frequency: RecurringFrequency.quarterly,
      startDate: now,
      nextRunDate: now,
      status: RecurringInvoiceStatus.active,
      items: [
        RecurringInvoiceItem(
          id: 'item-p-1',
          recurringInvoiceId: 'rec-persist-alpha',
          productId: product.id,
          taxRateId: tax.id,
          productName: 'Statutory Compliance Audit',
          hsnSac: '998222',
          quantity: 1,
          unitCode: unit.shortName,
          ratePaise: 2500000, // 25,000 INR
          discountPaise: 100000, // 1,000 INR
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await recRepo.createProfile(profile);

    // Record an execution
    await recRepo.recordExecution(
      RecurringInvoiceExecution(
        id: 'exec-1',
        recurringInvoiceId: profile.id,
        invoiceId: null,
        scheduledForDate: now,
        executedAt: DateTime.now(),
        executionStatus: RecurringExecutionStatus.success,
        notes: 'Successfully generated first quarter audit invoice',
        createdAt: DateTime.now(),
      ),
    );

    // Verify execution exists in active session
    expect(await recRepo.hasExecutionForDate(profile.id, now), isTrue);

    // 2. SIMULATE APPLICATION CRASH / RESTART
    await dbHelper.close();
    activeDbHelper = null;

    // 3. Re-open database fresh from disk
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: dbFilePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    activeDbHelper = dbHelper;
    recRepo = SqliteRecurringInvoiceRepository(dbHelper);

    // Verify profile survived restart
    final fetched = await recRepo.getProfileById('rec-persist-alpha');
    expect(fetched, isNotNull);
    expect(fetched!.profileName, equals('Quarterly Audit Retainer'));
    expect(fetched.frequency, equals(RecurringFrequency.quarterly));
    expect(fetched.items.length, equals(1));
    expect(fetched.items.first.productName, equals('Statutory Compliance Audit'));
    expect(fetched.items.first.hsnSac, equals('998222'));
    expect(fetched.items.first.ratePaise, equals(2500000));
    expect(fetched.items.first.discountPaise, equals(100000));

    // Verify execution history survived restart
    final executions = await recRepo.getExecutions('rec-persist-alpha');
    expect(executions.length, equals(1));
    expect(executions.first.id, equals('exec-1'));
    expect(executions.first.executionStatus, equals(RecurringExecutionStatus.success));

    // Verify idempotency check survives restart
    expect(await recRepo.hasExecutionForDate('rec-persist-alpha', now), isTrue);

    await dbHelper.close();
    activeDbHelper = null;
  });
}
