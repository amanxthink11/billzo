import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/application/invoice/invoice_service.dart';
import 'package:billzo/application/recurring/recurring_invoice_service.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/catalog/tax_rate.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/recurring/recurring_execution_status.dart';
import 'package:billzo/domain/recurring/recurring_frequency.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_invoice_repository.dart';
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
  late DatabaseHelper dbHelper;

  late SqliteBusinessRepository businessRepo;
  late SqlitePartyRepository partyRepo;
  late SqliteProductRepository productRepo;
  late SqliteTaxRateRepository taxRepo;
  late SqliteUnitRepository unitRepo;
  late SqliteInvoiceRepository invoiceRepo;
  late SqliteRecurringInvoiceRepository recurringRepo;
  late InvoiceService invoiceService;
  late RecurringInvoiceService recurringService;

  late Business testBusiness;
  late Party testCustomer;
  late Product testServiceProduct;
  late TaxRate tax18;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_recurring_service_test_');
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
    invoiceRepo = SqliteInvoiceRepository(dbHelper);
    recurringRepo = SqliteRecurringInvoiceRepository(dbHelper);

    invoiceService = InvoiceService(invoiceRepo);

    recurringService = RecurringInvoiceService(
      recurringRepo: recurringRepo,
      invoiceService: invoiceService,
      partyRepo: partyRepo,
      businessRepo: businessRepo,
      taxRateRepo: taxRepo,
    );

    // Seed master business
    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-rec-test',
        name: 'Nexus Cloud Technologies',
        phone: '9876543210',
        stateCode: '27', // Maharashtra
        stateName: 'Maharashtra',
        currencyCode: 'INR',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Seed customer
    testCustomer = await partyRepo.createParty(
      Party(
        id: 'cust-rec-test',
        businessId: testBusiness.id,
        name: 'Omni Retail Ltd',
        phone: '9123456789',
        partyType: PartyType.customer,
        billingStateCode: '27', // Intra-state
        billingStateName: 'Maharashtra',
        gstin: '27AAAAA0000A1Z5',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Get seeded unit
    final units = await unitRepo.getUnits(testBusiness.id);
    final unit = units.first;

    // Fetch default 18% tax rate
    final taxes = await taxRepo.getTaxRates(testBusiness.id);
    tax18 = taxes.firstWhere((t) => t.rateBasisPoints == 1800, orElse: () => taxes.first);

    // Seed recurring service product
    testServiceProduct = await productRepo.createProduct(
      Product(
        id: 'prod-saas-sub',
        businessId: testBusiness.id,
        name: 'Cloud ERP Monthly Subscription',
        unitId: unit.id,
        taxRateId: tax18.id,
        itemType: ItemType.service,
        purchasePricePaise: 0,
        sellingPricePaise: 500000, // 5,000 INR
        hsnSacCode: '998313',
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

  group('RecurringInvoiceService Workflow & Catch-Up Tests', () {
    test('Lifecycle operations: Create profile, pause, resume, and cancel', () async {
      final now = DateTime(2026, 1, 1);
      final profile = RecurringInvoice(
        id: 'rec-test-1',
        businessId: testBusiness.id,
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        profileName: 'Monthly Cloud Subscription',
        frequency: RecurringFrequency.monthly,
        startDate: now,
        nextRunDate: now,
        status: RecurringInvoiceStatus.active,
        items: [
          RecurringInvoiceItem(
            id: 'item-rec-1',
            recurringInvoiceId: 'rec-test-1',
            productId: testServiceProduct.id,
            taxRateId: tax18.id,
            productName: testServiceProduct.name,
            quantity: 1,
            unitCode: 'MON',
            ratePaise: 500000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final created = await recurringService.createProfile(profile);
      expect(created.id, equals('rec-test-1'));
      expect(created.status, equals(RecurringInvoiceStatus.active));

      // Pause profile
      await recurringService.pauseProfile('rec-test-1');
      var fetched = await recurringService.getProfileById('rec-test-1');
      expect(fetched?.status, equals(RecurringInvoiceStatus.paused));

      // Resume profile
      await recurringService.resumeProfile('rec-test-1');
      fetched = await recurringService.getProfileById('rec-test-1');
      expect(fetched?.status, equals(RecurringInvoiceStatus.active));

      // Cancel profile
      await recurringService.cancelProfile('rec-test-1');
      fetched = await recurringService.getProfileById('rec-test-1');
      expect(fetched?.status, equals(RecurringInvoiceStatus.cancelled));
    });

    test('generateInvoiceForCycle enforces absolute idempotency', () async {
      final cycleDate = DateTime(2026, 2, 1);
      final profile = RecurringInvoice(
        id: 'rec-idempotent',
        businessId: testBusiness.id,
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        profileName: 'Idempotency Guarantee Profile',
        frequency: RecurringFrequency.monthly,
        startDate: cycleDate,
        nextRunDate: cycleDate,
        status: RecurringInvoiceStatus.active,
        autoGenerate: false,
        requireReview: true,
        items: [
          RecurringInvoiceItem(
            id: 'item-idem-1',
            recurringInvoiceId: 'rec-idempotent',
            productId: testServiceProduct.id,
            taxRateId: tax18.id,
            productName: testServiceProduct.name,
            quantity: 2,
            unitCode: 'MON',
            ratePaise: 500000, // 5,000 * 2 = 10,000 INR
            createdAt: cycleDate,
            updatedAt: cycleDate,
          ),
        ],
        createdAt: cycleDate,
        updatedAt: cycleDate,
      );
      await recurringService.createProfile(profile);

      // First run: successfully generates invoice
      final invoice = await recurringService.generateInvoiceForCycle(profile, cycleDate);
      expect(invoice, isNotNull);
      expect(invoice!.status, equals(InvoiceStatus.draft));
      expect(invoice.taxableAmountPaise, equals(1000000));
      expect(invoice.cgstPaise, equals(90000)); // 9% of 10,000 INR = 900 INR
      expect(invoice.sgstPaise, equals(90000));
      expect(invoice.totalAmountPaise, equals(1180000));

      // Verify execution was logged
      final executions = await recurringService.getExecutions('rec-idempotent');
      expect(executions.length, equals(1));
      expect(executions.first.executionStatus, equals(RecurringExecutionStatus.reviewQueued));

      // Second run for EXACT SAME cycle date: must return null (idempotent no-op!)
      final duplicateInvoice = await recurringService.generateInvoiceForCycle(profile, cycleDate);
      expect(duplicateInvoice, isNull);

      // Execution count remains exactly 1
      final executionsAfter = await recurringService.getExecutions('rec-idempotent');
      expect(executionsAfter.length, equals(1));
    });

    test('detectMissedSchedules finds overdue dates when app is opened after being offline', () async {
      final startDate = DateTime(2026, 1, 1);
      final profile = RecurringInvoice(
        id: 'rec-catchup-1',
        businessId: testBusiness.id,
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        profileName: 'Offline Catchup Profile',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        nextRunDate: startDate,
        status: RecurringInvoiceStatus.active,
        items: [
          RecurringInvoiceItem(
            id: 'item-c-1',
            recurringInvoiceId: 'rec-catchup-1',
            productId: testServiceProduct.id,
            taxRateId: tax18.id,
            productName: testServiceProduct.name,
            quantity: 1,
            unitCode: 'MON',
            ratePaise: 500000,
            createdAt: startDate,
            updatedAt: startDate,
          ),
        ],
        createdAt: startDate,
        updatedAt: startDate,
      );
      await recurringService.createProfile(profile);

      // Suppose app was opened on April 10, 2026
      final simulatedToday = DateTime(2026, 4, 10);
      final missed = await recurringService.detectMissedSchedules(
        testBusiness.id,
        asOfDate: simulatedToday,
      );

      expect(missed.length, equals(1));
      expect(missed.first.profile.id, equals('rec-catchup-1'));
      // Missed cycles: Jan 1, Feb 1, Mar 1, Apr 1
      expect(missed.first.missedDates.length, equals(4));
    });

    test('processMissedSchedules with generateLatestOnly generates single latest invoice and skips older dates', () async {
      final startDate = DateTime(2026, 1, 1);
      final profile = RecurringInvoice(
        id: 'rec-catchup-latest',
        businessId: testBusiness.id,
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        profileName: 'Latest Only Resolution',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        nextRunDate: startDate,
        status: RecurringInvoiceStatus.active,
        items: [
          RecurringInvoiceItem(
            id: 'item-l-1',
            recurringInvoiceId: 'rec-catchup-latest',
            productId: testServiceProduct.id,
            taxRateId: tax18.id,
            productName: testServiceProduct.name,
            quantity: 1,
            unitCode: 'MON',
            ratePaise: 500000,
            createdAt: startDate,
            updatedAt: startDate,
          ),
        ],
        createdAt: startDate,
        updatedAt: startDate,
      );
      await recurringService.createProfile(profile);

      final simulatedToday = DateTime(2026, 3, 15);
      await recurringService.processMissedSchedules(
        testBusiness.id,
        [
          MissedScheduleResolution(
            profileId: 'rec-catchup-latest',
            action: MissedResolutionAction.generateLatestOnly,
          ),
        ],
        asOfDate: simulatedToday,
      );

      final executions = await recurringService.getExecutions('rec-catchup-latest');
      // Cycles were Jan 1, Feb 1, Mar 1
      expect(executions.length, equals(3));
      // Jan 1 and Feb 1 are skipped
      expect(executions.where((e) => e.executionStatus == RecurringExecutionStatus.skipped).length, equals(2));
      // Mar 1 was generated (reviewQueued because requireReview is true)
      final latestExec = executions.firstWhere((e) => e.scheduledForDate == DateTime(2026, 3, 1));
      expect(latestExec.executionStatus, equals(RecurringExecutionStatus.reviewQueued));

      // Profile schedule updated to next future date (April 1, 2026)
      final updatedProfile = await recurringService.getProfileById('rec-catchup-latest');
      expect(updatedProfile?.nextRunDate, equals(DateTime(2026, 4, 1)));
    });

    test('processMissedSchedules with skipAll skips all overdue runs and updates schedule to future', () async {
      final startDate = DateTime(2026, 1, 1);
      final profile = RecurringInvoice(
        id: 'rec-catchup-skip',
        businessId: testBusiness.id,
        customerId: testCustomer.id,
        customerName: testCustomer.name,
        profileName: 'Skip All Resolution',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        nextRunDate: startDate,
        status: RecurringInvoiceStatus.active,
        items: [
          RecurringInvoiceItem(
            id: 'item-s-1',
            recurringInvoiceId: 'rec-catchup-skip',
            productId: testServiceProduct.id,
            taxRateId: tax18.id,
            productName: testServiceProduct.name,
            quantity: 1,
            unitCode: 'MON',
            ratePaise: 500000,
            createdAt: startDate,
            updatedAt: startDate,
          ),
        ],
        createdAt: startDate,
        updatedAt: startDate,
      );
      await recurringService.createProfile(profile);

      final simulatedToday = DateTime(2026, 3, 15);
      await recurringService.processMissedSchedules(
        testBusiness.id,
        [
          MissedScheduleResolution(
            profileId: 'rec-catchup-skip',
            action: MissedResolutionAction.skipAll,
          ),
        ],
        asOfDate: simulatedToday,
      );

      final executions = await recurringService.getExecutions('rec-catchup-skip');
      expect(executions.length, equals(3));
      expect(executions.every((e) => e.executionStatus == RecurringExecutionStatus.skipped), isTrue);

      final updatedProfile = await recurringService.getProfileById('rec-catchup-skip');
      expect(updatedProfile?.nextRunDate, equals(DateTime(2026, 4, 1)));
    });
  });
}
