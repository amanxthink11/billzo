import 'package:billzo/domain/catalog/tax_rate.dart';
import 'package:billzo/domain/catalog/tax_rate_repository.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [ITaxRateRepository].
class SqliteTaxRateRepository implements ITaxRateRepository {
  final DatabaseHelper _dbHelper;

  SqliteTaxRateRepository(this._dbHelper);

  @override
  Future<List<TaxRate>> getTaxRates(String businessId, {bool includeInactive = false}) async {
    final db = await _dbHelper.database;
    final where = includeInactive
        ? 'business_id = ?'
        : 'business_id = ? AND is_active = 1';

    final results = await db.query(
      'tax_rates',
      where: where,
      whereArgs: [businessId],
      orderBy: 'rate_basis_points ASC',
    );

    return results.map(TaxRate.fromMap).toList();
  }

  @override
  Future<TaxRate?> getTaxRateById(String id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'tax_rates',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return TaxRate.fromMap(results.first);
  }

  @override
  Future<TaxRate?> getDefaultTaxRate(String businessId) async {
    final db = await _dbHelper.database;
    final settingsResult = await db.query(
      'business_settings',
      columns: ['default_tax_rate_id'],
      where: 'business_id = ?',
      whereArgs: [businessId],
      limit: 1,
    );

    if (settingsResult.isNotEmpty && settingsResult.first['default_tax_rate_id'] != null) {
      final defaultId = settingsResult.first['default_tax_rate_id'] as String;
      final rate = await getTaxRateById(defaultId);
      if (rate != null) return rate;
    }

    final all = await getTaxRates(businessId);
    return all.isNotEmpty ? all.first : null;
  }
}
