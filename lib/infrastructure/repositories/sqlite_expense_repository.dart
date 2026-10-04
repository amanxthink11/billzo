import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/domain/expense/expense.dart';
import 'package:billzo/domain/expense/expense_category.dart';
import 'package:billzo/domain/expense/expense_repository.dart';
import 'package:billzo/domain/expense/expense_status.dart';
import 'package:billzo/domain/expense/expense_validator.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

class SqliteExpenseRepository implements IExpenseRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid;
  final Future<void> Function(Transaction txn)? onBeforePostCommitForTesting;
  final Future<void> Function(Transaction txn)? onBeforeCancelCommitForTesting;

  SqliteExpenseRepository(
    this._dbHelper, {
    Uuid? uuid,
    this.onBeforePostCommitForTesting,
    this.onBeforeCancelCommitForTesting,
  }) : _uuid = uuid ?? const Uuid();

  @override
  Future<Expense> createDraft(Expense expense) async {
    final validation = ExpenseValidator.validate(expense, isPosting: false);
    if (!validation.isValid) {
      throw ArgumentError(validation.errorMessage);
    }

    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final draft = expense.copyWith(
      status: ExpenseStatus.draft,
      createdAt: now,
      updatedAt: now,
    );

    // Resolve category ledger account to satisfy expenses.account_id NOT NULL constraint
    String accountCode = '5100';
    String categoryName = expense.categoryName ?? 'Operating Expense';
    if (expense.categoryId.isNotEmpty) {
      final catRows = await db.query(
        'expense_categories',
        where: 'id = ?',
        whereArgs: [expense.categoryId],
        limit: 1,
      );
      if (catRows.isNotEmpty) {
        accountCode = catRows.first['account_code'] as String? ?? '5100';
        categoryName = catRows.first['name'] as String? ?? categoryName;
      }
    }

    final ledgerAccountId = await _ensureAccount(
      db,
      businessId: expense.businessId,
      code: accountCode,
      name: '$categoryName Expense',
      type: 'EXPENSE',
    );

    final map = draft.toMap();
    map['account_id'] = ledgerAccountId;

    await db.insert('expenses', map);
    return draft.copyWith(categoryName: categoryName);
  }

  @override
  Future<Expense> updateDraft(Expense expense) async {
    final validation = ExpenseValidator.validate(expense, isPosting: false);
    if (!validation.isValid) {
      throw ArgumentError(validation.errorMessage);
    }

    final db = await _dbHelper.database;
    final existing = await getExpenseById(expense.id);
    if (existing == null) {
      throw StateError('Expense not found: ${expense.id}');
    }
    if (!existing.isDraft) {
      throw StateError('Only draft expenses can be edited. Current status: ${existing.status.displayName}');
    }

    final updated = expense.copyWith(
      status: ExpenseStatus.draft,
      updatedAt: DateTime.now().toUtc(),
    );

    final map = updated.toMap();
    if (expense.categoryId.isNotEmpty) {
      final catRows = await db.query(
        'expense_categories',
        where: 'id = ?',
        whereArgs: [expense.categoryId],
        limit: 1,
      );
      if (catRows.isNotEmpty) {
        final accountCode = catRows.first['account_code'] as String? ?? '5100';
        final categoryName = catRows.first['name'] as String? ?? 'Operating Expense';
        final ledgerAccountId = await _ensureAccount(
          db,
          businessId: expense.businessId,
          code: accountCode,
          name: '$categoryName Expense',
          type: 'EXPENSE',
        );
        map['account_id'] = ledgerAccountId;
      }
    }

    await db.update(
      'expenses',
      map,
      where: 'id = ?',
      whereArgs: [expense.id],
    );
    return updated;
  }

  @override
  Future<void> deleteDraft(String expenseId) async {
    final db = await _dbHelper.database;
    final existing = await getExpenseById(expenseId);
    if (existing == null) {
      throw StateError('Expense not found: $expenseId');
    }
    if (!existing.isDraft) {
      throw StateError('Only draft expenses can be deleted. Current status: ${existing.status.displayName}');
    }

    await db.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
  }

  @override
  Future<Expense> postExpense(String expenseId, {String? paymentAccountId}) async {
    final db = await _dbHelper.database;

    return await db.transaction((txn) async {
      // 1. Fetch expense with row lock
      final rows = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [expenseId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Expense not found: $expenseId');
      }

      var currentExpense = Expense.fromMap(rows.first);
      if (!currentExpense.isDraft) {
        throw StateError('Cannot post expense with status: ${currentExpense.status.displayName}');
      }

      // 2. Resolve Cash/Bank account
      final targetAccountId = paymentAccountId ?? currentExpense.paymentAccountId;
      if (targetAccountId == null || targetAccountId.trim().isEmpty) {
        throw ArgumentError('A valid Cash or Bank account must be selected to post this expense');
      }

      final accountRows = await txn.query(
        'cash_bank_accounts',
        where: 'id = ? AND is_active = 1',
        whereArgs: [targetAccountId],
        limit: 1,
      );
      if (accountRows.isEmpty) {
        throw StateError('Payment account not found or is inactive: $targetAccountId');
      }
      final cashBankAccount = CashBankAccount.fromMap(accountRows.first);

      // 3. Resolve Category
      final catRows = await txn.query(
        'expense_categories',
        where: 'id = ?',
        whereArgs: [currentExpense.categoryId],
        limit: 1,
      );
      final categoryName = catRows.isNotEmpty ? (catRows.first['name'] as String) : 'General Expense';
      final accountCode = catRows.isNotEmpty ? (catRows.first['account_code'] as String? ?? '5100') : '5100';

      // 4. Validate for posting
      final expenseToPost = currentExpense.copyWith(
        paymentAccountId: targetAccountId,
        paymentAccountName: cashBankAccount.name,
        categoryName: categoryName,
      );
      final validation = ExpenseValidator.validate(expenseToPost, isPosting: true);
      if (!validation.isValid) {
        throw ArgumentError(validation.errorMessage);
      }

      // 5. Allocate sequence number atomically
      final expenseNumber = await _allocateExpenseNumber(
        txn,
        businessId: expenseToPost.businessId,
        date: expenseToPost.expenseDate,
      );

      final nowUtc = DateTime.now().toUtc();
      final nowStr = nowUtc.toIso8601String();
      final dateStr = expenseToPost.expenseDate.toIso8601String();

      // 6. Post double-entry records into ledger_entries
      // 6a. Ensure Expense Ledger Account exists
      final expenseLedgerAccountId = await _ensureAccount(
        txn,
        businessId: expenseToPost.businessId,
        code: accountCode,
        name: '$categoryName Expense',
        type: 'EXPENSE',
      );

      // DEBIT: Expense Account for taxable value
      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': expenseToPost.businessId,
        'account_id': expenseLedgerAccountId,
        'transaction_id': expenseToPost.id,
        'transaction_type': 'EXPENSE',
        'entry_date': dateStr,
        'debit_paise': expenseToPost.taxableAmountPaise,
        'credit_paise': 0,
        'description': 'Taxable expense $expenseNumber to ${expenseToPost.payee}',
        'created_at': nowStr,
      });

      // DEBIT: Input GST (if tax > 0)
      if (expenseToPost.igstPaise > 0) {
        final igstAccountId = await _ensureAccount(
          txn,
          businessId: expenseToPost.businessId,
          code: '2330',
          name: 'Input IGST Credit',
          type: 'ASSET',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': expenseToPost.businessId,
          'account_id': igstAccountId,
          'transaction_id': expenseToPost.id,
          'transaction_type': 'EXPENSE',
          'entry_date': dateStr,
          'debit_paise': expenseToPost.igstPaise,
          'credit_paise': 0,
          'description': 'Input IGST Credit on $expenseNumber',
          'created_at': nowStr,
        });
      }

      if (expenseToPost.cgstPaise > 0) {
        final cgstAccountId = await _ensureAccount(
          txn,
          businessId: expenseToPost.businessId,
          code: '2310',
          name: 'Input CGST Credit',
          type: 'ASSET',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': expenseToPost.businessId,
          'account_id': cgstAccountId,
          'transaction_id': expenseToPost.id,
          'transaction_type': 'EXPENSE',
          'entry_date': dateStr,
          'debit_paise': expenseToPost.cgstPaise,
          'credit_paise': 0,
          'description': 'Input CGST Credit on $expenseNumber',
          'created_at': nowStr,
        });
      }

      if (expenseToPost.sgstPaise > 0) {
        final sgstAccountId = await _ensureAccount(
          txn,
          businessId: expenseToPost.businessId,
          code: '2320',
          name: 'Input SGST Credit',
          type: 'ASSET',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': expenseToPost.businessId,
          'account_id': sgstAccountId,
          'transaction_id': expenseToPost.id,
          'transaction_type': 'EXPENSE',
          'entry_date': dateStr,
          'debit_paise': expenseToPost.sgstPaise,
          'credit_paise': 0,
          'description': 'Input SGST Credit on $expenseNumber',
          'created_at': nowStr,
        });
      }

      // CREDIT: Cash (1010) or Bank (1020) for Total Expense Amount
      final isCashAccount = cashBankAccount.accountType == CashBankAccountType.cash;
      final settlementCode = isCashAccount ? '1010' : '1020';
      final settlementName = isCashAccount ? 'Cash on Hand' : 'Bank Account';

      final settlementLedgerAccountId = await _ensureAccount(
        txn,
        businessId: expenseToPost.businessId,
        code: settlementCode,
        name: settlementName,
        type: 'ASSET',
      );

      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': expenseToPost.businessId,
        'account_id': settlementLedgerAccountId,
        'transaction_id': expenseToPost.id,
        'transaction_type': 'EXPENSE',
        'entry_date': dateStr,
        'debit_paise': 0,
        'credit_paise': expenseToPost.totalAmountPaise,
        'description': 'Payment for expense $expenseNumber to ${expenseToPost.payee}',
        'created_at': nowStr,
      });

      // 7. Update cash_bank_accounts current_balance (Outflow)
      final newCurrentBalance = cashBankAccount.currentBalancePaise - expenseToPost.totalAmountPaise;
      await txn.update(
        'cash_bank_accounts',
        {
          'current_balance_paise': newCurrentBalance,
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [cashBankAccount.id],
      );

      // 8. Update expense record in database
      final postedExpense = expenseToPost.copyWith(
        expenseNumber: expenseNumber,
        status: ExpenseStatus.posted,
        postedAt: nowUtc,
        updatedAt: nowUtc,
      );

      final postedMap = postedExpense.toMap();
      postedMap['account_id'] = expenseLedgerAccountId;

      await txn.update(
        'expenses',
        postedMap,
        where: 'id = ?',
        whereArgs: [postedExpense.id],
      );

      // 9. Write audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': expenseToPost.businessId,
        'entity_name': 'EXPENSE',
        'entity_id': expenseToPost.id,
        'action': 'POST',
        'user_identifier': 'Local Merchant',
        'details_json': 'Posted expense $expenseNumber of ₹${(expenseToPost.totalAmountPaise / 100).toStringAsFixed(2)} to ${expenseToPost.payee}',
        'timestamp': nowStr,
      });

      if (onBeforePostCommitForTesting != null) {
        await onBeforePostCommitForTesting!(txn);
      }

      return postedExpense;
    });
  }

  @override
  Future<Expense> cancelExpense(String expenseId, {required String reason}) async {
    final db = await _dbHelper.database;

    return await db.transaction((txn) async {
      // 1. Fetch expense with row lock
      final rows = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [expenseId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Expense not found: $expenseId');
      }

      final expense = Expense.fromMap(rows.first);
      final validation = ExpenseValidator.validateCancellation(
        expense: expense,
        reason: reason,
      );
      if (!validation.isValid) {
        throw ArgumentError(validation.errorMessage);
      }

      // 2. Fetch original payment account
      final accountId = expense.paymentAccountId;
      if (accountId == null) {
        throw StateError('Expense does not have an associated payment account: $expenseId');
      }

      final accountRows = await txn.query(
        'cash_bank_accounts',
        where: 'id = ?',
        whereArgs: [accountId],
        limit: 1,
      );
      if (accountRows.isEmpty) {
        throw StateError('Associated payment account not found: $accountId');
      }
      final cashBankAccount = CashBankAccount.fromMap(accountRows.first);

      // 3. Resolve Category
      final catRows = await txn.query(
        'expense_categories',
        where: 'id = ?',
        whereArgs: [expense.categoryId],
        limit: 1,
      );
      final categoryName = catRows.isNotEmpty ? (catRows.first['name'] as String) : 'General Expense';
      final accountCode = catRows.isNotEmpty ? (catRows.first['account_code'] as String? ?? '5100') : '5100';

      final nowUtc = DateTime.now().toUtc();
      final nowStr = nowUtc.toIso8601String();
      final dateStr = expense.expenseDate.toIso8601String();

      // 4. Post Reversing Accounting Entries in ledger_entries
      final isCashAccount = cashBankAccount.accountType == CashBankAccountType.cash;
      final settlementCode = isCashAccount ? '1010' : '1020';
      final settlementName = isCashAccount ? 'Cash on Hand' : 'Bank Account';

      final settlementLedgerAccountId = await _ensureAccount(
        txn,
        businessId: expense.businessId,
        code: settlementCode,
        name: settlementName,
        type: 'ASSET',
      );

      // DEBIT: Cash/Bank Account (Reversal restoring funds)
      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': expense.businessId,
        'account_id': settlementLedgerAccountId,
        'transaction_id': expense.id,
        'transaction_type': 'EXPENSE_CANCELLATION',
        'entry_date': dateStr,
        'debit_paise': expense.totalAmountPaise,
        'credit_paise': 0,
        'description': 'Reversal: Restoring funds for cancelled expense ${expense.expenseNumber}',
        'created_at': nowStr,
      });

      // CREDIT: Expense Account (Reversal)
      final expenseLedgerAccountId = await _ensureAccount(
        txn,
        businessId: expense.businessId,
        code: accountCode,
        name: '$categoryName Expense',
        type: 'EXPENSE',
      );

      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': expense.businessId,
        'account_id': expenseLedgerAccountId,
        'transaction_id': expense.id,
        'transaction_type': 'EXPENSE_CANCELLATION',
        'entry_date': dateStr,
        'debit_paise': 0,
        'credit_paise': expense.taxableAmountPaise,
        'description': 'Reversal: Cancelled expense ${expense.expenseNumber} ($reason)',
        'created_at': nowStr,
      });

      // CREDIT: Input GST Reversals
      if (expense.igstPaise > 0) {
        final igstAccountId = await _ensureAccount(
          txn,
          businessId: expense.businessId,
          code: '2330',
          name: 'Input IGST Credit',
          type: 'ASSET',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': expense.businessId,
          'account_id': igstAccountId,
          'transaction_id': expense.id,
          'transaction_type': 'EXPENSE_CANCELLATION',
          'entry_date': dateStr,
          'debit_paise': 0,
          'credit_paise': expense.igstPaise,
          'description': 'Reversal: Cancelled Input IGST on ${expense.expenseNumber}',
          'created_at': nowStr,
        });
      }

      if (expense.cgstPaise > 0) {
        final cgstAccountId = await _ensureAccount(
          txn,
          businessId: expense.businessId,
          code: '2310',
          name: 'Input CGST Credit',
          type: 'ASSET',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': expense.businessId,
          'account_id': cgstAccountId,
          'transaction_id': expense.id,
          'transaction_type': 'EXPENSE_CANCELLATION',
          'entry_date': dateStr,
          'debit_paise': 0,
          'credit_paise': expense.cgstPaise,
          'description': 'Reversal: Cancelled Input CGST on ${expense.expenseNumber}',
          'created_at': nowStr,
        });
      }

      if (expense.sgstPaise > 0) {
        final sgstAccountId = await _ensureAccount(
          txn,
          businessId: expense.businessId,
          code: '2320',
          name: 'Input SGST Credit',
          type: 'ASSET',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': expense.businessId,
          'account_id': sgstAccountId,
          'transaction_id': expense.id,
          'transaction_type': 'EXPENSE_CANCELLATION',
          'entry_date': dateStr,
          'debit_paise': 0,
          'credit_paise': expense.sgstPaise,
          'description': 'Reversal: Cancelled Input SGST on ${expense.expenseNumber}',
          'created_at': nowStr,
        });
      }

      // 5. Restore cash_bank_accounts current_balance
      final restoredBalance = cashBankAccount.currentBalancePaise + expense.totalAmountPaise;
      await txn.update(
        'cash_bank_accounts',
        {
          'current_balance_paise': restoredBalance,
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [cashBankAccount.id],
      );

      // 6. Update expense record to CANCELLED
      final cancelledExpense = expense.copyWith(
        status: ExpenseStatus.cancelled,
        cancelledAt: nowUtc,
        cancellationReason: reason,
        updatedAt: nowUtc,
      );

      await txn.update(
        'expenses',
        cancelledExpense.toMap(),
        where: 'id = ?',
        whereArgs: [expense.id],
      );

      // 7. Write audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': expense.businessId,
        'entity_name': 'EXPENSE',
        'entity_id': expense.id,
        'action': 'CANCEL',
        'user_identifier': 'Local Merchant',
        'details_json': 'Cancelled expense ${expense.expenseNumber}. Reason: $reason',
        'timestamp': nowStr,
      });

      if (onBeforeCancelCommitForTesting != null) {
        await onBeforeCancelCommitForTesting!(txn);
      }

      return cancelledExpense;
    });
  }

  @override
  Future<Expense?> getExpenseById(String expenseId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT e.*,
             ec.name as category_name,
             ca.name as payment_account_name
      FROM expenses e
      LEFT JOIN expense_categories ec ON e.category_id = ec.id
      LEFT JOIN cash_bank_accounts ca ON e.payment_account_id = ca.id
      WHERE e.id = ? AND e.deleted_at IS NULL
      LIMIT 1
    ''', [expenseId]);

    if (rows.isEmpty) return null;
    return Expense.fromMap(rows.first);
  }

  @override
  Future<List<Expense>> getExpenses({
    required String businessId,
    String? categoryId,
    ExpenseStatus? status,
    PaymentMethod? paymentMethod,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    final whereClauses = <String>['e.business_id = ?', 'e.deleted_at IS NULL'];
    final whereArgs = <dynamic>[businessId];

    if (categoryId != null && categoryId.isNotEmpty) {
      whereClauses.add('e.category_id = ?');
      whereArgs.add(categoryId);
    }

    if (status != null) {
      whereClauses.add('e.status = ?');
      whereArgs.add(status.dbValue);
    }

    if (paymentMethod != null) {
      whereClauses.add('e.payment_method = ?');
      whereArgs.add(paymentMethod.dbValue);
    }

    if (startDate != null) {
      whereClauses.add('e.expense_date >= ?');
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClauses.add('e.expense_date <= ?');
      whereArgs.add(endDate.toIso8601String());
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      whereClauses.add('(e.payee LIKE ? OR e.description LIKE ? OR e.expense_number LIKE ?)');
      whereArgs.addAll([term, term, term]);
    }

    final sql = '''
      SELECT e.*,
             ec.name as category_name,
             ca.name as payment_account_name
      FROM expenses e
      LEFT JOIN expense_categories ec ON e.category_id = ec.id
      LEFT JOIN cash_bank_accounts ca ON e.payment_account_id = ca.id
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY e.expense_date DESC, e.created_at DESC
      LIMIT ? OFFSET ?
    ''';

    final args = [...whereArgs, limit, offset];
    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  @override
  Future<int> getExpensesCount({
    required String businessId,
    String? categoryId,
    ExpenseStatus? status,
    PaymentMethod? paymentMethod,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) async {
    final db = await _dbHelper.database;
    final whereClauses = <String>['business_id = ?', 'deleted_at IS NULL'];
    final whereArgs = <dynamic>[businessId];

    if (categoryId != null && categoryId.isNotEmpty) {
      whereClauses.add('category_id = ?');
      whereArgs.add(categoryId);
    }

    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status.dbValue);
    }

    if (paymentMethod != null) {
      whereClauses.add('payment_method = ?');
      whereArgs.add(paymentMethod.dbValue);
    }

    if (startDate != null) {
      whereClauses.add('expense_date >= ?');
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClauses.add('expense_date <= ?');
      whereArgs.add(endDate.toIso8601String());
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      whereClauses.add('(payee LIKE ? OR description LIKE ? OR expense_number LIKE ?)');
      whereArgs.addAll([term, term, term]);
    }

    final sql = '''
      SELECT COUNT(*) as cnt
      FROM expenses
      WHERE ${whereClauses.join(' AND ')}
    ''';

    final rows = await db.rawQuery(sql, whereArgs);
    if (rows.isEmpty) return 0;
    return (rows.first['cnt'] as num? ?? 0).toInt();
  }

  @override
  Future<ExpenseSummary> getExpenseSummary(
    String businessId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _dbHelper.database;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toIso8601String();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999).toIso8601String();

    final whereClauses = <String>["e.business_id = ?", "e.status = 'POSTED'", "e.deleted_at IS NULL"];
    final whereArgs = <dynamic>[businessId];

    if (startDate != null) {
      whereClauses.add("e.expense_date >= ?");
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClauses.add("e.expense_date <= ?");
      whereArgs.add(endDate.toIso8601String());
    }

    final summarySql = '''
      SELECT 
        COUNT(*) as total_count,
        COALESCE(SUM(e.total_amount_paise), 0) as total_amount,
        COALESCE(SUM(e.taxable_amount_paise), 0) as total_taxable,
        COALESCE(SUM(e.total_gst_paise), 0) as total_gst,
        COALESCE(SUM(CASE WHEN e.payment_method = 'CASH' THEN e.total_amount_paise ELSE 0 END), 0) as cash_expenses,
        COALESCE(SUM(CASE WHEN e.payment_method != 'CASH' THEN e.total_amount_paise ELSE 0 END), 0) as bank_expenses
      FROM expenses e
      WHERE ${whereClauses.join(' AND ')}
    ''';

    final summaryRows = await db.rawQuery(summarySql, whereArgs);
    final row = summaryRows.isNotEmpty ? summaryRows.first : <String, dynamic>{};

    // Calculate today's and this month's posted expenses
    final todayRows = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount_paise), 0) as today_total
      FROM expenses
      WHERE business_id = ? AND status = 'POSTED' AND deleted_at IS NULL
        AND expense_date >= ? AND expense_date <= ?
    ''', [businessId, todayStart, todayEnd]);

    final monthRows = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount_paise), 0) as month_total
      FROM expenses
      WHERE business_id = ? AND status = 'POSTED' AND deleted_at IS NULL
        AND expense_date >= ? AND expense_date <= ?
    ''', [businessId, monthStart, monthEnd]);

    return ExpenseSummary(
      totalExpensesCount: (row['total_count'] as num? ?? 0).toInt(),
      totalAmountPaise: (row['total_amount'] as num? ?? 0).toInt(),
      totalTaxablePaise: (row['total_taxable'] as num? ?? 0).toInt(),
      totalGstPaise: (row['total_gst'] as num? ?? 0).toInt(),
      cashExpensesPaise: (row['cash_expenses'] as num? ?? 0).toInt(),
      bankExpensesPaise: (row['bank_expenses'] as num? ?? 0).toInt(),
      todayExpensesPaise: todayRows.isNotEmpty ? (todayRows.first['today_total'] as num? ?? 0).toInt() : 0,
      thisMonthExpensesPaise: monthRows.isNotEmpty ? (monthRows.first['month_total'] as num? ?? 0).toInt() : 0,
    );
  }

  @override
  Future<List<ExpenseCategory>> getCategories(
    String businessId, {
    bool includeInactive = false,
  }) async {
    final db = await _dbHelper.database;
    await ensurePredefinedCategories(businessId);

    final where = includeInactive
        ? 'business_id = ? AND deleted_at IS NULL'
        : 'business_id = ? AND is_active = 1 AND deleted_at IS NULL';

    final rows = await db.query(
      'expense_categories',
      where: where,
      whereArgs: [businessId],
      orderBy: 'is_predefined DESC, name ASC',
    );

    return rows.map((r) => ExpenseCategory.fromMap(r)).toList();
  }

  @override
  Future<ExpenseCategory> createCategory(ExpenseCategory category) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final toInsert = category.copyWith(
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('expense_categories', toInsert.toMap());
    return toInsert;
  }

  @override
  Future<ExpenseCategory> updateCategory(ExpenseCategory category) async {
    final db = await _dbHelper.database;
    final updated = category.copyWith(
      updatedAt: DateTime.now().toUtc(),
    );
    await db.update(
      'expense_categories',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
    return updated;
  }

  @override
  Future<void> ensurePredefinedCategories(String businessId) async {
    final db = await _dbHelper.database;

    final existing = await db.query(
      'expense_categories',
      columns: ['name'],
      where: 'business_id = ?',
      whereArgs: [businessId],
    );

    final existingNames = existing.map((r) => (r['name'] as String).toLowerCase()).toSet();
    final now = DateTime.now().toUtc();

    for (final std in ExpenseCategory.standardCategories) {
      if (!existingNames.contains(std.name.toLowerCase())) {
        final cat = ExpenseCategory(
          id: _uuid.v4(),
          businessId: businessId,
          name: std.name,
          accountCode: std.accountCode,
          description: std.description,
          isPredefined: true,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );
        await db.insert('expense_categories', cat.toMap());
      }
    }
  }

  // --- Internal Helpers ---

  Future<String> _allocateExpenseNumber(
    Transaction txn, {
    required String businessId,
    required DateTime date,
  }) async {
    final year = date.year;
    final nowStr = DateTime.now().toUtc().toIso8601String();

    final seqRows = await txn.query(
      'invoice_sequences',
      where: 'business_id = ? AND document_type = ? AND fiscal_year = ?',
      whereArgs: [businessId, 'EXPENSE', '$year'],
      limit: 1,
    );

    int nextNum;
    String prefix = 'EXP-$year-';
    int padding = 4;

    if (seqRows.isEmpty) {
      nextNum = 1;
      await txn.insert('invoice_sequences', {
        'id': _uuid.v4(),
        'business_id': businessId,
        'document_type': 'EXPENSE',
        'prefix': prefix,
        'current_number': nextNum,
        'padding_zeros': padding,
        'fiscal_year': '$year',
        'created_at': nowStr,
        'updated_at': nowStr,
      });
    } else {
      final row = seqRows.first;
      prefix = row['prefix'] as String? ?? prefix;
      padding = (row['padding_zeros'] as num? ?? 4).toInt();
      final currentNum = (row['current_number'] as num? ?? 0).toInt();
      nextNum = currentNum + 1;

      await txn.update(
        'invoice_sequences',
        {
          'current_number': nextNum,
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    final padded = nextNum.toString().padLeft(padding, '0');
    return '$prefix$padded';
  }

  Future<String> _ensureAccount(
    DatabaseExecutor txn, {
    required String businessId,
    required String code,
    required String name,
    required String type,
  }) async {
    final rows = await txn.query(
      'ledger_accounts',
      columns: ['id'],
      where: 'business_id = ? AND code = ?',
      whereArgs: [businessId, code],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      return rows.first['id'] as String;
    }

    final id = _uuid.v4();
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await txn.insert('ledger_accounts', {
      'id': id,
      'business_id': businessId,
      'code': code,
      'name': name,
      'account_type': type,
      'is_system_account': 1,
      'created_at': nowStr,
      'updated_at': nowStr,
    });
    return id;
  }
}
