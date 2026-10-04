import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:billzo/domain/recurring/recurring_invoice.dart';
import 'package:billzo/domain/recurring/recurring_invoice_execution.dart';
import 'package:billzo/domain/recurring/recurring_invoice_item.dart';
import 'package:billzo/domain/recurring/recurring_invoice_repository.dart';
import 'package:billzo/domain/recurring/recurring_invoice_status.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [IRecurringInvoiceRepository].
class SqliteRecurringInvoiceRepository implements IRecurringInvoiceRepository {
  final DatabaseHelper _dbHelper;

  SqliteRecurringInvoiceRepository(this._dbHelper);

  @override
  Future<RecurringInvoice> createProfile(RecurringInvoice profile) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      await txn.insert(
        'recurring_invoices',
        profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );

      for (final item in profile.items) {
        await txn.insert(
          'recurring_invoice_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.fail,
        );
      }
    });

    return (await getProfileById(profile.id))!;
  }

  @override
  Future<RecurringInvoice> updateProfile(RecurringInvoice profile) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      await txn.update(
        'recurring_invoices',
        profile.toMap(),
        where: 'id = ?',
        whereArgs: [profile.id],
      );

      await txn.delete(
        'recurring_invoice_items',
        where: 'recurring_invoice_id = ?',
        whereArgs: [profile.id],
      );

      for (final item in profile.items) {
        await txn.insert(
          'recurring_invoice_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    return (await getProfileById(profile.id))!;
  }

  @override
  Future<RecurringInvoice?> getProfileById(String id) async {
    final db = await _dbHelper.database;

    final results = await db.rawQuery('''
      SELECT r.*, c.name as customer_name, c.phone as customer_phone, c.gstin as customer_gstin
      FROM recurring_invoices r
      LEFT JOIN customers c ON r.customer_id = c.id
      WHERE r.id = ?
    ''', [id]);

    if (results.isEmpty) return null;

    final items = await _getItemsForProfile(db, id);
    return RecurringInvoice.fromMap(results.first, items: items);
  }

  @override
  Future<List<RecurringInvoice>> getProfilesByBusiness(
    String businessId, {
    RecurringInvoiceStatus? statusFilter,
  }) async {
    final db = await _dbHelper.database;

    String sql = '''
      SELECT r.*, c.name as customer_name, c.phone as customer_phone, c.gstin as customer_gstin
      FROM recurring_invoices r
      LEFT JOIN customers c ON r.customer_id = c.id
      WHERE r.business_id = ?
    ''';
    final List<dynamic> args = [businessId];

    if (statusFilter != null) {
      sql += ' AND r.status = ?';
      args.add(statusFilter.toDbString());
    }

    sql += ' ORDER BY r.created_at DESC;';

    final results = await db.rawQuery(sql, args);
    final profiles = <RecurringInvoice>[];

    for (final row in results) {
      final id = row['id'] as String;
      final items = await _getItemsForProfile(db, id);
      profiles.add(RecurringInvoice.fromMap(row, items: items));
    }

    return profiles;
  }

  @override
  Future<List<RecurringInvoice>> getDueProfiles(String businessId, DateTime asOfDate) async {
    final db = await _dbHelper.database;
    final dateStr = asOfDate.toIso8601String().substring(0, 10);

    final results = await db.rawQuery('''
      SELECT r.*, c.name as customer_name, c.phone as customer_phone, c.gstin as customer_gstin
      FROM recurring_invoices r
      LEFT JOIN customers c ON r.customer_id = c.id
      WHERE r.business_id = ?
        AND r.status = 'ACTIVE'
        AND r.next_run_date <= ?
        AND (r.end_date IS NULL OR r.next_run_date <= r.end_date)
      ORDER BY r.next_run_date ASC;
    ''', [businessId, dateStr]);

    final dueProfiles = <RecurringInvoice>[];
    for (final row in results) {
      final id = row['id'] as String;
      final items = await _getItemsForProfile(db, id);
      dueProfiles.add(RecurringInvoice.fromMap(row, items: items));
    }

    return dueProfiles;
  }

  @override
  Future<void> updateScheduleDates(
    String profileId, {
    required DateTime nextRunDate,
    DateTime? lastRunDate,
    RecurringInvoiceStatus? newStatus,
  }) async {
    final db = await _dbHelper.database;

    final values = <String, dynamic>{
      'next_run_date': nextRunDate.toIso8601String().substring(0, 10),
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (lastRunDate != null) {
      values['last_run_date'] = lastRunDate.toIso8601String().substring(0, 10);
    }

    if (newStatus != null) {
      values['status'] = newStatus.toDbString();
    }

    await db.update(
      'recurring_invoices',
      values,
      where: 'id = ?',
      whereArgs: [profileId],
    );
  }

  @override
  Future<void> updateStatus(String profileId, RecurringInvoiceStatus status) async {
    final db = await _dbHelper.database;

    await db.update(
      'recurring_invoices',
      {
        'status': status.toDbString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [profileId],
    );
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'recurring_invoices',
      where: 'id = ?',
      whereArgs: [profileId],
    );
  }

  @override
  Future<RecurringInvoiceExecution> recordExecution(RecurringInvoiceExecution execution) async {
    final db = await _dbHelper.database;

    await db.insert(
      'recurring_invoice_executions',
      execution.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );

    return execution;
  }

  @override
  Future<bool> hasExecutionForDate(String recurringInvoiceId, DateTime scheduledForDate) async {
    final db = await _dbHelper.database;
    final dateStr = scheduledForDate.toIso8601String().substring(0, 10);

    final results = await db.rawQuery('''
      SELECT COUNT(*) as cnt
      FROM recurring_invoice_executions
      WHERE recurring_invoice_id = ? AND scheduled_for_date = ?
    ''', [recurringInvoiceId, dateStr]);

    return (results.first['cnt'] as int? ?? 0) > 0;
  }

  @override
  Future<List<RecurringInvoiceExecution>> getExecutions(String recurringInvoiceId) async {
    final db = await _dbHelper.database;

    final results = await db.query(
      'recurring_invoice_executions',
      where: 'recurring_invoice_id = ?',
      whereArgs: [recurringInvoiceId],
      orderBy: 'executed_at DESC',
    );

    return results.map(RecurringInvoiceExecution.fromMap).toList();
  }

  Future<List<RecurringInvoiceItem>> _getItemsForProfile(DatabaseExecutor db, String profileId) async {
    final rows = await db.rawQuery('''
      SELECT rii.*, p.name as fallback_product_name, p.hsn_sac as fallback_hsn
      FROM recurring_invoice_items rii
      LEFT JOIN products p ON rii.product_id = p.id
      WHERE rii.recurring_invoice_id = ?
      ORDER BY rii.created_at ASC
    ''', [profileId]);

    return rows.map((row) {
      final map = Map<String, dynamic>.from(row);
      if (map['product_name'] == null) {
        map['product_name'] = map['fallback_product_name'] ?? 'Item';
      }
      if (map['hsn_sac'] == null) {
        map['hsn_sac'] = map['fallback_hsn'];
      }
      return RecurringInvoiceItem.fromMap(map);
    }).toList();
  }
}
