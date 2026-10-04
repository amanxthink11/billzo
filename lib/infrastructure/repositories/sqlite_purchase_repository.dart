import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/domain/invoice/tax_engine.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_item.dart';
import 'package:billzo/domain/purchase/purchase_repository.dart';
import 'package:billzo/domain/purchase/purchase_return.dart';
import 'package:billzo/domain/purchase/purchase_return_item.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/domain/purchase/purchase_validator.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of [IPurchaseRepository] providing ACID transactional
/// integrity, stock integration, double-entry ledger postings, and accounts payable tracking.
class SqlitePurchaseRepository implements IPurchaseRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  /// Optional callback to inject intentional failures for transaction rollback verification.
  final Future<void> Function(Transaction txn)? onBeforePostCommitForTesting;

  SqlitePurchaseRepository(
    this._dbHelper, {
    this.onBeforePostCommitForTesting,
  });

  @override
  Future<Purchase> saveDraft(Purchase purchase) async {
    final validation = PurchaseValidator.validate(purchase);
    if (validation.hasErrors) {
      throw ArgumentError(
        'Purchase validation failed: ${validation.errors.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
      );
    }

    final id = purchase.id.isEmpty ? _uuid.v4() : purchase.id;
    final now = DateTime.now().toUtc();
    final draftNumber = purchase.purchaseNumber.isNotEmpty &&
            !purchase.purchaseNumber.startsWith('PUR-')
        ? purchase.purchaseNumber
        : 'DRAFT-${id.substring(0, 8).toUpperCase()}';

    final toSave = purchase.copyWith(
      id: id,
      purchaseNumber: draftNumber,
      status: PurchaseStatus.draft,
      paidAmountPaise: 0,
      balanceAmountPaise: purchase.totalAmountPaise,
      createdAt: purchase.createdAt.year > 2000 ? purchase.createdAt : now,
      updatedAt: now,
    );

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert(
        'purchases',
        toSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);
      for (final item in toSave.items) {
        final itemId = item.id.isEmpty ? _uuid.v4() : item.id;
        final itemToSave = item.copyWith(
          id: itemId,
          purchaseId: id,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('purchase_items', itemToSave.toMap());
      }

      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': toSave.businessId,
        'entity_name': 'PURCHASE',
        'entity_id': id,
        'action': 'SAVE_DRAFT',
        'user_identifier': 'Local Merchant',
        'details_json': 'Draft purchase saved: $draftNumber',
        'timestamp': now.toIso8601String(),
      });
    });

    final saved = await getPurchaseById(id);
    return saved ?? toSave;
  }

  @override
  Future<Purchase> updateDraft(Purchase purchase) async {
    final existing = await getPurchaseById(purchase.id);
    if (existing == null) {
      throw StateError('Purchase ${purchase.id} not found to update.');
    }
    if (existing.status != PurchaseStatus.draft) {
      throw StateError(
        'Cannot edit purchase ${existing.purchaseNumber} with status ${existing.status.displayName}. Only drafts can be edited.',
      );
    }

    return saveDraft(purchase);
  }

  @override
  Future<void> deleteDraft(String purchaseId) async {
    final existing = await getPurchaseById(purchaseId);
    if (existing == null) return;
    if (existing.status != PurchaseStatus.draft) {
      throw StateError(
        'Cannot delete non-draft purchase ${existing.purchaseNumber} (status: ${existing.status.displayName}).',
      );
    }

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId]);
      await txn.delete('purchases', where: 'id = ?', whereArgs: [purchaseId]);
    });
  }

  @override
  Future<Purchase> finalizePurchase(Purchase purchase) async {
    final validation = PurchaseValidator.validate(purchase);
    if (validation.hasErrors) {
      throw ArgumentError(
        'Purchase validation failed: ${validation.errors.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
      );
    }

    final now = DateTime.now().toUtc();
    final id = purchase.id.isEmpty ? _uuid.v4() : purchase.id;
    String allocatedPurchaseNumber = '';

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // 1. Check duplicate vendor invoice number if provided
      if (purchase.supplierInvoiceNumber != null &&
          purchase.supplierInvoiceNumber!.trim().isNotEmpty) {
        final duplicateRows = await txn.query(
          'purchases',
          where: 'business_id = ? AND supplier_id = ? AND (supplier_invoice_number = ? OR vendor_invoice_number = ?) AND id != ? AND status != ?',
          whereArgs: [
            purchase.businessId,
            purchase.supplierId,
            purchase.supplierInvoiceNumber!.trim(),
            purchase.supplierInvoiceNumber!.trim(),
            id,
            PurchaseStatus.cancelled.dbValue,
          ],
          limit: 1,
        );
        if (duplicateRows.isNotEmpty) {
          throw ArgumentError(
            'Supplier invoice number "${purchase.supplierInvoiceNumber}" already exists for this supplier in purchase ${duplicateRows.first['purchase_number']}.',
          );
        }
      }

      // 2. Allocate internal purchase number atomically from invoice_sequences
      allocatedPurchaseNumber = await _allocateNextPurchaseNumber(
        txn,
        purchase.businessId,
        purchase.purchaseDate,
      );

      // 3. Determine business state for inter-state tax checking
      final businessRows = await txn.query(
        'businesses',
        columns: ['state_code'],
        where: 'id = ?',
        whereArgs: [purchase.businessId],
        limit: 1,
      );
      final businessStateCode = businessRows.isNotEmpty
          ? (businessRows.first['state_code'] as String? ?? '27')
          : '27';
      final isInterState = TaxEngine.isInterState(
        businessStateCode: businessStateCode,
        placeOfSupplyStateCode: purchase.placeOfSupplyStateCode,
      );

      // 4. Calculate eligible input tax credit amounts
      int inputCgstPaise = 0;
      int inputSgstPaise = 0;
      int inputIgstPaise = 0;
      int inputCessPaise = 0;

      if (purchase.itcEligibility.isEligible) {
        for (final item in purchase.items) {
          if (item.isItcEligible) {
            inputCgstPaise += item.cgstAmountPaise;
            inputSgstPaise += item.sgstAmountPaise;
            inputIgstPaise += item.igstAmountPaise;
            inputCessPaise += item.cessAmountPaise;
          }
        }
      }

      final finalizedPurchase = purchase.copyWith(
        id: id,
        purchaseNumber: allocatedPurchaseNumber,
        status: PurchaseStatus.finalized,
        paidAmountPaise: 0,
        balanceAmountPaise: purchase.totalAmountPaise,
        finalizedAt: now,
        inputCgstPaise: inputCgstPaise,
        inputSgstPaise: inputSgstPaise,
        inputIgstPaise: inputIgstPaise,
        inputCessPaise: inputCessPaise,
        createdAt: purchase.createdAt.year > 2000 ? purchase.createdAt : now,
        updatedAt: now,
      );

      // 5. Insert/Update purchase record
      await txn.insert(
        'purchases',
        finalizedPurchase.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 6. Insert items & update inventory for goods
      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);
      for (final item in finalizedPurchase.items) {
        final itemId = item.id.isEmpty ? _uuid.v4() : item.id;
        final itemToSave = item.copyWith(
          id: itemId,
          purchaseId: id,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('purchase_items', itemToSave.toMap());

        // Stock addition for physical goods
        if (item.trackInventory) {
          final prodRows = await txn.query(
            'products',
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [item.productId],
            limit: 1,
          );

          if (prodRows.isNotEmpty) {
            final currentStock = (prodRows.first['current_stock'] as num? ?? 0).toInt();
            final newStock = currentStock + item.quantityScaled;

            await txn.update(
              'products',
              {
                'current_stock': newStock,
                'updated_at': now.toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [item.productId],
            );

            // Record append-only stock movement
            await txn.insert('stock_movements', {
              'id': _uuid.v4(),
              'business_id': purchase.businessId,
              'product_id': item.productId,
              'reference_id': id,
              'reference_type': 'PURCHASE',
              'movement_date': purchase.purchaseDate.toIso8601String().substring(0, 10),
              'quantity_delta': item.quantityScaled, // Positive for inward purchase
              'balance_after': newStock,
              'unit_cost_paise': item.purchaseRatePaise,
              'notes': 'Purchase Bill $allocatedPurchaseNumber',
              'created_at': now.toIso8601String(),
            });
          }
        }
      }

      // 7. Post double-entry accounting records to ledger_entries
      await _postPurchaseLedgerEntries(
        txn,
        purchase: finalizedPurchase,
        isInterState: isInterState,
        now: now,
      );

      // 8. Update Supplier Balance (Accounts Payable increases)
      final supplierRows = await txn.query(
        'suppliers',
        columns: ['current_balance_paise'],
        where: 'id = ?',
        whereArgs: [purchase.supplierId],
        limit: 1,
      );
      if (supplierRows.isNotEmpty) {
        final currentBal = (supplierRows.first['current_balance_paise'] as num? ?? 0).toInt();
        final newBal = currentBal + finalizedPurchase.totalAmountPaise;
        await txn.update(
          'suppliers',
          {
            'current_balance_paise': newBal,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [purchase.supplierId],
        );
      }

      // 9. Audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': purchase.businessId,
        'entity_name': 'PURCHASE',
        'entity_id': id,
        'action': 'FINALIZE',
        'user_identifier': 'Local Merchant',
        'details_json':
            'Finalized purchase $allocatedPurchaseNumber for ₹${(finalizedPurchase.totalAmountPaise / 100).toStringAsFixed(2)}',
        'timestamp': now.toIso8601String(),
      });

      // Hook for rollback testing
      if (onBeforePostCommitForTesting != null) {
        await onBeforePostCommitForTesting!(txn);
      }
    });

    final result = await getPurchaseById(id);
    return result!;
  }

  @override
  Future<Purchase> cancelPurchase(String purchaseId, {required String cancellationReason}) async {
    final existing = await getPurchaseById(purchaseId);
    if (existing == null) {
      throw StateError('Purchase $purchaseId not found to cancel.');
    }
    if (existing.status != PurchaseStatus.finalized &&
        existing.status != PurchaseStatus.partiallyPaid) {
      throw StateError(
        'Only finalized purchases can be cancelled. Current status: ${existing.status.displayName}',
      );
    }
    if (existing.paidAmountPaise > 0) {
      throw StateError(
        'Cannot cancel purchase ${existing.purchaseNumber} because payments of ₹${(existing.paidAmountPaise / 100).toStringAsFixed(2)} have been allocated. Cancel or reallocate payments first.',
      );
    }

    final db = await _dbHelper.database;
    final returnRows = await db.query(
      'purchase_returns',
      where: 'original_purchase_id = ? AND status != ?',
      whereArgs: [purchaseId, 'CANCELLED'],
      limit: 1,
    );
    if (returnRows.isNotEmpty) {
      throw StateError(
        'Cannot cancel purchase ${existing.purchaseNumber} because debit notes/returns have been created against it. Cancel debit notes first.',
      );
    }

    final now = DateTime.now().toUtc();
    final nowStr = now.toIso8601String();
    final dateStr = existing.purchaseDate.toIso8601String().substring(0, 10);

    await db.transaction((txn) async {
      // 1. Mark purchase cancelled
      await txn.update(
        'purchases',
        {
          'status': PurchaseStatus.cancelled.dbValue,
          'cancelled_at': nowStr,
          'cancellation_reason': cancellationReason,
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [purchaseId],
      );

      // 2. Reverse stock additions for physical goods
      for (final item in existing.items) {
        if (item.trackInventory) {
          final prodRows = await txn.query(
            'products',
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [item.productId],
            limit: 1,
          );

          if (prodRows.isNotEmpty) {
            final currentStock = (prodRows.first['current_stock'] as num? ?? 0).toInt();
            final newStock = currentStock - item.quantityScaled;

            await txn.update(
              'products',
              {
                'current_stock': newStock,
                'updated_at': nowStr,
              },
              where: 'id = ?',
              whereArgs: [item.productId],
            );

            await txn.insert('stock_movements', {
              'id': _uuid.v4(),
              'business_id': existing.businessId,
              'product_id': item.productId,
              'reference_id': purchaseId,
              'reference_type': 'PURCHASE_CANCEL',
              'movement_date': dateStr,
              'quantity_delta': -item.quantityScaled, // Reverse previously added stock
              'balance_after': newStock,
              'unit_cost_paise': item.purchaseRatePaise,
              'notes': 'Purchase Cancellation of ${existing.purchaseNumber}: $cancellationReason',
              'created_at': nowStr,
            });
          }
        }
      }

      // 3. Post reversing accounting entries
      final originalEntries = await txn.query(
        'ledger_entries',
        where: 'transaction_id = ? AND transaction_type = ?',
        whereArgs: [purchaseId, 'PURCHASE'],
      );

      for (final entry in originalEntries) {
        final originalDebit = (entry['debit_paise'] as num? ?? 0).toInt();
        final originalCredit = (entry['credit_paise'] as num? ?? 0).toInt();

        // Swap debit and credit to balance out
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': existing.businessId,
          'account_id': entry['account_id'],
          'transaction_id': purchaseId,
          'transaction_type': 'PURCHASE_CANCEL',
          'entry_date': dateStr,
          'debit_paise': originalCredit,
          'credit_paise': originalDebit,
          'description': 'Reversal: ${entry['description']} ($cancellationReason)',
          'created_at': nowStr,
        });
      }

      // 4. Reduce supplier payable balance
      final supplierRows = await txn.query(
        'suppliers',
        columns: ['current_balance_paise'],
        where: 'id = ?',
        whereArgs: [existing.supplierId],
        limit: 1,
      );
      if (supplierRows.isNotEmpty) {
        final currentBal = (supplierRows.first['current_balance_paise'] as num? ?? 0).toInt();
        final newBal = currentBal - existing.totalAmountPaise;
        await txn.update(
          'suppliers',
          {
            'current_balance_paise': newBal,
            'updated_at': nowStr,
          },
          where: 'id = ?',
          whereArgs: [existing.supplierId],
        );
      }

      // 5. Audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': existing.businessId,
        'entity_name': 'PURCHASE',
        'entity_id': purchaseId,
        'action': 'CANCEL',
        'user_identifier': 'Local Merchant',
        'details_json': 'Cancelled purchase ${existing.purchaseNumber}: $cancellationReason',
        'timestamp': nowStr,
      });

      if (onBeforePostCommitForTesting != null) {
        await onBeforePostCommitForTesting!(txn);
      }
    });

    final cancelled = await getPurchaseById(purchaseId);
    return cancelled!;
  }

  @override
  Future<Purchase?> getPurchaseById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
             s.name as supplier_name,
             s.phone as supplier_phone,
             s.gstin as supplier_gstin,
             s.company_name as supplier_company_name,
             s.address_line1 as supplier_address
      FROM purchases p
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      WHERE p.id = ? AND p.deleted_at IS NULL
      LIMIT 1
    ''', [id]);

    if (rows.isEmpty) return null;

    final itemRows = await db.rawQuery('''
      SELECT pi.*,
             p.name as product_name_fallback
      FROM purchase_items pi
      LEFT JOIN products p ON pi.product_id = p.id
      WHERE pi.purchase_id = ?
      ORDER BY pi.rowid ASC
    ''', [id]);

    final items = itemRows.map(PurchaseItem.fromMap).toList();
    return Purchase.fromMap(rows.first, items: items);
  }

  @override
  Future<List<Purchase>> getPurchases({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    final whereClauses = <String>['p.business_id = ?', 'p.deleted_at IS NULL'];
    final whereArgs = <dynamic>[businessId];

    if (status != null) {
      whereClauses.add('p.status = ?');
      whereArgs.add(status.dbValue);
    }

    if (supplierId != null && supplierId.isNotEmpty) {
      whereClauses.add('p.supplier_id = ?');
      whereArgs.add(supplierId);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      whereClauses.add('(p.purchase_number LIKE ? OR p.supplier_invoice_number LIKE ? OR s.name LIKE ?)');
      whereArgs.addAll([query, query, query]);
    }

    if (startDate != null) {
      whereClauses.add('p.purchase_date >= ?');
      whereArgs.add(startDate.toIso8601String().substring(0, 10));
    }

    if (endDate != null) {
      whereClauses.add('p.purchase_date <= ?');
      whereArgs.add(endDate.toIso8601String().substring(0, 10));
    }

    final sql = '''
      SELECT p.*,
             s.name as supplier_name,
             s.phone as supplier_phone,
             s.gstin as supplier_gstin,
             s.company_name as supplier_company_name,
             s.address_line1 as supplier_address
      FROM purchases p
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY p.purchase_date DESC, p.created_at DESC
      LIMIT ? OFFSET ?
    ''';

    whereArgs.add(limit);
    whereArgs.add(offset);

    final rows = await db.rawQuery(sql, whereArgs);
    if (rows.isEmpty) return [];

    final purchaseIds = rows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(purchaseIds.length, '?').join(',');

    final itemRows = await db.rawQuery('''
      SELECT pi.*,
             p.name as product_name_fallback
      FROM purchase_items pi
      LEFT JOIN products p ON pi.product_id = p.id
      WHERE pi.purchase_id IN ($placeholders)
      ORDER BY pi.rowid ASC
    ''', purchaseIds);

    final itemsMap = <String, List<PurchaseItem>>{};
    for (final itemRow in itemRows) {
      final pid = itemRow['purchase_id'] as String;
      itemsMap.putIfAbsent(pid, () => []).add(PurchaseItem.fromMap(itemRow));
    }

    return rows.map((r) {
      final pid = r['id'] as String;
      return Purchase.fromMap(r, items: itemsMap[pid] ?? const []);
    }).toList();
  }

  @override
  Future<int> getPurchasesCount({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _dbHelper.database;
    final whereClauses = <String>['p.business_id = ?', 'p.deleted_at IS NULL'];
    final whereArgs = <dynamic>[businessId];

    if (status != null) {
      whereClauses.add('p.status = ?');
      whereArgs.add(status.dbValue);
    }

    if (supplierId != null && supplierId.isNotEmpty) {
      whereClauses.add('p.supplier_id = ?');
      whereArgs.add(supplierId);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      whereClauses.add('(p.purchase_number LIKE ? OR p.supplier_invoice_number LIKE ? OR s.name LIKE ?)');
      whereArgs.addAll([query, query, query]);
    }

    if (startDate != null) {
      whereClauses.add('p.purchase_date >= ?');
      whereArgs.add(startDate.toIso8601String().substring(0, 10));
    }

    if (endDate != null) {
      whereClauses.add('p.purchase_date <= ?');
      whereArgs.add(endDate.toIso8601String().substring(0, 10));
    }

    final sql = '''
      SELECT COUNT(*) as count
      FROM purchases p
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      WHERE ${whereClauses.join(' AND ')}
    ''';

    final result = await db.rawQuery(sql, whereArgs);
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<String> getNextPurchaseNumberPreview(String businessId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final fiscalYear = _calculateFiscalYear(now);

    final rows = await db.query(
      'invoice_sequences',
      columns: ['current_number', 'prefix', 'padding_zeros'],
      where: 'business_id = ? AND document_type = ? AND fiscal_year = ?',
      whereArgs: [businessId, 'PURCHASE', fiscalYear],
      limit: 1,
    );

    int nextNum = 1;
    String prefix = 'PUR-$fiscalYear-';
    int padding = 4;

    if (rows.isNotEmpty) {
      final row = rows.first;
      nextNum = (row['current_number'] as num? ?? 0).toInt() + 1;
      prefix = row['prefix'] as String? ?? prefix;
      padding = (row['padding_zeros'] as num? ?? 4).toInt();
    }

    return '$prefix${nextNum.toString().padLeft(padding, '0')}';
  }

  @override
  Future<bool> isSupplierInvoiceDuplicate(
    String businessId,
    String supplierId,
    String supplierInvoiceNumber, {
    String? excludePurchaseId,
  }) async {
    if (supplierInvoiceNumber.trim().isEmpty) return false;
    final db = await _dbHelper.database;

    final where = StringBuffer(
      'business_id = ? AND supplier_id = ? AND (supplier_invoice_number = ? OR vendor_invoice_number = ?) AND status != ? AND deleted_at IS NULL',
    );
    final args = <dynamic>[
      businessId,
      supplierId,
      supplierInvoiceNumber.trim(),
      supplierInvoiceNumber.trim(),
      PurchaseStatus.cancelled.dbValue,
    ];

    if (excludePurchaseId != null) {
      where.write(' AND id != ?');
      args.add(excludePurchaseId);
    }

    final rows = await db.query('purchases', columns: ['id'], where: where.toString(), whereArgs: args, limit: 1);
    return rows.isNotEmpty;
  }

  @override
  Future<PurchaseReturn> createReturn(PurchaseReturn purchaseReturn) async {
    final original = await getPurchaseById(purchaseReturn.originalPurchaseId);
    if (original == null) {
      throw StateError('Original purchase ${purchaseReturn.originalPurchaseId} not found for return.');
    }

    // Get previously returned quantities for this purchase
    final db = await _dbHelper.database;
    final prevRows = await db.rawQuery('''
      SELECT pri.product_id, pri.purchase_item_id, SUM(pri.quantity) as total_qty
      FROM purchase_return_items pri
      JOIN purchase_returns pr ON pri.purchase_return_id = pr.id
      WHERE pr.original_purchase_id = ? AND pr.status != 'CANCELLED'
      GROUP BY pri.product_id, pri.purchase_item_id
    ''', [purchaseReturn.originalPurchaseId]);

    final prevQtyMap = <String, int>{};
    for (final r in prevRows) {
      final pid = r['product_id'] as String;
      final piid = r['purchase_item_id'] as String?;
      final total = (r['total_qty'] as num? ?? 0).toInt();
      prevQtyMap[pid] = (prevQtyMap[pid] ?? 0) + total;
      if (piid != null) prevQtyMap[piid] = (prevQtyMap[piid] ?? 0) + total;
    }

    final validation = PurchaseValidator.validateReturn(
      purchaseReturn,
      originalPurchase: original,
      previouslyReturnedQuantities: prevQtyMap,
    );
    if (validation.hasErrors) {
      throw ArgumentError(validation.firstError);
    }

    final id = purchaseReturn.id.isEmpty ? _uuid.v4() : purchaseReturn.id;
    final now = DateTime.now().toUtc();
    final nowStr = now.toIso8601String();
    final dateStr = purchaseReturn.returnDate.toIso8601String().substring(0, 10);
    String allocatedReturnNumber = '';

    await db.transaction((txn) async {
      // 1. Allocate debit note number
      allocatedReturnNumber = await _allocateNextDebitNoteNumber(
        txn,
        purchaseReturn.businessId,
        purchaseReturn.returnDate,
      );

      final toSave = purchaseReturn.copyWith(
        id: id,
        returnNumber: allocatedReturnNumber,
        status: 'FINALIZED',
        createdAt: now,
        updatedAt: now,
      );

      // 2. Insert purchase_returns record
      await txn.insert('purchase_returns', toSave.toMap());

      // 3. Insert items and decrease stock for physical goods
      for (final item in toSave.items) {
        final itemId = item.id.isEmpty ? _uuid.v4() : item.id;
        final itemToSave = item.copyWith(
          id: itemId,
          purchaseReturnId: id,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('purchase_return_items', itemToSave.toMap());

        if (item.trackInventory) {
          final prodRows = await txn.query(
            'products',
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [item.productId],
            limit: 1,
          );

          if (prodRows.isNotEmpty) {
            final currentStock = (prodRows.first['current_stock'] as num? ?? 0).toInt();
            final newStock = currentStock - item.quantityScaled;

            await txn.update(
              'products',
              {
                'current_stock': newStock,
                'updated_at': nowStr,
              },
              where: 'id = ?',
              whereArgs: [item.productId],
            );

            await txn.insert('stock_movements', {
              'id': _uuid.v4(),
              'business_id': purchaseReturn.businessId,
              'product_id': item.productId,
              'reference_id': id,
              'reference_type': 'PURCHASE_RETURN',
              'movement_date': dateStr,
              'quantity_delta': -item.quantityScaled, // Negative for returned stock
              'balance_after': newStock,
              'unit_cost_paise': item.ratePaise,
              'notes': 'Purchase Return $allocatedReturnNumber on Purchase ${original.purchaseNumber}',
              'created_at': nowStr,
            });
          }
        }
      }

      // 4. Reduce supplier payable balance
      final supplierRows = await txn.query(
        'suppliers',
        columns: ['current_balance_paise'],
        where: 'id = ?',
        whereArgs: [purchaseReturn.supplierId],
        limit: 1,
      );
      if (supplierRows.isNotEmpty) {
        final currentBal = (supplierRows.first['current_balance_paise'] as num? ?? 0).toInt();
        final newBal = currentBal - toSave.totalAmountPaise;
        await txn.update(
          'suppliers',
          {
            'current_balance_paise': newBal,
            'updated_at': nowStr,
          },
          where: 'id = ?',
          whereArgs: [purchaseReturn.supplierId],
        );
      }

      // 5. Adjust original purchase outstanding balance
      final newPurchaseBal = (original.balanceAmountPaise - toSave.totalAmountPaise)
          .clamp(0, original.totalAmountPaise);
      final newStatus = newPurchaseBal == 0
          ? PurchaseStatus.paid.dbValue
          : (original.paidAmountPaise > 0
              ? PurchaseStatus.partiallyPaid.dbValue
              : original.status.dbValue);

      await txn.update(
        'purchases',
        {
          'balance_amount_paise': newPurchaseBal,
          'status': newStatus,
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [original.id],
      );

      // 6. Post double-entry accounting records
      await _postPurchaseReturnLedgerEntries(
        txn,
        purchaseReturn: toSave,
        originalPurchase: original,
        now: now,
      );

      // 7. Audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': purchaseReturn.businessId,
        'entity_name': 'PURCHASE_RETURN',
        'entity_id': id,
        'action': 'CREATE_RETURN',
        'user_identifier': 'Local Merchant',
        'details_json':
            'Created debit note $allocatedReturnNumber for ₹${(toSave.totalAmountPaise / 100).toStringAsFixed(2)} against ${original.purchaseNumber}',
        'timestamp': nowStr,
      });

      if (onBeforePostCommitForTesting != null) {
        await onBeforePostCommitForTesting!(txn);
      }
    });

    final created = await getReturnById(id);
    return created!;
  }

  @override
  Future<PurchaseReturn?> getReturnById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT pr.*,
             s.name as supplier_name,
             p.purchase_number as original_purchase_number
      FROM purchase_returns pr
      LEFT JOIN suppliers s ON pr.supplier_id = s.id
      LEFT JOIN purchases p ON pr.original_purchase_id = p.id
      WHERE pr.id = ?
      LIMIT 1
    ''', [id]);

    if (rows.isEmpty) return null;

    final itemRows = await db.query(
      'purchase_return_items',
      where: 'purchase_return_id = ?',
      whereArgs: [id],
    );

    final items = itemRows.map(PurchaseReturnItem.fromMap).toList();
    return PurchaseReturn.fromMap(rows.first, items: items);
  }

  @override
  Future<List<PurchaseReturn>> getReturnsForPurchase(String purchaseId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT pr.*,
             s.name as supplier_name,
             p.purchase_number as original_purchase_number
      FROM purchase_returns pr
      LEFT JOIN suppliers s ON pr.supplier_id = s.id
      LEFT JOIN purchases p ON pr.original_purchase_id = p.id
      WHERE pr.original_purchase_id = ?
      ORDER BY pr.return_date DESC
    ''', [purchaseId]);

    final returns = <PurchaseReturn>[];
    for (final r in rows) {
      final rid = r['id'] as String;
      final itemRows = await db.query('purchase_return_items', where: 'purchase_return_id = ?', whereArgs: [rid]);
      returns.add(PurchaseReturn.fromMap(r, items: itemRows.map(PurchaseReturnItem.fromMap).toList()));
    }
    return returns;
  }

  @override
  Future<List<PurchaseReturn>> getReturns({
    required String businessId,
    String? supplierId,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    final where = <String>['pr.business_id = ?'];
    final args = <dynamic>[businessId];

    if (supplierId != null && supplierId.isNotEmpty) {
      where.add('pr.supplier_id = ?');
      args.add(supplierId);
    }

    final sql = '''
      SELECT pr.*,
             s.name as supplier_name,
             p.purchase_number as original_purchase_number
      FROM purchase_returns pr
      LEFT JOIN suppliers s ON pr.supplier_id = s.id
      LEFT JOIN purchases p ON pr.original_purchase_id = p.id
      WHERE ${where.join(' AND ')}
      ORDER BY pr.return_date DESC
      LIMIT ? OFFSET ?
    ''';
    args.add(limit);
    args.add(offset);

    final rows = await db.rawQuery(sql, args);
    final returns = <PurchaseReturn>[];
    for (final r in rows) {
      final rid = r['id'] as String;
      final itemRows = await db.query('purchase_return_items', where: 'purchase_return_id = ?', whereArgs: [rid]);
      returns.add(PurchaseReturn.fromMap(r, items: itemRows.map(PurchaseReturnItem.fromMap).toList()));
    }
    return returns;
  }

  @override
  Future<SupplierAccountsPayableSummary> getSupplierSummary(
    String businessId,
    String supplierId,
  ) async {
    final db = await _dbHelper.database;

    // Total purchased, paid, and count from purchases
    final purRows = await db.rawQuery('''
      SELECT COUNT(*) as count,
             COALESCE(SUM(total_amount_paise), 0) as total_purchased,
             COALESCE(SUM(paid_amount_paise), 0) as total_paid
      FROM purchases
      WHERE business_id = ? AND supplier_id = ? AND status != 'CANCELLED' AND deleted_at IS NULL
    ''', [businessId, supplierId]);

    final totalCount = (purRows.first['count'] as num? ?? 0).toInt();
    final totalPurchased = (purRows.first['total_purchased'] as num? ?? 0).toInt();
    final totalPaid = (purRows.first['total_paid'] as num? ?? 0).toInt();

    // Current outstanding balance from suppliers table
    final suppRows = await db.query(
      'suppliers',
      columns: ['current_balance_paise'],
      where: 'id = ?',
      whereArgs: [supplierId],
      limit: 1,
    );
    final outstanding = suppRows.isNotEmpty
        ? (suppRows.first['current_balance_paise'] as num? ?? 0).toInt()
        : 0;

    // Recent 5 purchases
    final recentPurchases = await getPurchases(
      businessId: businessId,
      supplierId: supplierId,
      limit: 5,
    );

    return SupplierAccountsPayableSummary(
      totalPurchasesCount: totalCount,
      totalPurchasedPaise: totalPurchased,
      totalPaidPaise: totalPaid,
      outstandingPayablePaise: outstanding,
      recentPurchases: recentPurchases,
    );
  }

  @override
  Future<List<Purchase>> getOutstandingPurchasesForSupplier(
    String businessId,
    String supplierId,
  ) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
             s.name as supplier_name,
             s.phone as supplier_phone,
             s.gstin as supplier_gstin,
             s.company_name as supplier_company_name,
             s.address_line1 as supplier_address
      FROM purchases p
      LEFT JOIN suppliers s ON p.supplier_id = s.id
      WHERE p.business_id = ?
        AND p.supplier_id = ?
        AND p.status IN ('FINALIZED', 'PARTIALLY_PAID')
        AND p.balance_amount_paise > 0
        AND p.deleted_at IS NULL
      ORDER BY p.purchase_date ASC, p.created_at ASC
    ''', [businessId, supplierId]);

    return rows.map((r) => Purchase.fromMap(r)).toList();
  }

  // ==============================================================================
  // PRIVATE HELPER METHODS: ACCOUNTING, SEQUENCES, ACCOUNTS
  // ==============================================================================

  Future<void> _postPurchaseLedgerEntries(
    Transaction txn, {
    required Purchase purchase,
    required bool isInterState,
    required DateTime now,
  }) async {
    final dateStr = purchase.purchaseDate.toIso8601String().substring(0, 10);
    final nowStr = now.toIso8601String();

    // 1. Debit: Inventory / Purchase account (1200) for taxable value
    final inventoryAccountId = await _ensureAccount(
      txn,
      businessId: purchase.businessId,
      code: '1200',
      name: 'Inventory Stock Value',
      type: 'ASSET',
    );
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': purchase.businessId,
      'account_id': inventoryAccountId,
      'transaction_id': purchase.id,
      'transaction_type': 'PURCHASE',
      'entry_date': dateStr,
      'debit_paise': purchase.taxableAmountPaise,
      'credit_paise': 0,
      'description': 'Taxable purchases on bill ${purchase.purchaseNumber}',
      'created_at': nowStr,
    });

    // 2. Debit: Input GST
    if (purchase.itcEligibility.isEligible) {
      if (isInterState) {
        if (purchase.igstPaise > 0) {
          final igstAccountId = await _ensureAccount(
            txn,
            businessId: purchase.businessId,
            code: '2330',
            name: 'Input IGST Credit',
            type: 'ASSET',
          );
          await txn.insert('ledger_entries', {
            'id': _uuid.v4(),
            'business_id': purchase.businessId,
            'account_id': igstAccountId,
            'transaction_id': purchase.id,
            'transaction_type': 'PURCHASE',
            'entry_date': dateStr,
            'debit_paise': purchase.igstPaise,
            'credit_paise': 0,
            'description': 'Input IGST Credit on ${purchase.purchaseNumber}',
            'created_at': nowStr,
          });
        }
      } else {
        if (purchase.cgstPaise > 0) {
          final cgstAccountId = await _ensureAccount(
            txn,
            businessId: purchase.businessId,
            code: '2310',
            name: 'Input CGST Credit',
            type: 'ASSET',
          );
          await txn.insert('ledger_entries', {
            'id': _uuid.v4(),
            'business_id': purchase.businessId,
            'account_id': cgstAccountId,
            'transaction_id': purchase.id,
            'transaction_type': 'PURCHASE',
            'entry_date': dateStr,
            'debit_paise': purchase.cgstPaise,
            'credit_paise': 0,
            'description': 'Input CGST Credit on ${purchase.purchaseNumber}',
            'created_at': nowStr,
          });
        }

        if (purchase.sgstPaise > 0) {
          final sgstAccountId = await _ensureAccount(
            txn,
            businessId: purchase.businessId,
            code: '2320',
            name: 'Input SGST Credit',
            type: 'ASSET',
          );
          await txn.insert('ledger_entries', {
            'id': _uuid.v4(),
            'business_id': purchase.businessId,
            'account_id': sgstAccountId,
            'transaction_id': purchase.id,
            'transaction_type': 'PURCHASE',
            'entry_date': dateStr,
            'debit_paise': purchase.sgstPaise,
            'credit_paise': 0,
            'description': 'Input SGST Credit on ${purchase.purchaseNumber}',
            'created_at': nowStr,
          });
        }
      }
    } else {
      // Ineligible ITC debited to blocked tax account (2340)
      final totalIneligibleTax = purchase.cgstPaise + purchase.sgstPaise + purchase.igstPaise;
      if (totalIneligibleTax > 0) {
        final ineligibleTaxAccountId = await _ensureAccount(
          txn,
          businessId: purchase.businessId,
          code: '2340',
          name: 'Ineligible Input Tax',
          type: 'EXPENSE',
        );
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': purchase.businessId,
          'account_id': ineligibleTaxAccountId,
          'transaction_id': purchase.id,
          'transaction_type': 'PURCHASE',
          'entry_date': dateStr,
          'debit_paise': totalIneligibleTax,
          'credit_paise': 0,
          'description': 'Ineligible ITC on ${purchase.purchaseNumber}',
          'created_at': nowStr,
        });
      }
    }

    // 3. Credit: Supplier Accounts Payable (2100) for grand total
    final payableAccountId = await _ensureAccount(
      txn,
      businessId: purchase.businessId,
      code: '2100',
      name: 'Accounts Payable (Creditors)',
      type: 'LIABILITY',
    );
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': purchase.businessId,
      'account_id': payableAccountId,
      'transaction_id': purchase.id,
      'transaction_type': 'PURCHASE',
      'entry_date': dateStr,
      'debit_paise': 0,
      'credit_paise': purchase.totalAmountPaise,
      'description': 'Accounts payable on purchase ${purchase.purchaseNumber}',
      'created_at': nowStr,
    });

    // 4. Round-off account
    if (purchase.roundOffPaise != 0) {
      final roundOffAccountId = await _ensureAccount(
        txn,
        businessId: purchase.businessId,
        code: '5200',
        name: 'Round-Off Account',
        type: 'EXPENSE',
      );

      if (purchase.roundOffPaise > 0) {
        // Round-off added: Debit Round-Off
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': purchase.businessId,
          'account_id': roundOffAccountId,
          'transaction_id': purchase.id,
          'transaction_type': 'PURCHASE',
          'entry_date': dateStr,
          'debit_paise': purchase.roundOffPaise,
          'credit_paise': 0,
          'description': 'Round-off expense on ${purchase.purchaseNumber}',
          'created_at': nowStr,
        });
      } else {
        // Round-off deducted: Credit Round-Off
        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': purchase.businessId,
          'account_id': roundOffAccountId,
          'transaction_id': purchase.id,
          'transaction_type': 'PURCHASE',
          'entry_date': dateStr,
          'debit_paise': 0,
          'credit_paise': purchase.roundOffPaise.abs(),
          'description': 'Round-off concession on ${purchase.purchaseNumber}',
          'created_at': nowStr,
        });
      }
    }
  }

  Future<void> _postPurchaseReturnLedgerEntries(
    Transaction txn, {
    required PurchaseReturn purchaseReturn,
    required Purchase originalPurchase,
    required DateTime now,
  }) async {
    final dateStr = purchaseReturn.returnDate.toIso8601String().substring(0, 10);
    final nowStr = now.toIso8601String();

    // 1. Debit: Supplier Accounts Payable (2100) [Total Return Amount]
    final payableAccountId = await _ensureAccount(
      txn,
      businessId: purchaseReturn.businessId,
      code: '2100',
      name: 'Accounts Payable (Creditors)',
      type: 'LIABILITY',
    );
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': purchaseReturn.businessId,
      'account_id': payableAccountId,
      'transaction_id': purchaseReturn.id,
      'transaction_type': 'PURCHASE_RETURN',
      'entry_date': dateStr,
      'debit_paise': purchaseReturn.totalAmountPaise,
      'credit_paise': 0,
      'description': 'Payable reduction via Debit Note ${purchaseReturn.returnNumber}',
      'created_at': nowStr,
    });

    // 2. Credit: Inventory (1200) [Taxable Return Amount]
    final inventoryAccountId = await _ensureAccount(
      txn,
      businessId: purchaseReturn.businessId,
      code: '1200',
      name: 'Inventory Stock Value',
      type: 'ASSET',
    );
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': purchaseReturn.businessId,
      'account_id': inventoryAccountId,
      'transaction_id': purchaseReturn.id,
      'transaction_type': 'PURCHASE_RETURN',
      'entry_date': dateStr,
      'debit_paise': 0,
      'credit_paise': purchaseReturn.taxableAmountPaise,
      'description': 'Inventory return on Debit Note ${purchaseReturn.returnNumber}',
      'created_at': nowStr,
    });

    // 3. Credit: Input GST Reversal
    if (purchaseReturn.igstPaise > 0) {
      final igstAccountId = await _ensureAccount(
        txn,
        businessId: purchaseReturn.businessId,
        code: '2330',
        name: 'Input IGST Credit',
        type: 'ASSET',
      );
      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': purchaseReturn.businessId,
        'account_id': igstAccountId,
        'transaction_id': purchaseReturn.id,
        'transaction_type': 'PURCHASE_RETURN',
        'entry_date': dateStr,
        'debit_paise': 0,
        'credit_paise': purchaseReturn.igstPaise,
        'description': 'Reversal of Input IGST on ${purchaseReturn.returnNumber}',
        'created_at': nowStr,
      });
    }

    if (purchaseReturn.cgstPaise > 0) {
      final cgstAccountId = await _ensureAccount(
        txn,
        businessId: purchaseReturn.businessId,
        code: '2310',
        name: 'Input CGST Credit',
        type: 'ASSET',
      );
      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': purchaseReturn.businessId,
        'account_id': cgstAccountId,
        'transaction_id': purchaseReturn.id,
        'transaction_type': 'PURCHASE_RETURN',
        'entry_date': dateStr,
        'debit_paise': 0,
        'credit_paise': purchaseReturn.cgstPaise,
        'description': 'Reversal of Input CGST on ${purchaseReturn.returnNumber}',
        'created_at': nowStr,
      });
    }

    if (purchaseReturn.sgstPaise > 0) {
      final sgstAccountId = await _ensureAccount(
        txn,
        businessId: purchaseReturn.businessId,
        code: '2320',
        name: 'Input SGST Credit',
        type: 'ASSET',
      );
      await txn.insert('ledger_entries', {
        'id': _uuid.v4(),
        'business_id': purchaseReturn.businessId,
        'account_id': sgstAccountId,
        'transaction_id': purchaseReturn.id,
        'transaction_type': 'PURCHASE_RETURN',
        'entry_date': dateStr,
        'debit_paise': 0,
        'credit_paise': purchaseReturn.sgstPaise,
        'description': 'Reversal of Input SGST on ${purchaseReturn.returnNumber}',
        'created_at': nowStr,
      });
    }
  }

  Future<String> _ensureAccount(
    Transaction txn, {
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

  Future<String> _allocateNextPurchaseNumber(
    Transaction txn,
    String businessId,
    DateTime date,
  ) async {
    final fiscalYear = _calculateFiscalYear(date);
    final rows = await txn.query(
      'invoice_sequences',
      where: 'business_id = ? AND document_type = ? AND fiscal_year = ?',
      whereArgs: [businessId, 'PURCHASE', fiscalYear],
      limit: 1,
    );

    final nowStr = DateTime.now().toUtc().toIso8601String();
    int currentNum = 0;
    String prefix = 'PUR-$fiscalYear-';
    int padding = 4;
    String sequenceId = '';

    if (rows.isNotEmpty) {
      final row = rows.first;
      sequenceId = row['id'] as String;
      currentNum = (row['current_number'] as num? ?? 0).toInt();
      prefix = row['prefix'] as String? ?? prefix;
      padding = (row['padding_zeros'] as num? ?? 4).toInt();
    } else {
      sequenceId = _uuid.v4();
      await txn.insert('invoice_sequences', {
        'id': sequenceId,
        'business_id': businessId,
        'document_type': 'PURCHASE',
        'prefix': prefix,
        'current_number': 0,
        'padding_zeros': padding,
        'fiscal_year': fiscalYear,
        'created_at': nowStr,
        'updated_at': nowStr,
      });
    }

    final nextNum = currentNum + 1;
    await txn.update(
      'invoice_sequences',
      {
        'current_number': nextNum,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [sequenceId],
    );

    return '$prefix${nextNum.toString().padLeft(padding, '0')}';
  }

  Future<String> _allocateNextDebitNoteNumber(
    Transaction txn,
    String businessId,
    DateTime date,
  ) async {
    final fiscalYear = _calculateFiscalYear(date);
    final rows = await txn.query(
      'invoice_sequences',
      where: 'business_id = ? AND document_type = ? AND fiscal_year = ?',
      whereArgs: [businessId, 'DEBIT_NOTE', fiscalYear],
      limit: 1,
    );

    final nowStr = DateTime.now().toUtc().toIso8601String();
    int currentNum = 0;
    String prefix = 'DN-$fiscalYear-';
    int padding = 4;
    String sequenceId = '';

    if (rows.isNotEmpty) {
      final row = rows.first;
      sequenceId = row['id'] as String;
      currentNum = (row['current_number'] as num? ?? 0).toInt();
      prefix = row['prefix'] as String? ?? prefix;
      padding = (row['padding_zeros'] as num? ?? 4).toInt();
    } else {
      sequenceId = _uuid.v4();
      await txn.insert('invoice_sequences', {
        'id': sequenceId,
        'business_id': businessId,
        'document_type': 'DEBIT_NOTE',
        'prefix': prefix,
        'current_number': 0,
        'padding_zeros': padding,
        'fiscal_year': fiscalYear,
        'created_at': nowStr,
        'updated_at': nowStr,
      });
    }

    final nextNum = currentNum + 1;
    await txn.update(
      'invoice_sequences',
      {
        'current_number': nextNum,
        'updated_at': nowStr,
      },
      where: 'id = ?',
      whereArgs: [sequenceId],
    );

    return '$prefix${nextNum.toString().padLeft(padding, '0')}';
  }

  String _calculateFiscalYear(DateTime date) {
    final year = date.month >= 4 ? date.year : date.year - 1;
    final nextYear = (year + 1) % 100;
    return '$year-${nextYear.toString().padLeft(2, '0')}';
  }

  @override
  Future<PurchaseReturn> recordReturn(PurchaseReturn purchaseReturn) => createReturn(purchaseReturn);

  @override
  Future<int> countPurchases({
    required String businessId,
    PurchaseStatus? status,
    String? supplierId,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) => getPurchasesCount(
    businessId: businessId,
    status: status,
    supplierId: supplierId,
    searchQuery: searchQuery,
    startDate: startDate,
    endDate: endDate,
  );

  @override
  Future<bool> checkDuplicateSupplierInvoice({
    required String businessId,
    required String supplierId,
    required String supplierInvoiceNumber,
    String? excludePurchaseId,
  }) => isSupplierInvoiceDuplicate(
    businessId,
    supplierId,
    supplierInvoiceNumber,
    excludePurchaseId: excludePurchaseId,
  );

  @override
  Future<SupplierAccountsPayableSummary> getSupplierAccountsPayableSummary(
    String businessId,
    String supplierId,
  ) => getSupplierSummary(businessId, supplierId);
}
