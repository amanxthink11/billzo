import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/domain/party/party_repository.dart';
import 'package:billzo/domain/party/party_validator.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [IPartyRepository] backed by relational customers & suppliers tables.
class SqlitePartyRepository implements IPartyRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  SqlitePartyRepository(this._dbHelper);

  @override
  Future<Party> createParty(Party party) async {
    // 1. Strict domain validation outside widgets
    final validation = PartyValidator.validate(party);
    if (validation.hasErrors) {
      throw ArgumentError(
        'Validation failed for party: ${validation.errors.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
      );
    }

    final id = party.id.isEmpty ? _uuid.v4() : party.id;
    final now = DateTime.now().toUtc();

    final toInsert = party.copyWith(
      id: id,
      name: party.name.trim(),
      companyName: party.companyName?.trim(),
      phone: party.phone != null ? PartyValidator.sanitizePhone(party.phone!) : null,
      alternatePhone: party.alternatePhone != null ? PartyValidator.sanitizePhone(party.alternatePhone!) : null,
      currentBalancePaise: party.openingBalancePaise,
      createdAt: now,
      updatedAt: now,
    );

    // 2. Persist to customers and/or suppliers and record opening balance atomically
    await _dbHelper.transaction((txn) async {
      if (toInsert.isCustomer) {
        await txn.insert(
          'customers',
          _partyToCustomerMap(toInsert),
          conflictAlgorithm: ConflictAlgorithm.fail,
        );
      }
      if (toInsert.isSupplier) {
        await txn.insert(
          'suppliers',
          _partyToSupplierMap(toInsert),
          conflictAlgorithm: ConflictAlgorithm.fail,
        );
      }

      if (toInsert.openingBalancePaise > 0) {
        await _recordOpeningBalanceEntry(txn, toInsert);
      }
    });

    return toInsert;
  }

  @override
  Future<Party> updateParty(Party party) async {
    final validation = PartyValidator.validate(party);
    if (validation.hasErrors) {
      throw ArgumentError(
        'Validation failed for party: ${validation.errors.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
      );
    }

    final now = DateTime.now().toUtc();
    final updated = party.copyWith(
      name: party.name.trim(),
      companyName: party.companyName?.trim(),
      phone: party.phone != null ? PartyValidator.sanitizePhone(party.phone!) : null,
      alternatePhone: party.alternatePhone != null ? PartyValidator.sanitizePhone(party.alternatePhone!) : null,
      updatedAt: now,
    );

    await _dbHelper.transaction((txn) async {
      if (updated.isCustomer) {
        final custMap = _partyToCustomerMap(updated);
        final count = await txn.update(
          'customers',
          custMap,
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [updated.id],
        );
        if (count == 0) {
          // If previously only supplier, insert into customers
          await txn.insert('customers', custMap, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } else {
        // If no longer customer, soft-delete from customers
        await txn.update(
          'customers',
          {'deleted_at': now.toIso8601String(), 'is_active': 0, 'updated_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [updated.id],
        );
      }

      if (updated.isSupplier) {
        final suppMap = _partyToSupplierMap(updated);
        final count = await txn.update(
          'suppliers',
          suppMap,
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [updated.id],
        );
        if (count == 0) {
          // If previously only customer, insert into suppliers
          await txn.insert('suppliers', suppMap, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } else {
        // If no longer supplier, soft-delete from suppliers
        await txn.update(
          'suppliers',
          {'deleted_at': now.toIso8601String(), 'is_active': 0, 'updated_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [updated.id],
        );
      }
    });

    return updated;
  }

  @override
  Future<Party?> getPartyById(String id) async {
    final db = await _dbHelper.database;
    final customerResults = await db.query(
      'customers',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );

    final supplierResults = await db.query(
      'suppliers',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );

    if (customerResults.isNotEmpty && supplierResults.isNotEmpty) {
      return _customerRowToParty(customerResults.first, isAlsoSupplier: true);
    } else if (customerResults.isNotEmpty) {
      return _customerRowToParty(customerResults.first, isAlsoSupplier: false);
    } else if (supplierResults.isNotEmpty) {
      return _supplierRowToParty(supplierResults.first, isAlsoCustomer: false);
    }

    return null;
  }

  @override
  Future<List<Party>> getParties({
    required String businessId,
    PartyType? typeFilter,
    String? searchQuery,
    bool includeInactive = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final allParties = await _fetchAllMatchingParties(
      businessId: businessId,
      typeFilter: typeFilter,
      searchQuery: searchQuery,
      includeInactive: includeInactive,
    );

    allParties.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (offset >= allParties.length) return [];
    final endIndex = (offset + limit < allParties.length) ? offset + limit : allParties.length;
    return allParties.sublist(offset, endIndex);
  }

  @override
  Future<int> countParties({
    required String businessId,
    PartyType? typeFilter,
    String? searchQuery,
    bool includeInactive = false,
  }) async {
    final allParties = await _fetchAllMatchingParties(
      businessId: businessId,
      typeFilter: typeFilter,
      searchQuery: searchQuery,
      includeInactive: includeInactive,
    );
    return allParties.length;
  }

  Future<List<Party>> _fetchAllMatchingParties({
    required String businessId,
    PartyType? typeFilter,
    String? searchQuery,
    bool includeInactive = false,
  }) async {
    final db = await _dbHelper.database;
    final customerWhere = StringBuffer('business_id = ? AND deleted_at IS NULL');
    final customerArgs = <dynamic>[businessId];
    final supplierWhere = StringBuffer('business_id = ? AND deleted_at IS NULL');
    final supplierArgs = <dynamic>[businessId];

    if (!includeInactive) {
      customerWhere.write(' AND is_active = 1');
      supplierWhere.write(' AND is_active = 1');
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      customerWhere.write(' AND (name LIKE ? OR company_name LIKE ? OR phone LIKE ? OR gstin LIKE ?)');
      customerArgs.addAll([term, term, term, term]);
      supplierWhere.write(' AND (name LIKE ? OR company_name LIKE ? OR phone LIKE ? OR gstin LIKE ?)');
      supplierArgs.addAll([term, term, term, term]);
    }

    final customerRows = await db.query(
      'customers',
      where: customerWhere.toString(),
      whereArgs: customerArgs,
    );

    final supplierRows = await db.query(
      'suppliers',
      where: supplierWhere.toString(),
      whereArgs: supplierArgs,
    );

    final supplierIds = supplierRows.map((r) => r['id'] as String).toSet();
    final customerIds = customerRows.map((r) => r['id'] as String).toSet();

    final Map<String, Party> partyMap = {};

    for (final row in customerRows) {
      final id = row['id'] as String;
      final isAlsoSupplier = supplierIds.contains(id);
      final party = _customerRowToParty(row, isAlsoSupplier: isAlsoSupplier);

      if (typeFilter == null ||
          (typeFilter == PartyType.customer && party.isCustomer) ||
          (typeFilter == PartyType.supplier && party.isSupplier) ||
          (typeFilter == PartyType.both && party.partyType == PartyType.both)) {
        partyMap[id] = party;
      }
    }

    for (final row in supplierRows) {
      final id = row['id'] as String;
      if (!partyMap.containsKey(id)) {
        final isAlsoCustomer = customerIds.contains(id);
        final party = _supplierRowToParty(row, isAlsoCustomer: isAlsoCustomer);

        if (typeFilter == null ||
            (typeFilter == PartyType.customer && party.isCustomer) ||
            (typeFilter == PartyType.supplier && party.isSupplier) ||
            (typeFilter == PartyType.both && party.partyType == PartyType.both)) {
          partyMap[id] = party;
        }
      }
    }

    return partyMap.values.toList();
  }

  @override
  Future<void> setPartyActiveStatus(String id, bool isActive) async {
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await _dbHelper.transaction((txn) async {
      await txn.update(
        'customers',
        {'is_active': isActive ? 1 : 0, 'updated_at': nowStr},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      await txn.update(
        'suppliers',
        {'is_active': isActive ? 1 : 0, 'updated_at': nowStr},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> softDeleteParty(String id) async {
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await _dbHelper.transaction((txn) async {
      await txn.update(
        'customers',
        {'deleted_at': nowStr, 'is_active': 0, 'updated_at': nowStr},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'suppliers',
        {'deleted_at': nowStr, 'is_active': 0, 'updated_at': nowStr},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<bool> isPhoneTaken(String businessId, String phone, {String? excludePartyId}) async {
    final db = await _dbHelper.database;
    final sanitized = PartyValidator.sanitizePhone(phone);

    final custWhere = StringBuffer('business_id = ? AND phone = ? AND deleted_at IS NULL');
    final custArgs = <dynamic>[businessId, sanitized];
    final suppWhere = StringBuffer('business_id = ? AND phone = ? AND deleted_at IS NULL');
    final suppArgs = <dynamic>[businessId, sanitized];

    if (excludePartyId != null) {
      custWhere.write(' AND id != ?');
      custArgs.add(excludePartyId);
      suppWhere.write(' AND id != ?');
      suppArgs.add(excludePartyId);
    }

    final custCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM customers WHERE ${custWhere.toString()}',
      custArgs,
    )).first['count'] as int? ?? 0;

    final suppCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM suppliers WHERE ${suppWhere.toString()}',
      suppArgs,
    )).first['count'] as int? ?? 0;

    return (custCount + suppCount) > 0;
  }

  @override
  Future<bool> isGstinTaken(String businessId, String gstin, {String? excludePartyId}) async {
    final db = await _dbHelper.database;
    final upperGstin = gstin.trim().toUpperCase();

    final custWhere = StringBuffer('business_id = ? AND UPPER(gstin) = ? AND deleted_at IS NULL');
    final custArgs = <dynamic>[businessId, upperGstin];
    final suppWhere = StringBuffer('business_id = ? AND UPPER(gstin) = ? AND deleted_at IS NULL');
    final suppArgs = <dynamic>[businessId, upperGstin];

    if (excludePartyId != null) {
      custWhere.write(' AND id != ?');
      custArgs.add(excludePartyId);
      suppWhere.write(' AND id != ?');
      suppArgs.add(excludePartyId);
    }

    final custCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM customers WHERE ${custWhere.toString()}',
      custArgs,
    )).first['count'] as int? ?? 0;

    final suppCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM suppliers WHERE ${suppWhere.toString()}',
      suppArgs,
    )).first['count'] as int? ?? 0;

    return (custCount + suppCount) > 0;
  }

  @override
  Future<void> recordOpeningBalanceJournalEntry({required Party party}) async {
    if (party.openingBalancePaise <= 0) return;
    await _dbHelper.transaction((txn) async {
      await _recordOpeningBalanceEntry(txn, party);
    });
  }

  /// Internal transaction helper to record balanced double-entry journal postings in ledger_entries.
  Future<void> _recordOpeningBalanceEntry(Transaction txn, Party party) async {
    // Standard accounts per ACCOUNTING_RULES.md:
    // 1100: Accounts Receivable (Debtors), Asset
    // 2100: Accounts Payable (Creditors), Liability
    // 3000: Owner's Capital / Equity, Equity
    final receivableAccountId = await _ensureAccount(
      txn,
      businessId: party.businessId,
      code: '1100',
      name: 'Accounts Receivable (Debtors)',
      type: 'ASSET',
    );

    final payableAccountId = await _ensureAccount(
      txn,
      businessId: party.businessId,
      code: '2100',
      name: 'Accounts Payable (Creditors)',
      type: 'LIABILITY',
    );

    final equityAccountId = await _ensureAccount(
      txn,
      businessId: party.businessId,
      code: '3000',
      name: "Owner's Capital / Equity",
      type: 'EQUITY',
    );

    final now = DateTime.now().toUtc().toIso8601String();

    if (party.openingBalanceType == OpeningBalanceType.toReceive) {
      // Customer owes business: Debit Accounts Receivable (1100), Credit Equity (3000)
      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': party.businessId,
        'account_id': receivableAccountId,
        'transaction_id': party.id,
        'transaction_type': 'OPENING_BALANCE',
        'entry_date': now,
        'debit_paise': party.openingBalancePaise,
        'credit_paise': 0,
        'description': 'Opening balance receivable from ${party.name}',
        'created_at': now,
      });

      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': party.businessId,
        'account_id': equityAccountId,
        'transaction_id': party.id,
        'transaction_type': 'OPENING_BALANCE',
        'entry_date': now,
        'debit_paise': 0,
        'credit_paise': party.openingBalancePaise,
        'description': 'Opening equity offset for ${party.name}',
        'created_at': now,
      });
    } else {
      // Business owes supplier: Debit Equity (3000), Credit Accounts Payable (2100)
      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': party.businessId,
        'account_id': equityAccountId,
        'transaction_id': party.id,
        'transaction_type': 'OPENING_BALANCE',
        'entry_date': now,
        'debit_paise': party.openingBalancePaise,
        'credit_paise': 0,
        'description': 'Opening equity offset for ${party.name}',
        'created_at': now,
      });

      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': party.businessId,
        'account_id': payableAccountId,
        'transaction_id': party.id,
        'transaction_type': 'OPENING_BALANCE',
        'entry_date': now,
        'debit_paise': 0,
        'credit_paise': party.openingBalancePaise,
        'description': 'Opening balance payable to ${party.name}',
        'created_at': now,
      });
    }
  }

  /// Ensures an account exists in the Chart of Accounts, creating it if needed.
  Future<String> _ensureAccount(
    Transaction txn, {
    required String businessId,
    required String code,
    required String name,
    required String type,
  }) async {
    final existing = await txn.query(
      'ledger_accounts',
      columns: ['id'],
      where: 'business_id = ? AND code = ?',
      whereArgs: [businessId, code],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return existing.first['id'] as String;
    }

    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.insert('ledger_accounts', {
      'id': id,
      'business_id': businessId,
      'code': code,
      'name': name,
      'account_type': type,
      'is_system_account': 1,
      'created_at': now,
      'updated_at': now,
    });

    return id;
  }

  Map<String, dynamic> _partyToCustomerMap(Party party) {
    return {
      'id': party.id,
      'business_id': party.businessId,
      'name': party.name,
      'company_name': party.companyName,
      'phone': party.phone,
      'email': party.email,
      'gstin': party.gstin,
      'pan': party.pan,
      'billing_address_line1': party.billingAddressLine1,
      'billing_address_line2': party.billingAddressLine2,
      'billing_city': party.billingCity,
      'billing_state_code': party.billingStateCode ?? '27',
      'billing_state_name': party.billingStateName ?? 'Maharashtra',
      'billing_pincode': party.billingPincode,
      'shipping_address_line1': party.shippingAddressLine1,
      'shipping_address_line2': party.shippingAddressLine2,
      'shipping_city': party.shippingCity,
      'shipping_state_code': party.shippingStateCode,
      'shipping_state_name': party.shippingStateName,
      'shipping_pincode': party.shippingPincode,
      'credit_period_days': party.creditPeriodDays,
      'credit_limit_paise': party.creditLimitPaise,
      'opening_balance_paise': party.openingBalancePaise,
      'opening_balance_type': party.openingBalanceType == OpeningBalanceType.toReceive ? 'RECEIVABLE' : 'PAYABLE',
      'current_balance_paise': party.currentBalancePaise,
      'is_active': party.isActive ? 1 : 0,
      'created_at': party.createdAt.toIso8601String(),
      'updated_at': party.updatedAt.toIso8601String(),
      'deleted_at': party.isDeleted ? party.updatedAt.toIso8601String() : null,
      'sync_version': 1,
      'sync_status': 'synced',
    };
  }

  Map<String, dynamic> _partyToSupplierMap(Party party) {
    return {
      'id': party.id,
      'business_id': party.businessId,
      'name': party.name,
      'company_name': party.companyName,
      'phone': party.phone,
      'email': party.email,
      'gstin': party.gstin,
      'pan': party.pan,
      'address_line1': party.billingAddressLine1,
      'address_line2': party.billingAddressLine2,
      'city': party.billingCity,
      'state_code': party.billingStateCode ?? '27',
      'state_name': party.billingStateName ?? 'Maharashtra',
      'pincode': party.billingPincode,
      'credit_period_days': party.creditPeriodDays,
      'opening_balance_paise': party.openingBalancePaise,
      'opening_balance_type': party.openingBalanceType == OpeningBalanceType.toPay ? 'PAYABLE' : 'RECEIVABLE',
      'current_balance_paise': party.currentBalancePaise,
      'is_active': party.isActive ? 1 : 0,
      'created_at': party.createdAt.toIso8601String(),
      'updated_at': party.updatedAt.toIso8601String(),
      'deleted_at': party.isDeleted ? party.updatedAt.toIso8601String() : null,
      'sync_version': 1,
      'sync_status': 'synced',
    };
  }

  Party _customerRowToParty(Map<String, dynamic> row, {bool isAlsoSupplier = false}) {
    return Party(
      id: row['id'] as String,
      businessId: row['business_id'] as String,
      name: row['name'] as String,
      companyName: row['company_name'] as String?,
      partyType: isAlsoSupplier ? PartyType.both : PartyType.customer,
      contactPerson: null,
      phone: row['phone'] as String?,
      alternatePhone: null,
      email: row['email'] as String?,
      gstin: row['gstin'] as String?,
      pan: row['pan'] as String?,
      billingAddressLine1: row['billing_address_line1'] as String?,
      billingAddressLine2: row['billing_address_line2'] as String?,
      billingCity: row['billing_city'] as String?,
      billingStateCode: row['billing_state_code'] as String?,
      billingStateName: row['billing_state_name'] as String?,
      billingPincode: row['billing_pincode'] as String?,
      shippingAddressLine1: row['shipping_address_line1'] as String?,
      shippingAddressLine2: row['shipping_address_line2'] as String?,
      shippingCity: row['shipping_city'] as String?,
      shippingStateCode: row['shipping_state_code'] as String?,
      shippingStateName: row['shipping_state_name'] as String?,
      shippingPincode: row['shipping_pincode'] as String?,
      creditLimitPaise: row['credit_limit_paise'] as int? ?? 0,
      creditPeriodDays: row['credit_period_days'] as int? ?? 0,
      openingBalancePaise: row['opening_balance_paise'] as int? ?? 0,
      openingBalanceType: (row['opening_balance_type'] as String? ?? 'RECEIVABLE').toUpperCase() == 'PAYABLE'
          ? OpeningBalanceType.toPay
          : OpeningBalanceType.toReceive,
      currentBalancePaise: row['current_balance_paise'] as int? ?? 0,
      notes: null,
      isActive: (row['is_active'] as int? ?? 1) == 1,
      isDeleted: row['deleted_at'] != null,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Party _supplierRowToParty(Map<String, dynamic> row, {bool isAlsoCustomer = false}) {
    return Party(
      id: row['id'] as String,
      businessId: row['business_id'] as String,
      name: row['name'] as String,
      companyName: row['company_name'] as String?,
      partyType: isAlsoCustomer ? PartyType.both : PartyType.supplier,
      contactPerson: null,
      phone: row['phone'] as String?,
      alternatePhone: null,
      email: row['email'] as String?,
      gstin: row['gstin'] as String?,
      pan: row['pan'] as String?,
      billingAddressLine1: row['address_line1'] as String?,
      billingAddressLine2: row['address_line2'] as String?,
      billingCity: row['city'] as String?,
      billingStateCode: row['state_code'] as String?,
      billingStateName: row['state_name'] as String?,
      billingPincode: row['pincode'] as String?,
      shippingAddressLine1: null,
      shippingAddressLine2: null,
      shippingCity: null,
      shippingStateCode: null,
      shippingStateName: null,
      shippingPincode: null,
      creditLimitPaise: 0,
      creditPeriodDays: row['credit_period_days'] as int? ?? 0,
      openingBalancePaise: row['opening_balance_paise'] as int? ?? 0,
      openingBalanceType: (row['opening_balance_type'] as String? ?? 'PAYABLE').toUpperCase() == 'RECEIVABLE'
          ? OpeningBalanceType.toReceive
          : OpeningBalanceType.toPay,
      currentBalancePaise: row['current_balance_paise'] as int? ?? 0,
      notes: null,
      isActive: (row['is_active'] as int? ?? 1) == 1,
      isDeleted: row['deleted_at'] != null,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
