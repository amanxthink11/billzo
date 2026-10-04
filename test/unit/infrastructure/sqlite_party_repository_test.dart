import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
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
  late Business testBusiness;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_party_repo_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);

    // Seed test business
    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-party-test',
        name: 'Apex Retailers',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SqlitePartyRepository Infrastructure Tests', () {
    final now = DateTime.now().toUtc();

    test('Creates Customer, Supplier, and Both-type parties successfully', () async {
      // 1. Create Customer
      final customer = await partyRepo.createParty(
        Party(
          id: 'cust-101',
          businessId: testBusiness.id,
          name: 'Mehta Brothers',
          partyType: PartyType.customer,
          phone: '9820112233',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          openingBalancePaise: 2500000, // ₹25,000 receivable
          openingBalanceType: OpeningBalanceType.toReceive,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(customer.id, equals('cust-101'));
      expect(customer.isCustomer, isTrue);

      // 2. Create Supplier
      final supplier = await partyRepo.createParty(
        Party(
          id: 'supp-201',
          businessId: testBusiness.id,
          name: 'Hindustan Distributors',
          partyType: PartyType.supplier,
          phone: '9811223344',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          openingBalancePaise: 4000000, // ₹40,000 payable
          openingBalanceType: OpeningBalanceType.toPay,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(supplier.id, equals('supp-201'));
      expect(supplier.isSupplier, isTrue);

      // 3. Create Both-type Party
      final bothParty = await partyRepo.createParty(
        Party(
          id: 'both-301',
          businessId: testBusiness.id,
          name: 'Universal Enterprises',
          partyType: PartyType.both,
          phone: '9833445566',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(bothParty.id, equals('both-301'));
      expect(bothParty.partyType, equals(PartyType.both));

      // Verify retrieval by ID
      final fetchedCust = await partyRepo.getPartyById('cust-101');
      expect(fetchedCust, isNotNull);
      expect(fetchedCust!.name, equals('Mehta Brothers'));
      expect(fetchedCust.partyType, equals(PartyType.customer));

      final fetchedBoth = await partyRepo.getPartyById('both-301');
      expect(fetchedBoth, isNotNull);
      expect(fetchedBoth!.partyType, equals(PartyType.both));
    });

    test('Opening balance creates double-entry journal entries in ledger_entries', () async {
      await partyRepo.createParty(
        Party(
          id: 'cust-ledger-test',
          businessId: testBusiness.id,
          name: 'Kulkarni Stores',
          partyType: PartyType.customer,
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          openingBalancePaise: 1500000, // ₹15,000 receivable
          openingBalanceType: OpeningBalanceType.toReceive,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final db = await dbHelper.database;

      // Verify ledger_entries created
      final entries = await db.query(
        'ledger_entries',
        where: 'business_id = ? AND transaction_id = ?',
        whereArgs: [testBusiness.id, 'cust-ledger-test'],
      );

      expect(entries.length, equals(2)); // Balanced Debit + Credit

      int totalDebit = 0;
      int totalCredit = 0;
      for (final entry in entries) {
        totalDebit += entry['debit_paise'] as int;
        totalCredit += entry['credit_paise'] as int;
      }

      // Invariant: Total Debits == Total Credits == 1500000 paise
      expect(totalDebit, equals(1500000));
      expect(totalCredit, equals(1500000));
      expect(totalDebit, equals(totalCredit));
    });

    test('Search and filter parties by name, phone, gstin, and type', () async {
      await partyRepo.createParty(
        Party(
          id: 'search-1',
          businessId: testBusiness.id,
          name: 'Anand Book Depot',
          partyType: PartyType.customer,
          phone: '9900112233',
          gstin: '27AABCA1234A1Z1',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await partyRepo.createParty(
        Party(
          id: 'search-2',
          businessId: testBusiness.id,
          name: 'Bhavna Paper Mill',
          partyType: PartyType.supplier,
          phone: '9911223344',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Search by name
      final nameResults = await partyRepo.getParties(
        businessId: testBusiness.id,
        searchQuery: 'Anand',
      );
      expect(nameResults.length, equals(1));
      expect(nameResults.first.name, equals('Anand Book Depot'));

      // Search by phone
      final phoneResults = await partyRepo.getParties(
        businessId: testBusiness.id,
        searchQuery: '9911223344',
      );
      expect(phoneResults.length, equals(1));
      expect(phoneResults.first.name, equals('Bhavna Paper Mill'));

      // Search by GSTIN
      final gstinResults = await partyRepo.getParties(
        businessId: testBusiness.id,
        searchQuery: '27AABCA1234A1Z1',
      );
      expect(gstinResults.length, equals(1));

      // Filter by Customer
      final customers = await partyRepo.getParties(
        businessId: testBusiness.id,
        typeFilter: PartyType.customer,
      );
      expect(customers.any((p) => p.name == 'Anand Book Depot'), isTrue);
      expect(customers.any((p) => p.name == 'Bhavna Paper Mill'), isFalse);
    });

    test('Deactivation, reactivation, and soft deletion maintain integrity', () async {
      final party = await partyRepo.createParty(
        Party(
          id: 'status-test',
          businessId: testBusiness.id,
          name: 'Status Test Merchant',
          partyType: PartyType.customer,
          phone: '9822334455',
          billingStateCode: '27',
          billingStateName: 'Maharashtra',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Deactivate
      await partyRepo.setPartyActiveStatus(party.id, false);
      var fetched = await partyRepo.getPartyById(party.id);
      expect(fetched!.isActive, isFalse);

      // Reactivate
      await partyRepo.setPartyActiveStatus(party.id, true);
      fetched = await partyRepo.getPartyById(party.id);
      expect(fetched!.isActive, isTrue);

      // Soft delete
      await partyRepo.softDeleteParty(party.id);
      fetched = await partyRepo.getPartyById(party.id);
      expect(fetched, isNull); // Soft deleted items excluded from normal query
    });
  });

  test('Party data survives database close and simulated restart', () async {
    final diskDbPath = '${tempDir.path}${Platform.pathSeparator}restart_party_test.db';
    final diskHelper = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final diskBusinessRepo = SqliteBusinessRepository(dbHelper: diskHelper);
    final diskPartyRepo = SqlitePartyRepository(diskHelper);

    final biz = await diskBusinessRepo.createBusiness(
      Business(
        id: 'biz-disk-test',
        name: 'Persistent Traders',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    await diskPartyRepo.createParty(
      Party(
        id: 'persistent-party-1',
        businessId: biz.id,
        name: 'Evergreen Stationery',
        partyType: PartyType.customer,
        phone: '9844556677',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        openingBalancePaise: 500000,
        openingBalanceType: OpeningBalanceType.toReceive,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Simulate application restart
    await diskHelper.close();

    final reopenedHelper = DatabaseHelper.createForTesting(
      dbPath: diskDbPath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );
    final reopenedPartyRepo = SqlitePartyRepository(reopenedHelper);

    final restoredParty = await reopenedPartyRepo.getPartyById('persistent-party-1');
    expect(restoredParty, isNotNull);
    expect(restoredParty!.name, equals('Evergreen Stationery'));
    expect(restoredParty.openingBalancePaise, equals(500000));

    await reopenedHelper.close();
  });
}
