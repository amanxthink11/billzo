import 'package:billzo/core/money/money.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// Single integrity discrepancy or audit finding.
class AccountingIntegrityIssue {
  final String category; // JOURNAL, TRIAL_BALANCE, CASH_BANK, AR, AP, EXPENSE
  final String description;
  final int expectedPaise;
  final int actualPaise;
  final int discrepancyPaise;

  const AccountingIntegrityIssue({
    required this.category,
    required this.description,
    this.expectedPaise = 0,
    this.actualPaise = 0,
    this.discrepancyPaise = 0,
  });

  Money get expected => Money.fromPaise(expectedPaise);
  Money get actual => Money.fromPaise(actualPaise);
  Money get discrepancy => Money.fromPaise(discrepancyPaise.abs());
}

/// Comprehensive audit report exposing accounting integrity across 6 validation checks.
class AccountingIntegrityReport {
  final String businessId;
  final bool journalEntriesBalanced;
  final bool trialBalanceBalanced;
  final bool cashBankReconciled;
  final bool receivablesReconciled;
  final bool payablesReconciled;
  final bool expensesReconciled;
  final List<AccountingIntegrityIssue> issues;
  final DateTime auditedAt;

  const AccountingIntegrityReport({
    required this.businessId,
    required this.journalEntriesBalanced,
    required this.trialBalanceBalanced,
    required this.cashBankReconciled,
    required this.receivablesReconciled,
    required this.payablesReconciled,
    required this.expensesReconciled,
    required this.issues,
    required this.auditedAt,
  });

  /// All 6 verification checks passed with zero discrepancies.
  bool get isClean =>
      journalEntriesBalanced &&
      trialBalanceBalanced &&
      cashBankReconciled &&
      receivablesReconciled &&
      payablesReconciled &&
      expensesReconciled &&
      issues.isEmpty;

  int get totalIssuesCount => issues.length;
}

/// Service that executes formal double-entry accounting integrity checks.
class AccountingIntegrityService {
  final DatabaseHelper _dbHelper;

  AccountingIntegrityService(this._dbHelper);

  /// Runs all 6 integrity verifications without modifying any data.
  Future<AccountingIntegrityReport> runIntegrityAudit(String businessId) async {
    final db = await _dbHelper.database;
    final issues = <AccountingIntegrityIssue>[];

    // 1. Every journal entry balances: sum(debit) == sum(credit) for every transaction_id
    final unbalancedTxns = await db.rawQuery('''
      SELECT transaction_id, transaction_type,
             COALESCE(SUM(debit_paise), 0) as total_debit,
             COALESCE(SUM(credit_paise), 0) as total_credit
      FROM ledger_entries
      WHERE business_id = ?
      GROUP BY transaction_id, transaction_type
      HAVING total_debit != total_credit
    ''', [businessId]);

    final journalEntriesBalanced = unbalancedTxns.isEmpty;
    for (final row in unbalancedTxns) {
      final txId = row['transaction_id'] as String;
      final txType = row['transaction_type'] as String;
      final deb = (row['total_debit'] as num? ?? 0).toInt();
      final cred = (row['total_credit'] as num? ?? 0).toInt();
      final diff = (deb - cred).abs();

      issues.add(
        AccountingIntegrityIssue(
          category: 'JOURNAL',
          description: 'Unbalanced journal entry in $txType transaction $txId (Debits: ₹${(deb / 100).toStringAsFixed(2)}, Credits: ₹${(cred / 100).toStringAsFixed(2)})',
          expectedPaise: deb,
          actualPaise: cred,
          discrepancyPaise: diff,
        ),
      );
    }

    // 2. Trial Balance debits equal credits
    final tbRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(debit_paise), 0) as sum_debit,
        COALESCE(SUM(credit_paise), 0) as sum_credit
      FROM ledger_entries
      WHERE business_id = ?
    ''', [businessId]);

    final tbDebits = tbRows.isNotEmpty ? (tbRows.first['sum_debit'] as num? ?? 0).toInt() : 0;
    final tbCredits = tbRows.isNotEmpty ? (tbRows.first['sum_credit'] as num? ?? 0).toInt() : 0;
    final trialBalanceBalanced = tbDebits == tbCredits;

    if (!trialBalanceBalanced) {
      issues.add(
        AccountingIntegrityIssue(
          category: 'TRIAL_BALANCE',
          description: 'Trial Balance debits (₹${(tbDebits / 100).toStringAsFixed(2)}) do not equal credits (₹${(tbCredits / 100).toStringAsFixed(2)})',
          expectedPaise: tbDebits,
          actualPaise: tbCredits,
          discrepancyPaise: (tbDebits - tbCredits).abs(),
        ),
      );
    }

    // 3. Cash/bank balances agree with ledger postings
    // Sum of cash_bank_accounts current_balance vs net debits of 1010 + 1020
    final cashBankRows = await db.rawQuery('''
      SELECT COALESCE(SUM(current_balance_paise), 0) as total_cash_bank
      FROM cash_bank_accounts
      WHERE business_id = ? AND is_active = 1 AND deleted_at IS NULL
    ''', [businessId]);
    final totalCashBank = cashBankRows.isNotEmpty ? (cashBankRows.first['total_cash_bank'] as num? ?? 0).toInt() : 0;

    final ledgerCashRows = await db.rawQuery('''
      SELECT COALESCE(SUM(le.debit_paise), 0) - COALESCE(SUM(le.credit_paise), 0) as net_ledger_cash
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.code IN ('1010', '1020')
    ''', [businessId]);
    final netLedgerCash = ledgerCashRows.isNotEmpty ? (ledgerCashRows.first['net_ledger_cash'] as num? ?? 0).toInt() : 0;

    // Check opening balances component if accounts had opening balances
    final openingBalanceRows = await db.rawQuery('''
      SELECT COALESCE(SUM(opening_balance_paise), 0) as total_opening
      FROM cash_bank_accounts
      WHERE business_id = ? AND is_active = 1 AND deleted_at IS NULL
    ''', [businessId]);
    final totalOpening = openingBalanceRows.isNotEmpty ? (openingBalanceRows.first['total_opening'] as num? ?? 0).toInt() : 0;

    final expectedCashBank = totalOpening + netLedgerCash;
    final cashBankReconciled = totalCashBank == expectedCashBank;

    if (!cashBankReconciled) {
      issues.add(
        AccountingIntegrityIssue(
          category: 'CASH_BANK',
          description: 'Cash & Bank holding balances (₹${(totalCashBank / 100).toStringAsFixed(2)}) disagree with ledger postings + opening balances (₹${(expectedCashBank / 100).toStringAsFixed(2)})',
          expectedPaise: expectedCashBank,
          actualPaise: totalCashBank,
          discrepancyPaise: (totalCashBank - expectedCashBank).abs(),
        ),
      );
    }

    // 4. Customer receivables agree with accounting:
    // Total unpaid/partially paid invoices balance == net debit of ledger account 1100 (AR)
    final invoiceArRows = await db.rawQuery('''
      SELECT COALESCE(SUM(balance_amount_paise), 0) as ar_sum
      FROM invoices
      WHERE business_id = ? AND status IN ('FINALIZED', 'PARTIAL') AND cancelled_at IS NULL
    ''', [businessId]);
    final invoiceAr = invoiceArRows.isNotEmpty ? (invoiceArRows.first['ar_sum'] as num? ?? 0).toInt() : 0;

    final ledgerArRows = await db.rawQuery('''
      SELECT COALESCE(SUM(le.debit_paise), 0) - COALESCE(SUM(le.credit_paise), 0) as ar_ledger
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.code = '1100'
    ''', [businessId]);
    final ledgerAr = ledgerArRows.isNotEmpty ? (ledgerArRows.first['ar_ledger'] as num? ?? 0).toInt() : 0;

    final receivablesReconciled = invoiceAr == ledgerAr;
    if (!receivablesReconciled) {
      issues.add(
        AccountingIntegrityIssue(
          category: 'AR',
          description: 'Customer outstanding invoices (₹${(invoiceAr / 100).toStringAsFixed(2)}) disagree with Accounts Receivable ledger account 1100 (₹${(ledgerAr / 100).toStringAsFixed(2)})',
          expectedPaise: invoiceAr,
          actualPaise: ledgerAr,
          discrepancyPaise: (invoiceAr - ledgerAr).abs(),
        ),
      );
    }

    // 5. Supplier payables agree with accounting:
    // Total unpaid/partially paid purchases balance == net credit of ledger account 2100 (AP)
    final purchaseApRows = await db.rawQuery('''
      SELECT COALESCE(SUM(balance_amount_paise), 0) as ap_sum
      FROM purchases
      WHERE business_id = ? AND status IN ('FINALIZED', 'PARTIAL') AND deleted_at IS NULL
    ''', [businessId]);
    final purchaseAp = purchaseApRows.isNotEmpty ? (purchaseApRows.first['ap_sum'] as num? ?? 0).toInt() : 0;

    final ledgerApRows = await db.rawQuery('''
      SELECT COALESCE(SUM(le.credit_paise), 0) - COALESCE(SUM(le.debit_paise), 0) as ap_ledger
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.code = '2100'
    ''', [businessId]);
    final ledgerAp = ledgerApRows.isNotEmpty ? (ledgerApRows.first['ap_ledger'] as num? ?? 0).toInt() : 0;

    final payablesReconciled = purchaseAp == ledgerAp;
    if (!payablesReconciled) {
      issues.add(
        AccountingIntegrityIssue(
          category: 'AP',
          description: 'Supplier outstanding bills (₹${(purchaseAp / 100).toStringAsFixed(2)}) disagree with Accounts Payable ledger account 2100 (₹${(ledgerAp / 100).toStringAsFixed(2)})',
          expectedPaise: purchaseAp,
          actualPaise: ledgerAp,
          discrepancyPaise: (purchaseAp - ledgerAp).abs(),
        ),
      );
    }

    // 6. Expense postings agree with expense records:
    // Total taxable amount of POSTED expenses == net debit of ledger EXPENSE entries with transaction_type 'EXPENSE'
    final expenseTaxableRows = await db.rawQuery('''
      SELECT COALESCE(SUM(taxable_amount_paise), 0) as posted_taxable
      FROM expenses
      WHERE business_id = ? AND status = 'POSTED' AND deleted_at IS NULL
    ''', [businessId]);
    final postedTaxable = expenseTaxableRows.isNotEmpty ? (expenseTaxableRows.first['posted_taxable'] as num? ?? 0).toInt() : 0;

    final expenseLedgerRows = await db.rawQuery('''
      SELECT COALESCE(SUM(le.debit_paise), 0) - COALESCE(SUM(le.credit_paise), 0) as ledger_expense_sum
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.account_type = 'EXPENSE' AND le.transaction_type IN ('EXPENSE', 'EXPENSE_CANCELLATION')
    ''', [businessId]);
    final ledgerExpenseSum = expenseLedgerRows.isNotEmpty ? (expenseLedgerRows.first['ledger_expense_sum'] as num? ?? 0).toInt() : 0;

    final expensesReconciled = postedTaxable == ledgerExpenseSum;
    if (!expensesReconciled) {
      issues.add(
        AccountingIntegrityIssue(
          category: 'EXPENSE',
          description: 'Posted expenses taxable amount (₹${(postedTaxable / 100).toStringAsFixed(2)}) disagrees with ledger expense entries (₹${(ledgerExpenseSum / 100).toStringAsFixed(2)})',
          expectedPaise: postedTaxable,
          actualPaise: ledgerExpenseSum,
          discrepancyPaise: (postedTaxable - ledgerExpenseSum).abs(),
        ),
      );
    }

    return AccountingIntegrityReport(
      businessId: businessId,
      journalEntriesBalanced: journalEntriesBalanced,
      trialBalanceBalanced: trialBalanceBalanced,
      cashBankReconciled: cashBankReconciled,
      receivablesReconciled: receivablesReconciled,
      payablesReconciled: payablesReconciled,
      expensesReconciled: expensesReconciled,
      issues: issues,
      auditedAt: DateTime.now().toUtc(),
    );
  }
}
