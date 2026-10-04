import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:billzo/application/business/business_service.dart';
import 'package:billzo/application/catalog/catalog_service.dart';
import 'package:billzo/application/party/party_service.dart';
import 'package:billzo/application/settings/settings_service.dart';
import 'package:billzo/domain/business/business_repository.dart';
import 'package:billzo/domain/catalog/category_repository.dart';
import 'package:billzo/domain/catalog/product_repository.dart';
import 'package:billzo/domain/catalog/tax_rate_repository.dart';
import 'package:billzo/domain/catalog/unit_repository.dart';
import 'package:billzo/domain/party/party_repository.dart';
import 'package:billzo/domain/settings/settings_repository.dart';
import 'package:billzo/infrastructure/platform/app_path_provider.dart';
import 'package:billzo/infrastructure/repositories/sqlite_business_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_category_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_party_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_settings_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_tax_rate_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_unit_repository.dart';
import 'package:billzo/application/invoice/invoice_service.dart';
import 'package:billzo/domain/invoice/invoice_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_invoice_repository.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';
import 'package:billzo/application/payment/payment_service.dart';
import 'package:billzo/domain/payment/payment_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:billzo/application/purchase/purchase_service.dart';
import 'package:billzo/domain/purchase/purchase_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_purchase_repository.dart';
import 'package:billzo/application/expense/expense_service.dart';
import 'package:billzo/domain/expense/expense_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_expense_repository.dart';
import 'package:billzo/application/reports/report_service.dart';
import 'package:billzo/domain/reports/report_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_report_repository.dart';
import 'package:billzo/application/reports/accounting_integrity_service.dart';
import 'package:billzo/application/recurring/recurring_invoice_service.dart';
import 'package:billzo/domain/recurring/recurring_invoice_repository.dart';
import 'package:billzo/infrastructure/repositories/sqlite_recurring_invoice_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// Provider for platform filesystem path resolutions.
final pathProvider = Provider<IAppPathProvider>((ref) {
  return ProductionAppPathProvider();
});

/// Provider for SQLite connection and lifecycle helper.
final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  final paths = ref.watch(pathProvider);
  return DatabaseHelper.getInstance(pathProvider: paths);
});

/// Provider for BusinessRepository.
final businessRepositoryProvider = Provider<IBusinessRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteBusinessRepository(dbHelper: dbHelper);
});

/// Provider for SettingsRepository.
final settingsRepositoryProvider = Provider<ISettingsRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteSettingsRepository(dbHelper: dbHelper);
});

/// Provider for PartyRepository.
final partyRepositoryProvider = Provider<IPartyRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqlitePartyRepository(dbHelper);
});

/// Provider for CategoryRepository.
final categoryRepositoryProvider = Provider<ICategoryRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteCategoryRepository(dbHelper);
});

/// Provider for UnitRepository.
final unitRepositoryProvider = Provider<IUnitRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteUnitRepository(dbHelper);
});

/// Provider for TaxRateRepository.
final taxRateRepositoryProvider = Provider<ITaxRateRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteTaxRateRepository(dbHelper);
});

/// Provider for ProductRepository.
final productRepositoryProvider = Provider<IProductRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteProductRepository(dbHelper);
});

/// Provider for Business application service.
final businessServiceProvider = Provider<BusinessService>((ref) {
  final repo = ref.watch(businessRepositoryProvider);
  return BusinessService(repo);
});

/// Provider for Settings application service.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return SettingsService(repo);
});

/// Provider for Party application service.
final partyServiceProvider = Provider<PartyService>((ref) {
  final repo = ref.watch(partyRepositoryProvider);
  return PartyService(repo);
});

/// Provider for Catalog application service.
final catalogServiceProvider = Provider<CatalogService>((ref) {
  return CatalogService(
    ref.watch(productRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(unitRepositoryProvider),
    ref.watch(taxRateRepositoryProvider),
  );
});

/// Provider for InvoiceRepository.
final invoiceRepositoryProvider = Provider<IInvoiceRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteInvoiceRepository(dbHelper);
});

/// Provider for Invoice application service.
final invoiceServiceProvider = Provider<InvoiceService>((ref) {
  final repo = ref.watch(invoiceRepositoryProvider);
  return InvoiceService(repo);
});

/// Provider for Printer service.
final printerServiceProvider = Provider<IPrinterService>((ref) {
  return const PrintingService();
});

/// Provider for PaymentRepository.
final paymentRepositoryProvider = Provider<IPaymentRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqlitePaymentRepository(dbHelper);
});

/// Provider for Payment application service.
final paymentServiceProvider = Provider<PaymentService>((ref) {
  final repo = ref.watch(paymentRepositoryProvider);
  return PaymentService(repo);
});

/// Provider for PurchaseRepository.
final purchaseRepositoryProvider = Provider<IPurchaseRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqlitePurchaseRepository(dbHelper);
});

/// Provider for Purchase application service.
final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final repo = ref.watch(purchaseRepositoryProvider);
  return PurchaseService(repo);
});

/// Provider for ExpenseRepository.
final expenseRepositoryProvider = Provider<IExpenseRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteExpenseRepository(dbHelper);
});

/// Provider for Expense application service.
final expenseServiceProvider = Provider<ExpenseService>((ref) {
  final repo = ref.watch(expenseRepositoryProvider);
  return ExpenseService(repo);
});

/// Provider for ReportRepository.
final reportRepositoryProvider = Provider<IReportRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteReportRepository(dbHelper);
});

/// Provider for Report application service.
final reportServiceProvider = Provider<ReportService>((ref) {
  final repo = ref.watch(reportRepositoryProvider);
  return ReportService(repo);
});

/// Provider for AccountingIntegrityService.
final accountingIntegrityServiceProvider = Provider<AccountingIntegrityService>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return AccountingIntegrityService(dbHelper);
});

/// Provider for RecurringInvoiceRepository.
final recurringInvoiceRepositoryProvider = Provider<IRecurringInvoiceRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return SqliteRecurringInvoiceRepository(dbHelper);
});

/// Provider for RecurringInvoice application service.
final recurringInvoiceServiceProvider = Provider<RecurringInvoiceService>((ref) {
  final recurringRepo = ref.watch(recurringInvoiceRepositoryProvider);
  final invoiceService = ref.watch(invoiceServiceProvider);
  final partyRepo = ref.watch(partyRepositoryProvider);
  final businessRepo = ref.watch(businessRepositoryProvider);
  final taxRateRepo = ref.watch(taxRateRepositoryProvider);
  return RecurringInvoiceService(
    recurringRepo: recurringRepo,
    invoiceService: invoiceService,
    partyRepo: partyRepo,
    businessRepo: businessRepo,
    taxRateRepo: taxRateRepo,
  );
});


