import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/catalog/product.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/domain/purchase/itc_eligibility.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_purchase_repository.dart';
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
  late SqlitePurchaseRepository purchaseRepo;
  late SqlitePaymentRepository paymentRepo;

  late Business testBusiness;
  late Party testSupplier;
  late Product testProduct;
  late CashBankAccount bankAccount;
  late String taxRate18Id;
  late String unitPcsId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('billzo_supplier_payment_test_');
    dbHelper = DatabaseHelper.createForTesting(
      dbPath: inMemoryDatabasePath,
      pathProvider: MockPathProvider(tempDir),
      dbFactory: databaseFactoryFfi,
    );

    businessRepo = SqliteBusinessRepository(dbHelper: dbHelper);
    partyRepo = SqlitePartyRepository(dbHelper);
    productRepo = SqliteProductRepository(dbHelper);
    purchaseRepo = SqlitePurchaseRepository(dbHelper);
    paymentRepo = SqlitePaymentRepository(dbHelper);

    testBusiness = await businessRepo.createBusiness(
      Business(
        id: 'biz-pay-1',
        name: 'Payment Integration Corp',
        phone: '9876543210',
        stateCode: '27',
        stateName: 'Maharashtra',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final db = await dbHelper.database;
    final taxRateRows = await db.query('tax_rates', where: 'business_id = ?', whereArgs: [testBusiness.id]);
    taxRate18Id = taxRateRows.firstWhere((r) => r['rate_basis_points'] == 1800)['id'] as String;

    final unitRows = await db.query('units', where: 'business_id = ?', whereArgs: [testBusiness.id]);
    unitPcsId = unitRows.firstWhere((u) => u['code'] == 'PCS')['id'] as String;

    testSupplier = await partyRepo.createParty(
      Party(
        id: 'supp-pay-1',
        businessId: testBusiness.id,
        name: 'Apex Machinery Suppliers',
        phone: '9833445566',
        partyType: PartyType.supplier,
        gstin: '27AABCA1234F1Z8',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        currentBalancePaise: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    testProduct = await productRepo.createProduct(
      Product(
        id: 'prod-pay-1',
        businessId: testBusiness.id,
        name: 'Steel Sheet 2mm',
        sku: 'ST-002',
        unitId: unitPcsId,
        taxRateId: taxRate18Id,
        purchasePricePaise: 100000,
        sellingPricePaise: 150000,
        currentStock: 0.0,
        openingStock: 0.0,
        itemType: ItemType.product,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // Create a bank account with initial balance ₹100,000.00 (10,000,000 paise)
    bankAccount = await paymentRepo.createCashBankAccount(
      CashBankAccount(
        id: 'bank-acc-1',
        businessId: testBusiness.id,
        name: 'HDFC Current Account',
        accountType: CashBankAccountType.bank,
        accountNumber: '50200012345678',
        ifscCode: 'HDFC0001234',
        bankName: 'HDFC Bank',
        openingBalancePaise: 10000000,
        currentBalancePaise: 10000000,
        isDefault: true,
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

  group('Supplier Payment & Allocation Tests', () {
    test('Single purchase bill payment updates purchase, supplier balance, bank account, and posts balanced journal', () async {
      final now = DateTime.now().toUtc();

      // Finalize purchase of ₹10,000 taxable + ₹1,800 GST = ₹11,800
      final purchase = await purchaseRepo.finalizePurchase(
        Purchase(
          id: 'pur-single-pay',
          businessId: testBusiness.id,
          supplierId: testSupplier.id,
          purchaseNumber: '',
          supplierInvoiceNumber: 'INV-BILL-01',
          supplierInvoiceDate: now,
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          status: PurchaseStatus.draft,
          subtotalPaise: 1000000,
          taxableAmountPaise: 1000000,
          cgstPaise: 90000,
          sgstPaise: 90000,
          totalAmountPaise: 1180000,
          balanceAmountPaise: 1180000,
          itcEligibility: ItcEligibility.eligible,
          inputCgstPaise: 90000,
          inputSgstPaise: 90000,
          items: [
            PurchaseItem(
              id: '',
              purchaseId: '',
              productId: testProduct.id,
              productName: testProduct.name,
              unitCode: 'PCS',
              quantityScaled: 10000,
              purchaseRatePaise: 100000,
              taxableAmountPaise: 1000000,
              taxRateId: taxRate18Id,
              rateBasisPoints: 1800,
              cgstRateBasisPoints: 900,
              cgstAmountPaise: 90000,
              sgstRateBasisPoints: 900,
              sgstAmountPaise: 90000,
              totalAmountPaise: 1180000,
              trackInventory: true,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Verify initial supplier balance is ₹11,800
      final suppBefore = await partyRepo.getPartyById(testSupplier.id);
      expect(suppBefore!.currentBalancePaise, 1180000);

      // Record partial payment of ₹5,000 against this purchase
      final payment = Payment(
        id: 'pay-supp-1',
        businessId: testBusiness.id,
        customerId: testSupplier.id,
        partyType: PartyType.supplier,
        paymentNumber: '',
        paymentDate: now,
        paymentMethod: PaymentMethod.bankTransfer,
        amountPaise: 500000, // ₹5,000.00
        accountId: bankAccount.id,
        referenceNumber: 'NEFT-12345',
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: '',
            paymentId: '',
            documentId: purchase.id,
            documentType: 'PURCHASE',
            allocatedAmountPaise: 500000,
            invoiceNumber: purchase.purchaseNumber,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final posted = await paymentRepo.postPayment(payment);
      expect(posted.paymentNumber, isNotEmpty);
      expect(posted.status, PaymentStatus.posted);

      // 1. Purchase balance updated
      final updatedPurchase = await purchaseRepo.getPurchaseById(purchase.id);
      expect(updatedPurchase!.paidAmountPaise, 500000);
      expect(updatedPurchase.balanceAmountPaise, 1180000 - 500000);
      expect(updatedPurchase.status, PurchaseStatus.partiallyPaid);

      // 2. Supplier balance reduced by ₹5,000 (₹11,800 - ₹5,000 = ₹6,800)
      final suppAfter = await partyRepo.getPartyById(testSupplier.id);
      expect(suppAfter!.currentBalancePaise, 1180000 - 500000);

      // 3. Bank Account balance reduced by ₹5,000
      final updatedBank = await paymentRepo.getCashBankAccountById(bankAccount.id);
      expect(updatedBank!.currentBalancePaise, 10000000 - 500000);

      // 4. Double-entry accounting entry balances exactly
      final db = await dbHelper.database;
      final paymentLedger = await db.query(
        'ledger_entries',
        where: 'transaction_id = ?',
        whereArgs: [posted.id],
      );
      expect(paymentLedger.isNotEmpty, isTrue);

      int totalDebit = 0;
      int totalCredit = 0;
      for (final e in paymentLedger) {
        totalDebit += e['debit_paise'] as int;
        totalCredit += e['credit_paise'] as int;
      }
      expect(totalDebit, 500000);
      expect(totalCredit, 500000);
    });

    test('Multi-purchase payment allocation distributes correctly across multiple purchase bills', () async {
      final now = DateTime.now().toUtc();

      // Purchase A: ₹8,000
      final purchaseA = await purchaseRepo.finalizePurchase(
        Purchase(
          id: 'pur-a',
          businessId: testBusiness.id,
          supplierId: testSupplier.id,
          purchaseNumber: '',
          supplierInvoiceNumber: 'INV-A',
          supplierInvoiceDate: now,
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          status: PurchaseStatus.draft,
          subtotalPaise: 800000,
          taxableAmountPaise: 800000,
          totalAmountPaise: 800000,
          balanceAmountPaise: 800000,
          itcEligibility: ItcEligibility.ineligible,
          items: [
            PurchaseItem(
              id: '',
              purchaseId: '',
              productId: testProduct.id,
              productName: testProduct.name,
              unitCode: 'PCS',
              quantityScaled: 8000,
              purchaseRatePaise: 100000,
              taxableAmountPaise: 800000,
              taxRateId: taxRate18Id,
              totalAmountPaise: 800000,
              trackInventory: true,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Purchase B: ₹5,000
      final purchaseB = await purchaseRepo.finalizePurchase(
        Purchase(
          id: 'pur-b',
          businessId: testBusiness.id,
          supplierId: testSupplier.id,
          purchaseNumber: '',
          supplierInvoiceNumber: 'INV-B',
          supplierInvoiceDate: now,
          purchaseDate: now,
          dueDate: now.add(const Duration(days: 30)),
          placeOfSupplyStateCode: '27',
          status: PurchaseStatus.draft,
          subtotalPaise: 500000,
          taxableAmountPaise: 500000,
          totalAmountPaise: 500000,
          balanceAmountPaise: 500000,
          itcEligibility: ItcEligibility.ineligible,
          items: [
            PurchaseItem(
              id: '',
              purchaseId: '',
              productId: testProduct.id,
              productName: testProduct.name,
              unitCode: 'PCS',
              quantityScaled: 5000,
              purchaseRatePaise: 100000,
              taxableAmountPaise: 500000,
              taxRateId: taxRate18Id,
              totalAmountPaise: 500000,
              trackInventory: true,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Total payable is ₹8,000 + ₹5,000 = ₹13,000
      final suppBefore = await partyRepo.getPartyById(testSupplier.id);
      expect(suppBefore!.currentBalancePaise, 1300000);

      // Pay ₹10,000: ₹8,000 to Purchase A (full), ₹2,000 to Purchase B (partial)
      final multiPayment = Payment(
        id: 'pay-multi-1',
        businessId: testBusiness.id,
        customerId: testSupplier.id,
        partyType: PartyType.supplier,
        paymentNumber: '',
        paymentDate: now,
        paymentMethod: PaymentMethod.bankTransfer,
        amountPaise: 1000000, // ₹10,000
        accountId: bankAccount.id,
        status: PaymentStatus.posted,
        allocations: [
          PaymentAllocation(
            id: '',
            paymentId: '',
            documentId: purchaseA.id,
            documentType: 'PURCHASE',
            allocatedAmountPaise: 800000,
            createdAt: now,
            updatedAt: now,
          ),
          PaymentAllocation(
            id: '',
            paymentId: '',
            documentId: purchaseB.id,
            documentType: 'PURCHASE',
            allocatedAmountPaise: 200000,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final posted = await paymentRepo.postPayment(multiPayment);

      // 1. Purchase A is PAID (0 balance)
      final resA = await purchaseRepo.getPurchaseById(purchaseA.id);
      expect(resA!.balanceAmountPaise, 0);
      expect(resA.status, PurchaseStatus.paid);

      // 2. Purchase B is PARTIALLY PAID (₹3,000 balance remaining)
      final resB = await purchaseRepo.getPurchaseById(purchaseB.id);
      expect(resB!.balanceAmountPaise, 300000);
      expect(resB.status, PurchaseStatus.partiallyPaid);

      // 3. Supplier total payable is ₹3,000
      final suppAfter = await partyRepo.getPartyById(testSupplier.id);
      expect(suppAfter!.currentBalancePaise, 300000);

      // 4. Cancel the payment -> everything reverses atomically
      final cancelled = await paymentRepo.cancelPayment(
        posted.id,
        cancellationReason: 'Disbursement cancelled due to wrong supplier bank details',
      );
      expect(cancelled.isCancelled, isTrue);

      // 5. Purchase A & B balances restored
      final restoredA = await purchaseRepo.getPurchaseById(purchaseA.id);
      expect(restoredA!.balanceAmountPaise, 800000);
      expect(restoredA.status, PurchaseStatus.finalized);

      final restoredB = await purchaseRepo.getPurchaseById(purchaseB.id);
      expect(restoredB!.balanceAmountPaise, 500000);
      expect(restoredB.status, PurchaseStatus.finalized);

      // 6. Supplier payable restored to ₹13,000
      final restoredSupp = await partyRepo.getPartyById(testSupplier.id);
      expect(restoredSupp!.currentBalancePaise, 1300000);

      // 7. Bank Account balance restored to original
      final restoredBank = await paymentRepo.getCashBankAccountById(bankAccount.id);
      expect(restoredBank!.currentBalancePaise, 10000000);
    });
  });
}
