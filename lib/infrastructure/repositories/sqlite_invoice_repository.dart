import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_repository.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_validator.dart';
import 'package:billzo/domain/invoice/tax_engine.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [IInvoiceRepository] with atomic finalization,
/// sequential invoice numbering, stock deduction, and double-entry accounting.
class SqliteInvoiceRepository implements IInvoiceRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  SqliteInvoiceRepository(this._dbHelper);

  @override
  Future<Invoice> saveDraft(Invoice invoice) async {
    final validation = InvoiceValidator.validate(invoice);
    if (validation.hasErrors) {
      throw ArgumentError(
        'Invoice validation failed: ${validation.errors.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
      );
    }

    final id = invoice.id.isEmpty ? _uuid.v4() : invoice.id;
    final now = DateTime.now().toUtc();
    final draftNumber = invoice.invoiceNumber.isNotEmpty && !invoice.invoiceNumber.startsWith('INV-')
        ? invoice.invoiceNumber
        : 'DRAFT-${id.substring(0, 8).toUpperCase()}';

    final toSave = invoice.copyWith(
      id: id,
      invoiceNumber: draftNumber,
      status: InvoiceStatus.draft,
      paidAmountPaise: 0,
      balanceAmountPaise: invoice.totalAmountPaise,
      createdAt: invoice.createdAt.year > 2000 ? invoice.createdAt : now,
      updatedAt: now,
    );

    await _dbHelper.transaction((txn) async {
      // 1. Insert or update invoice
      await txn.insert(
        'invoices',
        toSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Replace line items
      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
      for (final item in toSave.items) {
        final itemId = item.id.isEmpty ? _uuid.v4() : item.id;
        final itemToSave = item.copyWith(
          id: itemId,
          invoiceId: id,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('invoice_items', itemToSave.toMap());
      }

      // Record audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': toSave.businessId,
        'entity_name': 'INVOICE',
        'entity_id': id,
        'action': 'SAVE_DRAFT',
        'user_identifier': 'Local Merchant',
        'details_json': 'Draft saved: $draftNumber',
        'timestamp': now.toIso8601String(),
      });
    });

    return getInvoiceById(id).then((inv) => inv ?? toSave);
  }

  @override
  Future<Invoice> updateDraft(Invoice invoice) async {
    final existing = await getInvoiceById(invoice.id);
    if (existing == null) {
      throw StateError('Invoice ${invoice.id} not found to update.');
    }
    if (existing.status != InvoiceStatus.draft) {
      throw StateError('Cannot edit invoice ${existing.invoiceNumber} with status ${existing.status.displayName}. Only drafts can be edited.');
    }

    return saveDraft(invoice);
  }

  @override
  Future<Invoice> finalizeInvoice(Invoice invoice) async {
    final validation = InvoiceValidator.validate(invoice);
    if (validation.hasErrors) {
      throw ArgumentError(
        'Invoice validation failed: ${validation.errors.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
      );
    }

    final now = DateTime.now().toUtc();
    final id = invoice.id.isEmpty ? _uuid.v4() : invoice.id;
    String allocatedInvoiceNumber = '';

    await _dbHelper.transaction((txn) async {
      // 1. Atomically allocate statutory invoice number from invoice_sequences
      allocatedInvoiceNumber = await _allocateNextInvoiceNumber(txn, invoice.businessId, invoice.invoiceDate);

      // 2. Fetch business state for intra/inter-state tax determination
      final businessRows = await txn.query(
        'businesses',
        columns: ['state_code'],
        where: 'id = ?',
        whereArgs: [invoice.businessId],
        limit: 1,
      );
      final businessStateCode = businessRows.isNotEmpty
          ? (businessRows.first['state_code'] as String? ?? '27')
          : '27';
      final isInterState = TaxEngine.isInterState(
        businessStateCode: businessStateCode,
        placeOfSupplyStateCode: invoice.placeOfSupplyStateCode,
      );

      final finalizedInvoice = invoice.copyWith(
        id: id,
        invoiceNumber: allocatedInvoiceNumber,
        status: InvoiceStatus.finalized,
        paidAmountPaise: 0,
        balanceAmountPaise: invoice.totalAmountPaise,
        finalizedAt: now,
        createdAt: invoice.createdAt.year > 2000 ? invoice.createdAt : now,
        updatedAt: now,
      );

      // 3. Insert or update invoice record
      await txn.insert(
        'invoices',
        finalizedInvoice.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 4. Insert line items
      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
      for (final item in finalizedInvoice.items) {
        final itemId = item.id.isEmpty ? _uuid.v4() : item.id;
        final itemToSave = item.copyWith(
          id: itemId,
          invoiceId: id,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('invoice_items', itemToSave.toMap());

        // 5. Stock deduction for physical goods
        final productRows = await txn.query(
          'products',
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [item.productId],
          limit: 1,
        );

        if (productRows.isNotEmpty) {
          final prod = productRows.first;
          final trackInventory = (prod['track_inventory'] as int? ?? 1) == 1;

          if (trackInventory) {
            final currentStockScaled = (prod['current_stock'] as num? ?? 0).toInt();
            final purchasePricePaise = prod['purchase_price_paise'] as int? ?? 0;
            final newStockScaled = currentStockScaled - item.quantityScaled;

            // Update current stock in product table
            await txn.update(
              'products',
              {
                'current_stock': newStockScaled,
                'updated_at': now.toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [item.productId],
            );

            // Record append-only stock movement
            await txn.insert('stock_movements', {
              'id': _uuid.v4(),
              'business_id': invoice.businessId,
              'product_id': item.productId,
              'reference_id': id,
              'reference_type': 'SALE',
              'movement_date': invoice.invoiceDate.toIso8601String().substring(0, 10),
              'quantity_delta': -item.quantityScaled, // Negative for outgoing sale
              'balance_after': newStockScaled,
              'unit_cost_paise': purchasePricePaise,
              'notes': 'Sales Invoice $allocatedInvoiceNumber',
              'created_at': now.toIso8601String(),
            });
          }
        }
      }

      // 6. Post double-entry accounting records to ledger_entries
      await _postInvoiceLedgerEntries(
        txn,
        invoice: finalizedInvoice,
        isInterState: isInterState,
        now: now,
      );

      // 7. Update Customer Outstanding Balance (Receivable)
      final customerRows = await txn.query(
        'customers',
        columns: ['current_balance_paise'],
        where: 'id = ?',
        whereArgs: [invoice.customerId],
        limit: 1,
      );
      if (customerRows.isNotEmpty) {
        final currentBal = (customerRows.first['current_balance_paise'] as num? ?? 0).toInt();
        final newBal = currentBal + finalizedInvoice.totalAmountPaise;
        await txn.update(
          'customers',
          {
            'current_balance_paise': newBal,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [invoice.customerId],
        );
      }

      // 8. Record audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': invoice.businessId,
        'entity_name': 'INVOICE',
        'entity_id': id,
        'action': 'FINALIZE',
        'user_identifier': 'Local Merchant',
        'details_json': 'Finalized invoice $allocatedInvoiceNumber for ₹${finalizedInvoice.totalAmount.toIndianRupeeString()}',
        'timestamp': now.toIso8601String(),
      });
    });

    final result = await getInvoiceById(id);
    return result!;
  }

  @override
  Future<Invoice> cancelInvoice(String invoiceId, {required String cancellationReason}) async {
    final existing = await getInvoiceById(invoiceId);
    if (existing == null) {
      throw StateError('Invoice $invoiceId not found to cancel.');
    }
    if (existing.status != InvoiceStatus.finalized) {
      throw StateError('Only finalized invoices can be cancelled. Current status: ${existing.status.displayName}');
    }

    final now = DateTime.now().toUtc();

    await _dbHelper.transaction((txn) async {
      // 1. Mark status as CANCELLED
      await txn.update(
        'invoices',
        {
          'status': InvoiceStatus.cancelled.dbValue,
          'cancelled_at': now.toIso8601String(),
          'cancellation_reason': cancellationReason.trim(),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      // 2. Restore stock for goods items
      for (final item in existing.items) {
        final productRows = await txn.query(
          'products',
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [item.productId],
          limit: 1,
        );

        if (productRows.isNotEmpty) {
          final prod = productRows.first;
          final trackInventory = (prod['track_inventory'] as int? ?? 1) == 1;

          if (trackInventory) {
            final currentStockScaled = (prod['current_stock'] as num? ?? 0).toInt();
            final purchasePricePaise = prod['purchase_price_paise'] as int? ?? 0;
            final restoredStockScaled = currentStockScaled + item.quantityScaled;

            await txn.update(
              'products',
              {
                'current_stock': restoredStockScaled,
                'updated_at': now.toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [item.productId],
            );

            await txn.insert('stock_movements', {
              'id': _uuid.v4(),
              'business_id': existing.businessId,
              'product_id': item.productId,
              'reference_id': existing.id,
              'reference_type': 'SALE_RETURN',
              'movement_date': now.toIso8601String().substring(0, 10),
              'quantity_delta': item.quantityScaled, // Positive for restoration
              'balance_after': restoredStockScaled,
              'unit_cost_paise': purchasePricePaise,
              'notes': 'Cancellation Reversal: ${existing.invoiceNumber}',
              'created_at': now.toIso8601String(),
            });
          }
        }
      }

      // 3. Post reversing accounting entries in ledger_entries
      final originalEntries = await txn.query(
        'ledger_entries',
        where: 'transaction_id = ? AND transaction_type = ?',
        whereArgs: [existing.id, 'INVOICE'],
      );

      for (final entry in originalEntries) {
        final debit = entry['debit_paise'] as int? ?? 0;
        final credit = entry['credit_paise'] as int? ?? 0;

        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': existing.businessId,
          'account_id': entry['account_id'],
          'transaction_id': existing.id,
          'transaction_type': 'INVOICE_CANCELLATION',
          'entry_date': now.toIso8601String().substring(0, 10),
          'debit_paise': credit,  // Swapped to reverse
          'credit_paise': debit, // Swapped to reverse
          'description': 'Reversal of entry ${entry['id']}: ${existing.invoiceNumber} cancelled ($cancellationReason)',
          'created_at': now.toIso8601String(),
        });
      }

      // 4. Reverse customer outstanding balance
      final customerRows = await txn.query(
        'customers',
        columns: ['current_balance_paise'],
        where: 'id = ?',
        whereArgs: [existing.customerId],
        limit: 1,
      );
      if (customerRows.isNotEmpty) {
        final currentBal = (customerRows.first['current_balance_paise'] as num? ?? 0).toInt();
        final newBal = currentBal - existing.totalAmountPaise;
        await txn.update(
          'customers',
          {
            'current_balance_paise': newBal,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [existing.customerId],
        );
      }

      // 5. Record audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': existing.businessId,
        'entity_name': 'INVOICE',
        'entity_id': existing.id,
        'action': 'CANCEL',
        'user_identifier': 'Local Merchant',
        'details_json': 'Cancelled invoice ${existing.invoiceNumber}. Reason: $cancellationReason',
        'timestamp': now.toIso8601String(),
      });
    });

    final result = await getInvoiceById(invoiceId);
    return result!;
  }

  @override
  Future<void> deleteDraft(String invoiceId) async {
    final existing = await getInvoiceById(invoiceId);
    if (existing == null) return;
    if (existing.status != InvoiceStatus.draft) {
      throw StateError('Cannot delete non-draft invoice ${existing.invoiceNumber}. Only drafts can be deleted.');
    }

    await _dbHelper.transaction((txn) async {
      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      await txn.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);
    });
  }

  @override
  Future<Invoice?> getInvoiceById(String id) async {
    final db = await _dbHelper.database;
    final invoiceRows = await db.rawQuery('''
      SELECT i.*, 
             c.name as customer_name,
             c.phone as customer_phone,
             c.gstin as customer_gstin,
             c.company_name as customer_company_name,
             (c.billing_address_line1 || 
              CASE WHEN c.billing_city IS NOT NULL AND c.billing_city != '' THEN ', ' || c.billing_city ELSE '' END ||
              CASE WHEN c.billing_state_name IS NOT NULL AND c.billing_state_name != '' THEN ', ' || c.billing_state_name ELSE '' END ||
              CASE WHEN c.billing_pincode IS NOT NULL AND c.billing_pincode != '' THEN ' - ' || c.billing_pincode ELSE '' END
             ) as customer_address
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE i.id = ?
      LIMIT 1
    ''', [id]);

    if (invoiceRows.isEmpty) return null;

    final itemRows = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [id],
      orderBy: 'created_at ASC',
    );

    final items = itemRows.map((m) => InvoiceItem.fromMap(m)).toList();
    return Invoice.fromMap(invoiceRows.first, items: items);
  }

  @override
  Future<Invoice?> getInvoiceByNumber(String businessId, String invoiceNumber) async {
    final db = await _dbHelper.database;
    final invoiceRows = await db.query(
      'invoices',
      columns: ['id'],
      where: 'business_id = ? AND invoice_number = ?',
      whereArgs: [businessId, invoiceNumber],
      limit: 1,
    );

    if (invoiceRows.isEmpty) return null;
    return getInvoiceById(invoiceRows.first['id'] as String);
  }

  @override
  Future<List<Invoice>> getInvoices({
    required String businessId,
    InvoiceStatus? status,
    String? customerId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    final whereData = _buildInvoiceQuery(
      businessId: businessId,
      status: status,
      customerId: customerId,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
    );

    final sql = '''
      SELECT i.*, 
             c.name as customer_name,
             c.phone as customer_phone,
             c.gstin as customer_gstin,
             c.company_name as customer_company_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE ${whereData.whereClause}
      ORDER BY i.invoice_date DESC, i.created_at DESC
      LIMIT ? OFFSET ?
    ''';

    final args = [...whereData.whereArgs, limit, offset];
    final rows = await db.rawQuery(sql, args);

    if (rows.isEmpty) return [];

    final invoiceIds = rows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(invoiceIds.length, '?').join(',');
    final itemRows = await db.rawQuery(
      'SELECT * FROM invoice_items WHERE invoice_id IN ($placeholders) ORDER BY created_at ASC',
      invoiceIds,
    );

    final itemsByInvoiceId = <String, List<InvoiceItem>>{};
    for (final row in itemRows) {
      final invId = row['invoice_id'] as String;
      itemsByInvoiceId.putIfAbsent(invId, () => []).add(InvoiceItem.fromMap(row));
    }

    return rows.map((row) {
      final invId = row['id'] as String;
      final items = itemsByInvoiceId[invId] ?? const [];
      return Invoice.fromMap(row, items: items);
    }).toList();
  }

  @override
  Future<int> countInvoices({
    required String businessId,
    InvoiceStatus? status,
    String? customerId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _dbHelper.database;
    final whereData = _buildInvoiceQuery(
      businessId: businessId,
      status: status,
      customerId: customerId,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
    );

    final sql = '''
      SELECT COUNT(*) as count
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE ${whereData.whereClause}
    ''';

    final result = await db.rawQuery(sql, whereData.whereArgs);
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<String> getNextInvoiceNumberPreview(String businessId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final fiscalYear = _calculateFiscalYear(now);

    final rows = await db.query(
      'invoice_sequences',
      where: 'business_id = ? AND document_type = ? AND fiscal_year = ?',
      whereArgs: [businessId, 'INVOICE', fiscalYear],
      limit: 1,
    );

    if (rows.isEmpty) {
      final year = now.year;
      return 'INV-$year-0001';
    }

    final row = rows.first;
    final prefix = row['prefix'] as String? ?? 'INV-${now.year}-';
    final currentNumber = row['current_number'] as int? ?? 1;
    final paddingZeros = row['padding_zeros'] as int? ?? 4;

    return '$prefix${currentNumber.toString().padLeft(paddingZeros, '0')}';
  }

  // --- Internal Helpers ---

  Future<String> _allocateNextInvoiceNumber(
    Transaction txn,
    String businessId,
    DateTime invoiceDate,
  ) async {
    final fiscalYear = _calculateFiscalYear(invoiceDate);
    final nowStr = DateTime.now().toUtc().toIso8601String();

    final rows = await txn.query(
      'invoice_sequences',
      where: 'business_id = ? AND document_type = ? AND fiscal_year = ?',
      whereArgs: [businessId, 'INVOICE', fiscalYear],
      limit: 1,
    );

    int numberToUse;
    String prefix;
    int paddingZeros;

    if (rows.isEmpty) {
      numberToUse = 1;
      prefix = 'INV-${invoiceDate.year}-';
      paddingZeros = 4;

      await txn.insert('invoice_sequences', {
        'id': _uuid.v4(),
        'business_id': businessId,
        'document_type': 'INVOICE',
        'prefix': prefix,
        'current_number': 2, // Next number
        'padding_zeros': paddingZeros,
        'fiscal_year': fiscalYear,
        'created_at': nowStr,
        'updated_at': nowStr,
      });
    } else {
      final row = rows.first;
      numberToUse = row['current_number'] as int? ?? 1;
      prefix = row['prefix'] as String? ?? 'INV-${invoiceDate.year}-';
      paddingZeros = row['padding_zeros'] as int? ?? 4;

      await txn.update(
        'invoice_sequences',
        {
          'current_number': numberToUse + 1,
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    return '$prefix${numberToUse.toString().padLeft(paddingZeros, '0')}';
  }

  String _calculateFiscalYear(DateTime date) {
    final year = date.year;
    if (date.month >= 4) {
      return '$year-${year + 1}';
    } else {
      return '${year - 1}-$year';
    }
  }

  Future<void> _postInvoiceLedgerEntries(
    Transaction txn, {
    required Invoice invoice,
    required bool isInterState,
    required DateTime now,
  }) async {
    final dateStr = invoice.invoiceDate.toIso8601String().substring(0, 10);
    final nowStr = now.toIso8601String();

    // Accounts according to Chart of Accounts (docs/ACCOUNTING_RULES.md Section 3.1)
    final arAccountId = await _ensureAccount(
      txn,
      businessId: invoice.businessId,
      code: '1100',
      name: 'Accounts Receivable',
      type: 'ASSET',
    );

    final salesAccountId = await _ensureAccount(
      txn,
      businessId: invoice.businessId,
      code: '4000',
      name: 'Sales Revenue',
      type: 'INCOME',
    );

    // 1. DEBIT: Accounts Receivable (Total Invoice Amount)
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': invoice.businessId,
      'account_id': arAccountId,
      'transaction_id': invoice.id,
      'transaction_type': 'INVOICE',
      'entry_date': dateStr,
      'debit_paise': invoice.totalAmountPaise,
      'credit_paise': 0,
      'description': 'Tax Invoice ${invoice.invoiceNumber}',
      'created_at': nowStr,
    });

    // 2. CREDIT: Sales Revenue (Taxable Amount)
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': invoice.businessId,
      'account_id': salesAccountId,
      'transaction_id': invoice.id,
      'transaction_type': 'INVOICE',
      'entry_date': dateStr,
      'debit_paise': 0,
      'credit_paise': invoice.taxableAmountPaise,
      'description': 'Taxable sales on ${invoice.invoiceNumber}',
      'created_at': nowStr,
    });

    // 3. CREDIT: Output Tax Accounts
    if (isInterState) {
      if (invoice.igstPaise > 0) {
        final igstAccountId = await _ensureAccount(
          txn,
          businessId: invoice.businessId,
          code: '2230',
          name: 'Output IGST Payable',
          type: 'LIABILITY',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': invoice.businessId,
          'account_id': igstAccountId,
          'transaction_id': invoice.id,
          'transaction_type': 'INVOICE',
          'entry_date': dateStr,
          'debit_paise': 0,
          'credit_paise': invoice.igstPaise,
          'description': 'Output IGST on ${invoice.invoiceNumber}',
          'created_at': nowStr,
        });
      }
    } else {
      if (invoice.cgstPaise > 0) {
        final cgstAccountId = await _ensureAccount(
          txn,
          businessId: invoice.businessId,
          code: '2210',
          name: 'Output CGST Payable',
          type: 'LIABILITY',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': invoice.businessId,
          'account_id': cgstAccountId,
          'transaction_id': invoice.id,
          'transaction_type': 'INVOICE',
          'entry_date': dateStr,
          'debit_paise': 0,
          'credit_paise': invoice.cgstPaise,
          'description': 'Output CGST on ${invoice.invoiceNumber}',
          'created_at': nowStr,
        });
      }

      if (invoice.sgstPaise > 0) {
        final sgstAccountId = await _ensureAccount(
          txn,
          businessId: invoice.businessId,
          code: '2220',
          name: 'Output SGST Payable',
          type: 'LIABILITY',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': invoice.businessId,
          'account_id': sgstAccountId,
          'transaction_id': invoice.id,
          'transaction_type': 'INVOICE',
          'entry_date': dateStr,
          'debit_paise': 0,
          'credit_paise': invoice.sgstPaise,
          'description': 'Output SGST on ${invoice.invoiceNumber}',
          'created_at': nowStr,
        });
      }
    }

    // 4. Round-off Account posting
    if (invoice.roundOffPaise != 0) {
      final roundOffAccountId = await _ensureAccount(
        txn,
        businessId: invoice.businessId,
        code: '5200',
        name: 'Round-Off Account',
        type: 'EXPENSE',
      );

      if (invoice.roundOffPaise > 0) {
        // Round-off added to total: Credit round-off account
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': invoice.businessId,
          'account_id': roundOffAccountId,
          'transaction_id': invoice.id,
          'transaction_type': 'INVOICE',
          'entry_date': dateStr,
          'debit_paise': 0,
          'credit_paise': invoice.roundOffPaise,
          'description': 'Round-off gain on ${invoice.invoiceNumber}',
          'created_at': nowStr,
        });
      } else {
        // Round-off deducted from total: Debit round-off account
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': invoice.businessId,
          'account_id': roundOffAccountId,
          'transaction_id': invoice.id,
          'transaction_type': 'INVOICE',
          'entry_date': dateStr,
          'debit_paise': invoice.roundOffPaise.abs(),
          'credit_paise': 0,
          'description': 'Round-off concession on ${invoice.invoiceNumber}',
          'created_at': nowStr,
        });
      }
    }
  }

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

  _InvoiceQueryData _buildInvoiceQuery({
    required String businessId,
    InvoiceStatus? status,
    String? customerId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final StringBuffer whereClause = StringBuffer('i.business_id = ?');
    final List<dynamic> whereArgs = [businessId];

    if (status != null) {
      whereClause.write(' AND i.status = ?');
      whereArgs.add(status.dbValue);
    }

    if (customerId != null && customerId.trim().isNotEmpty) {
      whereClause.write(' AND i.customer_id = ?');
      whereArgs.add(customerId);
    }

    if (startDate != null) {
      whereClause.write(' AND i.invoice_date >= ?');
      whereArgs.add(startDate.toIso8601String().substring(0, 10));
    }

    if (endDate != null) {
      whereClause.write(' AND i.invoice_date <= ?');
      whereArgs.add(endDate.toIso8601String().substring(0, 10));
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      whereClause.write(' AND (i.invoice_number LIKE ? OR c.name LIKE ? OR c.phone LIKE ? OR c.gstin LIKE ?)');
      whereArgs.addAll([term, term, term, term]);
    }

    return _InvoiceQueryData(whereClause.toString(), whereArgs);
  }
}

class _InvoiceQueryData {
  final String whereClause;
  final List<dynamic> whereArgs;
  _InvoiceQueryData(this.whereClause, this.whereArgs);
}
