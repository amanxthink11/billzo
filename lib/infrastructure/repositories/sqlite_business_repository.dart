import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_repository.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/business/business_validator.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [IBusinessRepository].
class SqliteBusinessRepository implements IBusinessRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  SqliteBusinessRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.getInstance();

  @override
  Future<Business?> getActiveBusiness() async {
    final db = await _dbHelper.database;

    // Check for explicit active business ID in app_settings
    final settingRows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['active_business_id'],
      limit: 1,
    );

    if (settingRows.isNotEmpty) {
      final activeId = settingRows.first['value'] as String?;
      if (activeId != null && activeId.isNotEmpty) {
        final rows = await db.query(
          'businesses',
          where: 'id = ?',
          whereArgs: [activeId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          return Business.fromMap(rows.first);
        }
      }
    }

    // Fallback: Return the first configured business
    final fallbackRows = await db.query('businesses', limit: 1);
    if (fallbackRows.isNotEmpty) {
      return Business.fromMap(fallbackRows.first);
    }

    return null;
  }

  @override
  Future<Business> createBusiness(Business business, {BusinessSettings? settings}) async {
    // 1. Strict Domain Validation
    final validation = BusinessValidator.validate(
      name: business.name,
      phone: business.phone,
      stateCode: business.stateCode,
      email: business.email,
      gstin: business.gstin,
      pan: business.pan,
      pincode: business.pincode,
      bankIfsc: business.bankIfsc,
      upiId: business.upiId,
    );

    if (!validation.isValid) {
      throw ArgumentError(validation.firstError ?? 'Invalid business data');
    }

    // 2. Atomic Transaction Write
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // Insert Business Record
      await txn.insert(
        'businesses',
        business.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );

      // Insert Business Settings
      final effectiveSettings = settings ??
          BusinessSettings(
            id: _uuid.v4(),
            businessId: business.id,
            createdAt: business.createdAt,
            updatedAt: business.updatedAt,
          );

      await txn.insert(
        'business_settings',
        effectiveSettings.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Seed Standard Statutory Tax Rates for this business
      await _seedDefaultTaxRates(txn, business.id, business.createdAt);

      // Seed Standard Units for this business
      await _seedDefaultUnits(txn, business.id, business.createdAt);

      // Seed Initial Invoice Sequences
      await _seedDefaultSequences(txn, business.id, business.createdAt);

      // Update App Settings pointing to this active business
      final nowStr = DateTime.now().toUtc().toIso8601String();
      await txn.insert(
        'app_settings',
        {'key': 'active_business_id', 'value': business.id, 'updated_at': nowStr},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'app_settings',
        {'key': 'onboarding_completed', 'value': 'true', 'updated_at': nowStr},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    return business;
  }

  @override
  Future<Business> updateBusiness(Business business) async {
    final validation = BusinessValidator.validate(
      name: business.name,
      phone: business.phone,
      stateCode: business.stateCode,
      email: business.email,
      gstin: business.gstin,
      pan: business.pan,
      pincode: business.pincode,
      bankIfsc: business.bankIfsc,
      upiId: business.upiId,
    );

    if (!validation.isValid) {
      throw ArgumentError(validation.firstError ?? 'Invalid business data');
    }

    final db = await _dbHelper.database;
    final updatedMap = business.toMap();
    updatedMap['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final count = await db.update(
      'businesses',
      updatedMap,
      where: 'id = ?',
      whereArgs: [business.id],
    );

    if (count == 0) {
      throw StateError('Business with ID ${business.id} not found to update');
    }

    return business;
  }

  @override
  Future<BusinessSettings?> getBusinessSettings(String businessId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'business_settings',
      where: 'business_id = ?',
      whereArgs: [businessId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return BusinessSettings.fromMap(rows.first);
  }

  @override
  Future<BusinessSettings> updateBusinessSettings(BusinessSettings settings) async {
    final db = await _dbHelper.database;
    final updatedMap = settings.toMap();
    updatedMap['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final count = await db.update(
      'business_settings',
      updatedMap,
      where: 'id = ?',
      whereArgs: [settings.id],
    );

    if (count == 0) {
      await db.insert('business_settings', updatedMap);
    }

    return settings;
  }

  @override
  Future<bool> hasConfiguredBusiness() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM businesses');
    final count = (result.isNotEmpty && result.first.values.isNotEmpty)
        ? (result.first.values.first as int? ?? 0)
        : 0;
    return count > 0;
  }

  // --- Seed Helpers ---

  Future<void> _seedDefaultTaxRates(Transaction txn, String businessId, DateTime now) async {
    final nowStr = now.toUtc().toIso8601String();
    final defaultRates = [
      {'name': 'GST 0% (Exempt)', 'rate': 0, 'cgst': 0, 'sgst': 0, 'igst': 0},
      {'name': 'GST 5%', 'rate': 500, 'cgst': 250, 'sgst': 250, 'igst': 500},
      {'name': 'GST 12%', 'rate': 1200, 'cgst': 600, 'sgst': 600, 'igst': 1200},
      {'name': 'GST 18%', 'rate': 1800, 'cgst': 900, 'sgst': 900, 'igst': 1800},
      {'name': 'GST 28%', 'rate': 2800, 'cgst': 1400, 'sgst': 1400, 'igst': 2800},
    ];

    for (final rate in defaultRates) {
      await txn.insert('tax_rates', {
        'id': _uuid.v4(),
        'business_id': businessId,
        'name': rate['name'],
        'rate_basis_points': rate['rate'],
        'cgst_basis_points': rate['cgst'],
        'sgst_basis_points': rate['sgst'],
        'igst_basis_points': rate['igst'],
        'cess_basis_points': 0,
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
        'sync_version': 1,
        'sync_status': 'synced',
      });
    }
  }

  Future<void> _seedDefaultUnits(Transaction txn, String businessId, DateTime now) async {
    final nowStr = now.toUtc().toIso8601String();
    final defaultUnits = [
      {'code': 'PCS', 'name': 'Pieces', 'decimal': 0},
      {'code': 'BOX', 'name': 'Boxes', 'decimal': 0},
      {'code': 'KG', 'name': 'Kilograms', 'decimal': 1},
      {'code': 'LTR', 'name': 'Litres', 'decimal': 1},
      {'code': 'MTR', 'name': 'Meters', 'decimal': 1},
      {'code': 'SET', 'name': 'Sets', 'decimal': 0},
      {'code': 'NOS', 'name': 'Numbers', 'decimal': 0},
      {'code': 'HRS', 'name': 'Hours', 'decimal': 1},
      {'code': 'DAY', 'name': 'Days', 'decimal': 1},
      {'code': 'MTH', 'name': 'Months', 'decimal': 1},
      {'code': 'JOB', 'name': 'Job Work', 'decimal': 0},
      {'code': 'SRV', 'name': 'Service Unit', 'decimal': 0},
      {'code': 'OTH', 'name': 'Others', 'decimal': 1},
    ];

    for (final unit in defaultUnits) {
      await txn.insert('units', {
        'id': _uuid.v4(),
        'business_id': businessId,
        'code': unit['code'],
        'name': unit['name'],
        'allow_decimal': unit['decimal'],
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
        'sync_version': 1,
        'sync_status': 'synced',
      });
    }
  }

  Future<void> _seedDefaultSequences(Transaction txn, String businessId, DateTime now) async {
    final nowStr = now.toUtc().toIso8601String();
    final year = now.year;
    final fiscalYear = '$year-${year + 1}';

    final defaultDocs = [
      {'type': 'INVOICE', 'prefix': 'INV-$year-'},
      {'type': 'ESTIMATE', 'prefix': 'EST-$year-'},
      {'type': 'PURCHASE', 'prefix': 'PUR-$year-'},
      {'type': 'CREDIT_NOTE', 'prefix': 'CN-$year-'},
      {'type': 'DEBIT_NOTE', 'prefix': 'DN-$year-'},
    ];

    for (final doc in defaultDocs) {
      await txn.insert('invoice_sequences', {
        'id': _uuid.v4(),
        'business_id': businessId,
        'document_type': doc['type'],
        'prefix': doc['prefix'],
        'current_number': 1,
        'padding_zeros': 4,
        'fiscal_year': fiscalYear,
        'created_at': nowStr,
        'updated_at': nowStr,
      });
    }
  }
}
