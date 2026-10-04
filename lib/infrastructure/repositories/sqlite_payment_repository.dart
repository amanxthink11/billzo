import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/payment/cash_bank_account.dart';
import 'package:billzo/domain/payment/payment.dart';
import 'package:billzo/domain/payment/payment_allocation.dart';
import 'package:billzo/domain/payment/payment_method.dart';
import 'package:billzo/domain/payment/payment_repository.dart';
import 'package:billzo/domain/payment/payment_status.dart';
import 'package:billzo/domain/payment/payment_validator.dart';
import 'package:billzo/domain/purchase/purchase.dart';
import 'package:billzo/domain/purchase/purchase_status.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite production implementation of [IPaymentRepository] with transactional integrity.
class SqlitePaymentRepository implements IPaymentRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();
  final Future<void> Function(Transaction txn)? onBeforePostCommitForTesting;

  SqlitePaymentRepository(
    this._dbHelper, {
    this.onBeforePostCommitForTesting,
  });

  @override
  Future<Payment> createDraft(Payment payment) async {
    final validation = PaymentValidator.validate(payment);
    if (validation.hasErrors && validation.errors.containsKey('amount')) {
      throw ArgumentError(validation.firstError);
    }

    final id = payment.id.isEmpty ? _uuid.v4() : payment.id;
    final now = DateTime.now().toUtc();
    final toSave = payment.copyWith(
      id: id,
      paymentNumber: 'DRAFT',
      status: PaymentStatus.draft,
      createdAt: now,
      updatedAt: now,
    );

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert(
        'payments',
        toSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Save allocations if any
      await txn.delete('payment_allocations', where: 'payment_id = ?', whereArgs: [id]);
      for (final alloc in toSave.allocations) {
        final allocId = alloc.id.isEmpty ? _uuid.v4() : alloc.id;
        await txn.insert('payment_allocations', {
          'id': allocId,
          'payment_id': id,
          'document_id': alloc.documentId,
          'document_type': alloc.documentType,
          'allocated_amount_paise': alloc.allocatedAmountPaise,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
    });

    final saved = await getPaymentById(id);
    return saved!;
  }

  @override
  Future<Payment> updateDraft(Payment payment) async {
    final existing = await getPaymentById(payment.id);
    if (existing == null) {
      throw StateError('Payment ${payment.id} does not exist to update.');
    }
    if (existing.status != PaymentStatus.draft) {
      throw StateError('Cannot update posted payment ${existing.paymentNumber}. Only drafts can be modified.');
    }

    final now = DateTime.now().toUtc();
    final toSave = payment.copyWith(updatedAt: now);

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'payments',
        toSave.toMap(),
        where: 'id = ?',
        whereArgs: [payment.id],
      );

      await txn.delete('payment_allocations', where: 'payment_id = ?', whereArgs: [payment.id]);
      for (final alloc in toSave.allocations) {
        final allocId = alloc.id.isEmpty ? _uuid.v4() : alloc.id;
        await txn.insert('payment_allocations', {
          'id': allocId,
          'payment_id': payment.id,
          'document_id': alloc.documentId,
          'document_type': alloc.documentType,
          'allocated_amount_paise': alloc.allocatedAmountPaise,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
    });

    final updated = await getPaymentById(payment.id);
    return updated!;
  }

  @override
  Future<void> deleteDraft(String paymentId) async {
    final existing = await getPaymentById(paymentId);
    if (existing == null) return;
    if (existing.status != PaymentStatus.draft) {
      throw StateError('Cannot delete non-draft payment ${existing.paymentNumber}.');
    }

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('payment_allocations', where: 'payment_id = ?', whereArgs: [paymentId]);
      await txn.delete('payments', where: 'id = ?', whereArgs: [paymentId]);
    });
  }

  @override
  Future<Payment?> getPaymentById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
             COALESCE(c.name, s.name) as customer_name,
             COALESCE(c.phone, s.phone) as customer_phone,
             s.name as supplier_name,
             a.name as account_name
      FROM payments p
      LEFT JOIN customers c ON p.party_id = c.id AND p.party_type = 'CUSTOMER'
      LEFT JOIN suppliers s ON p.party_id = s.id AND p.party_type = 'SUPPLIER'
      LEFT JOIN cash_bank_accounts a ON p.account_id = a.id
      WHERE p.id = ?
      LIMIT 1
    ''', [id]);

    if (rows.isEmpty) return null;

    final allocRows = await db.rawQuery('''
      SELECT pa.*,
             COALESCE(i.invoice_number, pur.purchase_number) as invoice_number,
             COALESCE(i.invoice_date, pur.purchase_date) as invoice_date,
             COALESCE(i.total_amount_paise, pur.total_amount_paise) as invoice_total_paise,
             COALESCE(i.balance_amount_paise, pur.balance_amount_paise) as invoice_outstanding_before_paise
      FROM payment_allocations pa
      LEFT JOIN invoices i ON pa.document_id = i.id AND pa.document_type = 'INVOICE'
      LEFT JOIN purchases pur ON pa.document_id = pur.id AND pa.document_type = 'PURCHASE'
      WHERE pa.payment_id = ?
      ORDER BY pa.created_at ASC
    ''', [id]);

    final allocations = allocRows.map(PaymentAllocation.fromMap).toList();
    return Payment.fromMap(rows.first, allocations: allocations);
  }

  @override
  Future<List<Payment>> getPayments({
    required String businessId,
    String? customerId,
    String? supplierId,
    PaymentStatus? status,
    PaymentMethod? method,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    final q = _buildPaymentQuery(
      businessId: businessId,
      customerId: customerId,
      supplierId: supplierId,
      status: status,
      method: method,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
    );

    final sql = '''
      SELECT p.*,
             COALESCE(c.name, s.name) as customer_name,
             COALESCE(c.phone, s.phone) as customer_phone,
             s.name as supplier_name,
             a.name as account_name
      FROM payments p
      LEFT JOIN customers c ON p.party_id = c.id AND p.party_type = 'CUSTOMER'
      LEFT JOIN suppliers s ON p.party_id = s.id AND p.party_type = 'SUPPLIER'
      LEFT JOIN cash_bank_accounts a ON p.account_id = a.id
      WHERE ${q.whereClause}
      ORDER BY p.payment_date DESC, p.created_at DESC
      LIMIT ? OFFSET ?
    ''';

    final args = [...q.whereArgs, limit, offset];
    final rows = await db.rawQuery(sql, args);

    if (rows.isEmpty) return [];

    final paymentIds = rows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(paymentIds.length, '?').join(',');

    final allocRows = await db.rawQuery('''
      SELECT pa.*,
             COALESCE(i.invoice_number, pur.purchase_number) as invoice_number,
             COALESCE(i.invoice_date, pur.purchase_date) as invoice_date,
             COALESCE(i.total_amount_paise, pur.total_amount_paise) as invoice_total_paise,
             COALESCE(i.balance_amount_paise, pur.balance_amount_paise) as invoice_outstanding_before_paise
      FROM payment_allocations pa
      LEFT JOIN invoices i ON pa.document_id = i.id AND pa.document_type = 'INVOICE'
      LEFT JOIN purchases pur ON pa.document_id = pur.id AND pa.document_type = 'PURCHASE'
      WHERE pa.payment_id IN ($placeholders)
      ORDER BY pa.created_at ASC
    ''', paymentIds);

    final allocMap = <String, List<PaymentAllocation>>{};
    for (final a in allocRows) {
      final pid = a['payment_id'] as String;
      allocMap.putIfAbsent(pid, () => []).add(PaymentAllocation.fromMap(a));
    }

    return rows.map((r) {
      final pid = r['id'] as String;
      return Payment.fromMap(r, allocations: allocMap[pid] ?? const []);
    }).toList();
  }

  @override
  Future<int> getPaymentsCount({
    required String businessId,
    String? customerId,
    String? supplierId,
    PaymentStatus? status,
    PaymentMethod? method,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) async {
    final db = await _dbHelper.database;
    final q = _buildPaymentQuery(
      businessId: businessId,
      customerId: customerId,
      supplierId: supplierId,
      status: status,
      method: method,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
    );

    final sql = '''
      SELECT COUNT(*) as total_count
      FROM payments p
      LEFT JOIN customers c ON p.party_id = c.id AND p.party_type = 'CUSTOMER'
      LEFT JOIN suppliers s ON p.party_id = s.id AND p.party_type = 'SUPPLIER'
      WHERE ${q.whereClause}
    ''';

    final rows = await db.rawQuery(sql, q.whereArgs);
    if (rows.isEmpty) return 0;
    return (rows.first['total_count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<Payment> postPayment(Payment payment) async {
    // 1. Strict domain-level validation
    final validation = PaymentValidator.validate(payment);
    if (validation.hasErrors) {
      throw ArgumentError(validation.firstError);
    }

    final id = payment.id.isEmpty ? _uuid.v4() : payment.id;
    final now = DateTime.now().toUtc();
    final dateStr = payment.paymentDate.toIso8601String().substring(0, 10);
    final nowStr = now.toIso8601String();

    await _dbHelper.transaction((txn) async {
      // 2. Resolve Cash / Bank Account
      String resolvedAccountId;
      if (payment.accountId != null && payment.accountId!.isNotEmpty) {
        resolvedAccountId = payment.accountId!;
      } else {
        // Find or create default cash or bank account matching the payment method
        final targetType = payment.paymentMethod == PaymentMethod.cash
            ? CashBankAccountType.cash
            : CashBankAccountType.bank;
        resolvedAccountId = await _ensureDefaultCashBankAccount(
          txn,
          businessId: payment.businessId,
          type: targetType,
          nowStr: nowStr,
        );
      }

      // 3. Generate statutory payment sequence number atomically
      final allocatedPaymentNumber = await _allocatePaymentNumber(
        txn,
        businessId: payment.businessId,
        date: payment.paymentDate,
      );

      if (payment.isSupplierPayment) {
        // ==================== SUPPLIER PAYMENT FLOW ====================
        // Validate supplier exists
        final supplierRows = await txn.query(
          'suppliers',
          where: 'id = ? AND business_id = ?',
          whereArgs: [payment.partyId, payment.businessId],
          limit: 1,
        );
        if (supplierRows.isEmpty) {
          throw StateError('Supplier ${payment.partyId} does not exist.');
        }
        final supplierName = supplierRows.first['name'] as String? ?? 'Supplier';

        // Validate allocations against target purchases
        for (final alloc in payment.allocations) {
          final purRows = await txn.query(
            'purchases',
            where: 'id = ? AND business_id = ?',
            whereArgs: [alloc.documentId, payment.businessId],
            limit: 1,
          );
          if (purRows.isEmpty) {
            throw StateError('Purchase ${alloc.documentId} not found for allocation.');
          }

          final purchase = Purchase.fromMap(purRows.first);
          final allocValidation = PaymentValidator.validateAllocationAgainstPurchase(
            allocation: alloc,
            purchase: purchase,
          );
          if (allocValidation.hasErrors) {
            throw ArgumentError(allocValidation.firstError);
          }
        }

        // Insert / Update payment record
        await txn.delete('payment_allocations', where: 'payment_id = ?', whereArgs: [id]);
        await txn.delete('payments', where: 'id = ?', whereArgs: [id]);

        await txn.insert('payments', {
          'id': id,
          'business_id': payment.businessId,
          'party_id': payment.partyId,
          'party_type': 'SUPPLIER',
          'payment_type': 'PAYMENT',
          'payment_number': allocatedPaymentNumber,
          'payment_date': dateStr,
          'payment_mode': payment.paymentMethod.dbValue,
          'amount_paise': payment.amountPaise,
          'account_id': resolvedAccountId,
          'reference_number': payment.referenceNumber,
          'notes': payment.notes,
          'status': PaymentStatus.posted.dbValue,
          'created_at': nowStr,
          'updated_at': nowStr,
          'sync_version': 1,
          'sync_status': 'synced',
        });

        // Insert allocations and update purchase balances and statuses
        for (final alloc in payment.allocations) {
          final allocId = alloc.id.isEmpty ? _uuid.v4() : alloc.id;
          await txn.insert('payment_allocations', {
            'id': allocId,
            'payment_id': id,
            'document_id': alloc.documentId,
            'document_type': 'PURCHASE',
            'allocated_amount_paise': alloc.allocatedAmountPaise,
            'created_at': nowStr,
            'updated_at': nowStr,
          });

          // Update target purchase
          final purRows = await txn.query(
            'purchases',
            columns: ['paid_amount_paise', 'total_amount_paise', 'balance_amount_paise'],
            where: 'id = ?',
            whereArgs: [alloc.documentId],
            limit: 1,
          );
          if (purRows.isNotEmpty) {
            final oldPaid = (purRows.first['paid_amount_paise'] as num? ?? 0).toInt();
            final total = (purRows.first['total_amount_paise'] as num? ?? 0).toInt();
            final newPaid = oldPaid + alloc.allocatedAmountPaise;
            final newBalance = total - newPaid;
            final newStatus = newBalance <= 0 ? PurchaseStatus.paid : PurchaseStatus.partiallyPaid;

            await txn.update(
              'purchases',
              {
                'paid_amount_paise': newPaid,
                'balance_amount_paise': newBalance,
                'status': newStatus.dbValue,
                'updated_at': nowStr,
              },
              where: 'id = ?',
              whereArgs: [alloc.documentId],
            );
          }
        }

        // Post supplier double-entry accounting (Debit Accounts Payable 2100, Credit Cash/Bank 1010/1020)
        await _postSupplierPaymentLedgerEntries(
          txn,
          paymentId: id,
          paymentNumber: allocatedPaymentNumber,
          businessId: payment.businessId,
          supplierName: supplierName,
          paymentMethod: payment.paymentMethod,
          amountPaise: payment.amountPaise,
          dateStr: dateStr,
          nowStr: nowStr,
        );

        // Update Cash / Bank Account current balance (Cash/Bank decreases)
        final accountRows = await txn.query(
          'cash_bank_accounts',
          columns: ['current_balance_paise'],
          where: 'id = ?',
          whereArgs: [resolvedAccountId],
          limit: 1,
        );
        if (accountRows.isNotEmpty) {
          final currentBal = (accountRows.first['current_balance_paise'] as num? ?? 0).toInt();
          await txn.update(
            'cash_bank_accounts',
            {
              'current_balance_paise': currentBal - payment.amountPaise,
              'updated_at': nowStr,
            },
            where: 'id = ?',
            whereArgs: [resolvedAccountId],
          );
        }

        // Update Supplier Outstanding Balance (Decreases payable liability)
        final suppBal = (supplierRows.first['current_balance_paise'] as num? ?? 0).toInt();
        await txn.update(
          'suppliers',
          {
            'current_balance_paise': suppBal - payment.amountPaise,
            'updated_at': nowStr,
          },
          where: 'id = ?',
          whereArgs: [payment.partyId],
        );

        // Record audit log
        await txn.insert('audit_logs', {
          'id': _uuid.v4(),
          'business_id': payment.businessId,
          'entity_name': 'PAYMENT',
          'entity_id': id,
          'action': 'POST',
          'user_identifier': 'Local Merchant',
          'details_json':
              'Posted supplier payment $allocatedPaymentNumber for ₹${(payment.amountPaise / 100.0).toStringAsFixed(2)} to $supplierName',
          'timestamp': nowStr,
        });
      } else {
        // ==================== CUSTOMER RECEIPT FLOW ====================
        // Validate customer exists
        final customerRows = await txn.query(
          'customers',
          where: 'id = ? AND business_id = ?',
          whereArgs: [payment.customerId, payment.businessId],
          limit: 1,
        );
        if (customerRows.isEmpty) {
          throw StateError('Customer ${payment.customerId} does not exist.');
        }
        final customerName = customerRows.first['name'] as String? ?? 'Customer';

        // Validate allocations against target invoices
        for (final alloc in payment.allocations) {
          final invRows = await txn.query(
            'invoices',
            where: 'id = ? AND business_id = ?',
            whereArgs: [alloc.documentId, payment.businessId],
            limit: 1,
          );
          if (invRows.isEmpty) {
            throw StateError('Invoice ${alloc.documentId} not found for allocation.');
          }

          final invoice = Invoice.fromMap(invRows.first);
          final allocValidation = PaymentValidator.validateAllocationAgainstInvoice(
            allocation: alloc,
            invoice: invoice,
          );
          if (allocValidation.hasErrors) {
            throw ArgumentError(allocValidation.firstError);
          }
        }

        // Insert / Update payment record
        await txn.delete('payment_allocations', where: 'payment_id = ?', whereArgs: [id]);
        await txn.delete('payments', where: 'id = ?', whereArgs: [id]);

        await txn.insert('payments', {
          'id': id,
          'business_id': payment.businessId,
          'party_id': payment.customerId,
          'party_type': 'CUSTOMER',
          'payment_type': 'RECEIPT',
          'payment_number': allocatedPaymentNumber,
          'payment_date': dateStr,
          'payment_mode': payment.paymentMethod.dbValue,
          'amount_paise': payment.amountPaise,
          'account_id': resolvedAccountId,
          'reference_number': payment.referenceNumber,
          'notes': payment.notes,
          'status': PaymentStatus.posted.dbValue,
          'created_at': nowStr,
          'updated_at': nowStr,
          'sync_version': 1,
          'sync_status': 'synced',
        });

        // Insert allocations and atomically update invoice balances and statuses
        for (final alloc in payment.allocations) {
          final allocId = alloc.id.isEmpty ? _uuid.v4() : alloc.id;
          await txn.insert('payment_allocations', {
            'id': allocId,
            'payment_id': id,
            'document_id': alloc.documentId,
            'document_type': alloc.documentType,
            'allocated_amount_paise': alloc.allocatedAmountPaise,
            'created_at': nowStr,
            'updated_at': nowStr,
          });

          // Update target invoice
          final invRows = await txn.query(
            'invoices',
            columns: ['paid_amount_paise', 'total_amount_paise', 'balance_amount_paise'],
            where: 'id = ?',
            whereArgs: [alloc.documentId],
            limit: 1,
          );
          if (invRows.isNotEmpty) {
            final oldPaid = (invRows.first['paid_amount_paise'] as num? ?? 0).toInt();
            final total = (invRows.first['total_amount_paise'] as num? ?? 0).toInt();
            final newPaid = oldPaid + alloc.allocatedAmountPaise;
            final newBalance = total - newPaid;
            final newStatus = newBalance <= 0 ? InvoiceStatus.paid : InvoiceStatus.partiallyPaid;

            await txn.update(
              'invoices',
              {
                'paid_amount_paise': newPaid,
                'balance_amount_paise': newBalance,
                'status': newStatus.dbValue,
                'updated_at': nowStr,
              },
              where: 'id = ?',
              whereArgs: [alloc.documentId],
            );
          }
        }

        // Post double-entry accounting entries into ledger_entries (Debit Cash/Bank 1010/1020, Credit Accounts Receivable 1100)
        await _postPaymentLedgerEntries(
          txn,
          paymentId: id,
          paymentNumber: allocatedPaymentNumber,
          businessId: payment.businessId,
          customerName: customerName,
          paymentMethod: payment.paymentMethod,
          amountPaise: payment.amountPaise,
          dateStr: dateStr,
          nowStr: nowStr,
        );

        // Update Cash / Bank Account current balance (Cash/Bank increases)
        final accountRows = await txn.query(
          'cash_bank_accounts',
          columns: ['current_balance_paise'],
          where: 'id = ?',
          whereArgs: [resolvedAccountId],
          limit: 1,
        );
        if (accountRows.isNotEmpty) {
          final currentBal = (accountRows.first['current_balance_paise'] as num? ?? 0).toInt();
          await txn.update(
            'cash_bank_accounts',
            {
              'current_balance_paise': currentBal + payment.amountPaise,
              'updated_at': nowStr,
            },
            where: 'id = ?',
            whereArgs: [resolvedAccountId],
          );
        }

        // Update Customer Outstanding Balance (Credit reduces customer receivable)
        final custBal = (customerRows.first['current_balance_paise'] as num? ?? 0).toInt();
        await txn.update(
          'customers',
          {
            'current_balance_paise': custBal - payment.amountPaise,
            'updated_at': nowStr,
          },
          where: 'id = ?',
          whereArgs: [payment.customerId],
        );

        // Record audit log
        await txn.insert('audit_logs', {
          'id': _uuid.v4(),
          'business_id': payment.businessId,
          'entity_name': 'PAYMENT',
          'entity_id': id,
          'action': 'POST',
          'user_identifier': 'Local Merchant',
          'details_json':
              'Posted payment $allocatedPaymentNumber for ₹${(payment.amountPaise / 100.0).toStringAsFixed(2)} from $customerName',
          'timestamp': nowStr,
        });
      }

      if (onBeforePostCommitForTesting != null) {
        await onBeforePostCommitForTesting!(txn);
      }
    });

    final result = await getPaymentById(id);
    return result!;
  }

  @override
  Future<Payment> cancelPayment(String paymentId, {required String cancellationReason}) async {
    final existing = await getPaymentById(paymentId);
    if (existing == null) {
      throw StateError('Payment $paymentId not found to cancel.');
    }
    if (existing.status != PaymentStatus.posted) {
      throw StateError(
        'Only posted payments can be cancelled. Current status: ${existing.status.displayName}',
      );
    }

    final now = DateTime.now().toUtc();
    final nowStr = now.toIso8601String();
    final dateStr = nowStr.substring(0, 10);

    await _dbHelper.transaction((txn) async {
      // 1. Mark payment as CANCELLED
      await txn.update(
        'payments',
        {
          'status': PaymentStatus.cancelled.dbValue,
          'cancelled_at': nowStr,
          'cancellation_reason': cancellationReason.trim(),
          'updated_at': nowStr,
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      // 2. Reverse allocations
      final allocRows = await txn.query(
        'payment_allocations',
        where: 'payment_id = ?',
        whereArgs: [paymentId],
      );

      if (existing.isSupplierPayment) {
        // Reverse purchase allocations
        for (final alloc in allocRows) {
          final docId = alloc['document_id'] as String;
          final allocatedAmount = (alloc['allocated_amount_paise'] as num? ?? 0).toInt();

          final purRows = await txn.query(
            'purchases',
            columns: ['paid_amount_paise', 'total_amount_paise', 'balance_amount_paise'],
            where: 'id = ?',
            whereArgs: [docId],
            limit: 1,
          );

          if (purRows.isNotEmpty) {
            final oldPaid = (purRows.first['paid_amount_paise'] as num? ?? 0).toInt();
            final total = (purRows.first['total_amount_paise'] as num? ?? 0).toInt();
            final newPaid = oldPaid - allocatedAmount;
            final newBalance = total - newPaid;

            PurchaseStatus newStatus;
            if (newPaid <= 0) {
              newStatus = PurchaseStatus.finalized;
            } else if (newBalance <= 0) {
              newStatus = PurchaseStatus.paid;
            } else {
              newStatus = PurchaseStatus.partiallyPaid;
            }

            await txn.update(
              'purchases',
              {
                'paid_amount_paise': newPaid,
                'balance_amount_paise': newBalance,
                'status': newStatus.dbValue,
                'updated_at': nowStr,
              },
              where: 'id = ?',
              whereArgs: [docId],
            );
          }
        }
      } else {
        // Reverse invoice allocations
        for (final alloc in allocRows) {
          final docId = alloc['document_id'] as String;
          final allocatedAmount = (alloc['allocated_amount_paise'] as num? ?? 0).toInt();

          final invRows = await txn.query(
            'invoices',
            columns: ['paid_amount_paise', 'total_amount_paise', 'balance_amount_paise'],
            where: 'id = ?',
            whereArgs: [docId],
            limit: 1,
          );

          if (invRows.isNotEmpty) {
            final oldPaid = (invRows.first['paid_amount_paise'] as num? ?? 0).toInt();
            final total = (invRows.first['total_amount_paise'] as num? ?? 0).toInt();
            final newPaid = oldPaid - allocatedAmount;
            final newBalance = total - newPaid;

            InvoiceStatus newStatus;
            if (newPaid <= 0) {
              newStatus = InvoiceStatus.finalized;
            } else if (newBalance <= 0) {
              newStatus = InvoiceStatus.paid;
            } else {
              newStatus = InvoiceStatus.partiallyPaid;
            }

            await txn.update(
              'invoices',
              {
                'paid_amount_paise': newPaid,
                'balance_amount_paise': newBalance,
                'status': newStatus.dbValue,
                'updated_at': nowStr,
              },
              where: 'id = ?',
              whereArgs: [docId],
            );
          }
        }
      }

      // 3. Post reversing accounting entries in ledger_entries
      final originalEntries = await txn.query(
        'ledger_entries',
        where: 'transaction_id = ? AND transaction_type = ?',
        whereArgs: [paymentId, 'PAYMENT'],
      );

      for (final entry in originalEntries) {
        final debit = (entry['debit_paise'] as num? ?? 0).toInt();
        final credit = (entry['credit_paise'] as num? ?? 0).toInt();

        await txn.insert('ledger_entries', {
          'id': _uuid.v4(),
          'business_id': existing.businessId,
          'account_id': entry['account_id'],
          'transaction_id': paymentId,
          'transaction_type': 'PAYMENT_CANCELLATION',
          'entry_date': dateStr,
          'debit_paise': credit, // Swapped to reverse
          'credit_paise': debit, // Swapped to reverse
          'description':
              'Reversal of payment ${existing.paymentNumber}: Cancelled ($cancellationReason)',
          'created_at': nowStr,
        });
      }

      // 4. Reverse Cash / Bank Account balance
      if (existing.accountId != null) {
        final accountRows = await txn.query(
          'cash_bank_accounts',
          columns: ['current_balance_paise'],
          where: 'id = ?',
          whereArgs: [existing.accountId],
          limit: 1,
        );
        if (accountRows.isNotEmpty) {
          final currentBal = (accountRows.first['current_balance_paise'] as num? ?? 0).toInt();
          // If supplier payment, money was deducted; reversing means adding back.
          // If customer receipt, money was added; reversing means deducting.
          final newBal = existing.isSupplierPayment
              ? currentBal + existing.amountPaise
              : currentBal - existing.amountPaise;

          await txn.update(
            'cash_bank_accounts',
            {
              'current_balance_paise': newBal,
              'updated_at': nowStr,
            },
            where: 'id = ?',
            whereArgs: [existing.accountId],
          );
        }
      }

      // 5. Restore Customer or Supplier outstanding balance
      if (existing.isSupplierPayment) {
        // Supplier payable was reduced by payment; restoring means adding back.
        final suppRows = await txn.query(
          'suppliers',
          columns: ['current_balance_paise'],
          where: 'id = ?',
          whereArgs: [existing.partyId],
          limit: 1,
        );
        if (suppRows.isNotEmpty) {
          final currentBal = (suppRows.first['current_balance_paise'] as num? ?? 0).toInt();
          await txn.update(
            'suppliers',
            {
              'current_balance_paise': currentBal + existing.amountPaise,
              'updated_at': nowStr,
            },
            where: 'id = ?',
            whereArgs: [existing.partyId],
          );
        }
      } else {
        // Customer receivable was reduced by receipt; restoring means adding back.
        final customerRows = await txn.query(
          'customers',
          columns: ['current_balance_paise'],
          where: 'id = ?',
          whereArgs: [existing.customerId],
          limit: 1,
        );
        if (customerRows.isNotEmpty) {
          final currentBal = (customerRows.first['current_balance_paise'] as num? ?? 0).toInt();
          await txn.update(
            'customers',
            {
              'current_balance_paise': currentBal + existing.amountPaise,
              'updated_at': nowStr,
            },
            where: 'id = ?',
            whereArgs: [existing.customerId],
          );
        }
      }

      // 6. Record audit log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': existing.businessId,
        'entity_name': 'PAYMENT',
        'entity_id': paymentId,
        'action': 'CANCEL',
        'user_identifier': 'Local Merchant',
        'details_json':
            'Cancelled payment ${existing.paymentNumber}. Reason: $cancellationReason',
        'timestamp': nowStr,
      });
    });

    final cancelled = await getPaymentById(paymentId);
    return cancelled!;
  }

  @override
  Future<List<Payment>> getPaymentsForCustomer(String customerId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
             c.name as customer_name,
             c.phone as customer_phone,
             a.name as account_name
      FROM payments p
      LEFT JOIN customers c ON p.party_id = c.id
      LEFT JOIN cash_bank_accounts a ON p.account_id = a.id
      WHERE p.party_id = ?
      ORDER BY p.payment_date DESC, p.created_at DESC
    ''', [customerId]);

    return rows.map((r) => Payment.fromMap(r)).toList();
  }

  @override
  Future<List<Payment>> getPaymentsForInvoice(String invoiceId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
             c.name as customer_name,
             c.phone as customer_phone,
             a.name as account_name
      FROM payments p
      INNER JOIN payment_allocations pa ON p.id = pa.payment_id
      LEFT JOIN customers c ON p.party_id = c.id
      LEFT JOIN cash_bank_accounts a ON p.account_id = a.id
      WHERE pa.document_id = ?
      ORDER BY p.payment_date DESC, p.created_at DESC
    ''', [invoiceId]);

    return rows.map((r) => Payment.fromMap(r)).toList();
  }

  @override
  Future<List<Payment>> getPaymentsForSupplier(String supplierId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
             s.name as supplier_name,
             s.phone as supplier_phone,
             a.name as account_name
      FROM payments p
      LEFT JOIN suppliers s ON p.party_id = s.id
      LEFT JOIN cash_bank_accounts a ON p.account_id = a.id
      WHERE p.party_id = ? AND p.party_type = 'SUPPLIER'
      ORDER BY p.payment_date DESC, p.created_at DESC
    ''', [supplierId]);

    return rows.map((r) => Payment.fromMap(r)).toList();
  }

  @override
  Future<List<Payment>> getPaymentsForPurchase(String purchaseId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
             s.name as supplier_name,
             s.phone as supplier_phone,
             a.name as account_name
      FROM payments p
      INNER JOIN payment_allocations pa ON p.id = pa.payment_id
      LEFT JOIN suppliers s ON p.party_id = s.id
      LEFT JOIN cash_bank_accounts a ON p.account_id = a.id
      WHERE pa.document_id = ? AND pa.document_type = 'PURCHASE'
      ORDER BY p.payment_date DESC, p.created_at DESC
    ''', [purchaseId]);

    return rows.map((r) => Payment.fromMap(r)).toList();
  }

  @override
  Future<List<Invoice>> getOutstandingInvoicesForCustomer(
    String businessId,
    String customerId,
  ) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT i.*,
             c.name as customer_name,
             c.phone as customer_phone,
             c.gstin as customer_gstin,
             c.company_name as customer_company_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE i.business_id = ? 
        AND i.customer_id = ? 
        AND i.status IN ('FINALIZED', 'PARTIAL') 
        AND i.balance_amount_paise > 0
      ORDER BY i.invoice_date ASC, i.created_at ASC
    ''', [businessId, customerId]);

    return rows.map((r) => Invoice.fromMap(r)).toList();
  }

  @override
  Future<List<CashBankAccount>> getCashBankAccounts(String businessId) async {
    final db = await _dbHelper.database;
    // Ensure default accounts exist for this business
    await db.transaction((txn) async {
      await _ensureDefaultCashBankAccount(
        txn,
        businessId: businessId,
        type: CashBankAccountType.cash,
        nowStr: DateTime.now().toUtc().toIso8601String(),
      );
      await _ensureDefaultCashBankAccount(
        txn,
        businessId: businessId,
        type: CashBankAccountType.bank,
        nowStr: DateTime.now().toUtc().toIso8601String(),
      );
    });

    final rows = await db.query(
      'cash_bank_accounts',
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'is_default DESC, name ASC',
    );

    return rows.map(CashBankAccount.fromMap).toList();
  }

  @override
  Future<CashBankAccount?> getCashBankAccountById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'cash_bank_accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CashBankAccount.fromMap(rows.first);
  }

  @override
  Future<CashBankAccount> createCashBankAccount(CashBankAccount account) async {
    final id = account.id.isEmpty ? _uuid.v4() : account.id;
    final now = DateTime.now().toUtc();
    final toInsert = account.copyWith(
      id: id,
      currentBalancePaise: account.openingBalancePaise,
      createdAt: now,
      updatedAt: now,
    );

    final db = await _dbHelper.database;
    await db.insert('cash_bank_accounts', toInsert.toMap());
    return toInsert;
  }

  @override
  Future<CashBankAccount> updateCashBankAccount(CashBankAccount account) async {
    final now = DateTime.now().toUtc();
    final toUpdate = account.copyWith(updatedAt: now);

    final db = await _dbHelper.database;
    await db.update(
      'cash_bank_accounts',
      toUpdate.toMap(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
    return toUpdate;
  }

  @override
  Future<String> getNextPaymentNumberPreview(String businessId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final fiscalYear = _calculateFiscalYear(now);

    final rows = await db.query(
      'invoice_sequences',
      where: 'business_id = ? AND document_type = ? AND fiscal_year = ?',
      whereArgs: [businessId, 'PAYMENT', fiscalYear],
      limit: 1,
    );

    final prefix = rows.isNotEmpty ? rows.first['prefix'] as String : 'PAY-';
    final currentNumber = rows.isNotEmpty ? (rows.first['current_number'] as int) : 0;
    final padding = rows.isNotEmpty ? (rows.first['padding_zeros'] as int) : 4;
    final nextNumber = currentNumber + 1;
    final padded = nextNumber.toString().padLeft(padding, '0');

    return '$prefix$fiscalYear-$padded';
  }

  // --- Internal Helpers ---

  Future<String> _allocatePaymentNumber(
    Transaction txn, {
    required String businessId,
    required DateTime date,
  }) async {
    final fiscalYear = _calculateFiscalYear(date);
    final nowStr = DateTime.now().toUtc().toIso8601String();

    final seqRows = await txn.query(
      'invoice_sequences',
      where: 'business_id = ? AND document_type = ? AND fiscal_year = ?',
      whereArgs: [businessId, 'PAYMENT', fiscalYear],
      limit: 1,
    );

    int nextNum;
    String prefix;
    int padding;

    if (seqRows.isEmpty) {
      prefix = 'PAY-';
      padding = 4;
      nextNum = 1;
      await txn.insert('invoice_sequences', {
        'id': _uuid.v4(),
        'business_id': businessId,
        'document_type': 'PAYMENT',
        'prefix': prefix,
        'current_number': nextNum,
        'padding_zeros': padding,
        'fiscal_year': fiscalYear,
        'created_at': nowStr,
        'updated_at': nowStr,
      });
    } else {
      final row = seqRows.first;
      prefix = row['prefix'] as String;
      padding = row['padding_zeros'] as int;
      final currentNum = row['current_number'] as int;
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
    return '$prefix$fiscalYear-$padded';
  }

  String _calculateFiscalYear(DateTime date) {
    // Indian Fiscal Year: April 1 to March 31
    final year = date.year;
    if (date.month >= 4) {
      final nextYearShort = (year + 1) % 100;
      return '$year-${nextYearShort.toString().padLeft(2, '0')}';
    } else {
      final currYearShort = year % 100;
      return '${year - 1}-${currYearShort.toString().padLeft(2, '0')}';
    }
  }

  Future<String> _ensureDefaultCashBankAccount(
    Transaction txn, {
    required String businessId,
    required CashBankAccountType type,
    required String nowStr,
  }) async {
    final existing = await txn.query(
      'cash_bank_accounts',
      where: 'business_id = ? AND account_type = ?',
      whereArgs: [businessId, type.dbValue],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return existing.first['id'] as String;
    }

    final id = _uuid.v4();
    final name = type == CashBankAccountType.cash ? 'Cash on Hand' : 'Main Bank Account';
    await txn.insert('cash_bank_accounts', {
      'id': id,
      'business_id': businessId,
      'name': name,
      'account_type': type.dbValue,
      'opening_balance_paise': 0,
      'current_balance_paise': 0,
      'is_default': type == CashBankAccountType.cash ? 1 : 0,
      'is_active': 1,
      'created_at': nowStr,
      'updated_at': nowStr,
    });

    return id;
  }

  Future<void> _postPaymentLedgerEntries(
    Transaction txn, {
    required String paymentId,
    required String paymentNumber,
    required String businessId,
    required String customerName,
    required PaymentMethod paymentMethod,
    required int amountPaise,
    required String dateStr,
    required String nowStr,
  }) async {
    // 1. Identify Asset Account: Cash on Hand (1010) or Bank Account (1020)
    final isCash = paymentMethod == PaymentMethod.cash;
    final assetCode = isCash ? '1010' : '1020';
    final assetName = isCash ? 'Cash on Hand' : 'Bank Account';

    final assetAccountId = await _ensureLedgerAccount(
      txn,
      businessId: businessId,
      code: assetCode,
      name: assetName,
      type: 'ASSET',
      nowStr: nowStr,
    );

    // 2. Identify Accounts Receivable Account (1100)
    final receivableAccountId = await _ensureLedgerAccount(
      txn,
      businessId: businessId,
      code: '1100',
      name: 'Accounts Receivable (Debtors)',
      type: 'ASSET',
      nowStr: nowStr,
    );

    // Debit Cash/Bank: Asset increases
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': businessId,
      'account_id': assetAccountId,
      'transaction_id': paymentId,
      'transaction_type': 'PAYMENT',
      'entry_date': dateStr,
      'debit_paise': amountPaise,
      'credit_paise': 0,
      'description': 'Payment receipt $paymentNumber from $customerName via ${paymentMethod.displayName}',
      'created_at': nowStr,
    });

    // Credit Accounts Receivable: Asset decreases
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': businessId,
      'account_id': receivableAccountId,
      'transaction_id': paymentId,
      'transaction_type': 'PAYMENT',
      'entry_date': dateStr,
      'debit_paise': 0,
      'credit_paise': amountPaise,
      'description': 'Customer receivable credited for $customerName ($paymentNumber)',
      'created_at': nowStr,
    });
  }

  Future<void> _postSupplierPaymentLedgerEntries(
    Transaction txn, {
    required String paymentId,
    required String paymentNumber,
    required String businessId,
    required String supplierName,
    required PaymentMethod paymentMethod,
    required int amountPaise,
    required String dateStr,
    required String nowStr,
  }) async {
    // 1. Identify Asset Account: Cash on Hand (1010) or Bank Account (1020)
    final isCash = paymentMethod == PaymentMethod.cash;
    final assetCode = isCash ? '1010' : '1020';
    final assetName = isCash ? 'Cash on Hand' : 'Bank Account';

    final assetAccountId = await _ensureLedgerAccount(
      txn,
      businessId: businessId,
      code: assetCode,
      name: assetName,
      type: 'ASSET',
      nowStr: nowStr,
    );

    // 2. Identify Accounts Payable Account (2100)
    final payableAccountId = await _ensureLedgerAccount(
      txn,
      businessId: businessId,
      code: '2100',
      name: 'Accounts Payable (Creditors)',
      type: 'LIABILITY',
      nowStr: nowStr,
    );

    // Debit Accounts Payable (2100): Liability decreases
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': businessId,
      'account_id': payableAccountId,
      'transaction_id': paymentId,
      'transaction_type': 'PAYMENT',
      'entry_date': dateStr,
      'debit_paise': amountPaise,
      'credit_paise': 0,
      'description': 'Accounts payable cleared for supplier $supplierName ($paymentNumber)',
      'created_at': nowStr,
    });

    // Credit Cash/Bank: Asset decreases
    await txn.insert('ledger_entries', {
      'id': _uuid.v4(),
      'business_id': businessId,
      'account_id': assetAccountId,
      'transaction_id': paymentId,
      'transaction_type': 'PAYMENT',
      'entry_date': dateStr,
      'debit_paise': 0,
      'credit_paise': amountPaise,
      'description': 'Supplier payment $paymentNumber to $supplierName via ${paymentMethod.displayName}',
      'created_at': nowStr,
    });
  }

  Future<String> _ensureLedgerAccount(
    Transaction txn, {
    required String businessId,
    required String code,
    required String name,
    required String type,
    required String nowStr,
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

  _PaymentQueryData _buildPaymentQuery({
    required String businessId,
    String? customerId,
    String? supplierId,
    PaymentStatus? status,
    PaymentMethod? method,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    final StringBuffer whereClause = StringBuffer('p.business_id = ?');
    final List<dynamic> whereArgs = [businessId];

    if (status != null) {
      whereClause.write(' AND p.status = ?');
      whereArgs.add(status.dbValue);
    }

    if (customerId != null && customerId.trim().isNotEmpty) {
      whereClause.write(' AND p.party_id = ? AND p.party_type = ?');
      whereArgs.addAll([customerId, 'CUSTOMER']);
    }

    if (supplierId != null && supplierId.trim().isNotEmpty) {
      whereClause.write(' AND p.party_id = ? AND p.party_type = ?');
      whereArgs.addAll([supplierId, 'SUPPLIER']);
    }

    if (method != null) {
      whereClause.write(' AND p.payment_mode = ?');
      whereArgs.add(method.dbValue);
    }

    if (startDate != null) {
      whereClause.write(' AND p.payment_date >= ?');
      whereArgs.add(startDate.toIso8601String().substring(0, 10));
    }

    if (endDate != null) {
      whereClause.write(' AND p.payment_date <= ?');
      whereArgs.add(endDate.toIso8601String().substring(0, 10));
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      whereClause.write(
        ' AND (p.payment_number LIKE ? OR p.reference_number LIKE ? OR p.notes LIKE ? OR c.name LIKE ? OR c.phone LIKE ? OR s.name LIKE ? OR s.phone LIKE ?)',
      );
      whereArgs.addAll([term, term, term, term, term, term, term]);
    }

    return _PaymentQueryData(whereClause.toString(), whereArgs);
  }
}

class _PaymentQueryData {
  final String whereClause;
  final List<dynamic> whereArgs;
  _PaymentQueryData(this.whereClause, this.whereArgs);
}
