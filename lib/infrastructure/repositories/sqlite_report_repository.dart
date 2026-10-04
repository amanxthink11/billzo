import 'package:billzo/domain/reports/aging_analysis_report.dart';
import 'package:billzo/domain/reports/balance_sheet_report.dart';
import 'package:billzo/domain/reports/gst_summary_report.dart';
import 'package:billzo/domain/reports/gstr1_report.dart';
import 'package:billzo/domain/reports/profit_loss_report.dart';
import 'package:billzo/domain/reports/report_repository.dart';
import 'package:billzo/domain/reports/stock_valuation_report.dart';
import 'package:billzo/domain/reports/trial_balance_report.dart';
import 'package:billzo/infrastructure/sqlite/database_helper.dart';

/// SQLite implementation of financial and statutory reporting services based on double-entry ledger.
class SqliteReportRepository implements IReportRepository {
  final DatabaseHelper _dbHelper;

  SqliteReportRepository(this._dbHelper);

  @override
  Future<TrialBalanceReport> getTrialBalance(
    String businessId, {
    DateTime? asOfDate,
    DateTime? startDate,
  }) async {
    final db = await _dbHelper.database;

    final whereConditions = <String>['la.business_id = ?'];
    final whereArgs = <dynamic>[businessId];

    final leWhere = <String>['le.business_id = ?'];
    final leArgs = <dynamic>[businessId];

    if (startDate != null) {
      leWhere.add('le.entry_date >= ?');
      leArgs.add(startDate.toIso8601String());
    }

    if (asOfDate != null) {
      leWhere.add('le.entry_date <= ?');
      leArgs.add(asOfDate.toIso8601String());
    }

    final sql = '''
      SELECT 
        la.id as account_id,
        la.code as account_code,
        la.name as account_name,
        la.account_type,
        COALESCE(SUM(le.debit_paise), 0) as total_debit,
        COALESCE(SUM(le.credit_paise), 0) as total_credit
      FROM ledger_accounts la
      LEFT JOIN ledger_entries le ON la.id = le.account_id AND ${leWhere.join(' AND ')}
      WHERE ${whereConditions.join(' AND ')}
      GROUP BY la.id, la.code, la.name, la.account_type
      HAVING total_debit > 0 OR total_credit > 0
      ORDER BY la.code ASC
    ''';

    final queryArgs = [...leArgs, ...whereArgs];
    final rows = await db.rawQuery(sql, queryArgs);

    int sumGrossDebits = 0;
    int sumGrossCredits = 0;
    final entries = <TrialBalanceEntry>[];

    for (final row in rows) {
      final debit = (row['total_debit'] as num? ?? 0).toInt();
      final credit = (row['total_credit'] as num? ?? 0).toInt();

      sumGrossDebits += debit;
      sumGrossCredits += credit;

      final netDebit = debit > credit ? debit - credit : 0;
      final netCredit = credit > debit ? credit - debit : 0;

      entries.add(
        TrialBalanceEntry(
          accountId: row['account_id'] as String,
          accountCode: row['account_code'] as String,
          accountName: row['account_name'] as String,
          accountType: row['account_type'] as String,
          totalDebitPaise: debit,
          totalCreditPaise: credit,
          netDebitPaise: netDebit,
          netCreditPaise: netCredit,
        ),
      );
    }

    return TrialBalanceReport(
      businessId: businessId,
      asOfDate: asOfDate,
      startDate: startDate,
      entries: entries,
      totalDebitsPaise: sumGrossDebits,
      totalCreditsPaise: sumGrossCredits,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<ProfitLossReport> getProfitLoss(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
    bool includePreviousPeriod = false,
  }) async {
    final db = await _dbHelper.database;
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    // 1. Sales Revenue (Account 4000)
    final salesRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(le.credit_paise), 0) - COALESCE(SUM(le.debit_paise), 0) as net_sales
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.code = '4000'
        AND le.entry_date >= ? AND le.entry_date <= ?
    ''', [businessId, startStr, endStr]);
    final salesRevenuePaise = salesRows.isNotEmpty ? (salesRows.first['net_sales'] as num? ?? 0).toInt() : 0;

    // 2. Round-off Account (Account 5200)
    final roundOffRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(le.credit_paise), 0) - COALESCE(SUM(le.debit_paise), 0) as net_roundoff
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.code = '5200'
        AND le.entry_date >= ? AND le.entry_date <= ?
    ''', [businessId, startStr, endStr]);
    final netRoundOff = roundOffRows.isNotEmpty ? (roundOffRows.first['net_roundoff'] as num? ?? 0).toInt() : 0;
    final otherIncomePaise = netRoundOff > 0 ? netRoundOff : 0;
    final roundOffExpensePaise = netRoundOff < 0 ? netRoundOff.abs() : 0;

    // 3. Cost of Goods Sold (Account 5000)
    final cogsRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(le.debit_paise), 0) - COALESCE(SUM(le.credit_paise), 0) as net_cogs
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.code = '5000'
        AND le.entry_date >= ? AND le.entry_date <= ?
    ''', [businessId, startStr, endStr]);
    final cogsPaise = cogsRows.isNotEmpty ? (cogsRows.first['net_cogs'] as num? ?? 0).toInt() : 0;

    final String cogsNote;
    if (cogsPaise == 0) {
      cogsNote =
          'Perpetual COGS tracking deferred — purchase costs are capitalized under Inventory Asset (1200) until periodic stock valuation.';
    } else {
      cogsNote = 'Direct Cost of Goods Sold from ledger account 5000.';
    }

    // 4. Operating Expenses (Accounts with type 'EXPENSE', code != '5000' and code != '5200')
    final expenseRows = await db.rawQuery('''
      SELECT 
        la.code as account_code,
        la.name as account_name,
        COALESCE(SUM(le.debit_paise), 0) - COALESCE(SUM(le.credit_paise), 0) as net_expense
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? 
        AND la.account_type = 'EXPENSE'
        AND la.code NOT IN ('5000', '5200')
        AND le.entry_date >= ? AND le.entry_date <= ?
      GROUP BY la.code, la.name
      HAVING net_expense > 0
      ORDER BY la.code ASC
    ''', [businessId, startStr, endStr]);

    final expenseBreakdown = <ExpenseCategoryBreakdown>[];
    int totalOperatingExpensesFromCategories = 0;

    for (final row in expenseRows) {
      final amt = (row['net_expense'] as num? ?? 0).toInt();
      totalOperatingExpensesFromCategories += amt;
      final rawName = row['account_name'] as String;
      final cleanName = rawName.endsWith(' Expense')
          ? rawName.substring(0, rawName.length - 8)
          : rawName;

      expenseBreakdown.add(
        ExpenseCategoryBreakdown(
          categoryName: cleanName,
          accountCode: row['account_code'] as String,
          amountPaise: amt,
        ),
      );
    }

    final totalRevenuePaise = salesRevenuePaise + otherIncomePaise;
    final grossProfitPaise = totalRevenuePaise - cogsPaise;
    final totalOperatingExpensesPaise = totalOperatingExpensesFromCategories + roundOffExpensePaise;
    final netProfitPaise = grossProfitPaise - totalOperatingExpensesPaise;

    ProfitLossReport? previousPeriod;
    if (includePreviousPeriod) {
      final periodDuration = endDate.difference(startDate);
      final prevEnd = startDate.subtract(const Duration(milliseconds: 1));
      final prevStart = prevEnd.subtract(periodDuration);
      previousPeriod = await getProfitLoss(
        businessId,
        startDate: prevStart,
        endDate: prevEnd,
        includePreviousPeriod: false,
      );
    }

    return ProfitLossReport(
      businessId: businessId,
      startDate: startDate,
      endDate: endDate,
      salesRevenuePaise: salesRevenuePaise,
      otherIncomePaise: otherIncomePaise,
      totalRevenuePaise: totalRevenuePaise,
      cogsPaise: cogsPaise,
      cogsNote: cogsNote,
      grossProfitPaise: grossProfitPaise,
      expenseBreakdown: expenseBreakdown,
      roundOffExpensePaise: roundOffExpensePaise,
      totalOperatingExpensesPaise: totalOperatingExpensesPaise,
      netProfitPaise: netProfitPaise,
      previousPeriodReport: previousPeriod,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<BalanceSheetReport> getBalanceSheet(
    String businessId, {
    required DateTime asOfDate,
  }) async {
    final db = await _dbHelper.database;
    final asOfStr = asOfDate.toIso8601String();

    // Query cumulative account balances up to asOfDate
    final rows = await db.rawQuery('''
      SELECT 
        la.code as account_code,
        la.name as account_name,
        la.account_type,
        COALESCE(SUM(le.debit_paise), 0) - COALESCE(SUM(le.credit_paise), 0) as net_debit,
        COALESCE(SUM(le.credit_paise), 0) - COALESCE(SUM(le.debit_paise), 0) as net_credit
      FROM ledger_accounts la
      LEFT JOIN ledger_entries le ON la.id = le.account_id AND le.business_id = ? AND le.entry_date <= ?
      WHERE la.business_id = ?
      GROUP BY la.code, la.name, la.account_type
      ORDER BY la.code ASC
    ''', [businessId, asOfStr, businessId]);

    final assetItems = <BalanceSheetItem>[];
    int totalAssetsPaise = 0;

    final liabilityItems = <BalanceSheetItem>[];
    int totalLiabilitiesPaise = 0;

    final equityItems = <BalanceSheetItem>[];
    int equityAccountsTotalPaise = 0;

    for (final row in rows) {
      final code = row['account_code'] as String;
      final name = row['account_name'] as String;
      final type = row['account_type'] as String;
      final netDebit = (row['net_debit'] as num? ?? 0).toInt();
      final netCredit = (row['net_credit'] as num? ?? 0).toInt();

      if (type == 'ASSET') {
        if (netDebit != 0) {
          assetItems.add(BalanceSheetItem(accountCode: code, accountName: name, amountPaise: netDebit));
          totalAssetsPaise += netDebit;
        }
      } else if (type == 'LIABILITY') {
        if (netCredit != 0) {
          liabilityItems.add(BalanceSheetItem(accountCode: code, accountName: name, amountPaise: netCredit));
          totalLiabilitiesPaise += netCredit;
        }
      } else if (type == 'EQUITY') {
        if (netCredit != 0) {
          equityItems.add(BalanceSheetItem(accountCode: code, accountName: name, amountPaise: netCredit));
          equityAccountsTotalPaise += netCredit;
        }
      }
    }

    // Cumulative Net Earnings (Income - Expenses) as of asOfDate
    final incomeRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(le.credit_paise), 0) - COALESCE(SUM(le.debit_paise), 0) as net_income
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.account_type = 'INCOME' AND le.entry_date <= ?
    ''', [businessId, asOfStr]);
    final cumulativeIncome = incomeRows.isNotEmpty ? (incomeRows.first['net_income'] as num? ?? 0).toInt() : 0;

    final expenseSumRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(le.debit_paise), 0) - COALESCE(SUM(le.credit_paise), 0) as net_expense
      FROM ledger_entries le
      JOIN ledger_accounts la ON le.account_id = la.id
      WHERE le.business_id = ? AND la.account_type = 'EXPENSE' AND le.entry_date <= ?
    ''', [businessId, asOfStr]);
    final cumulativeExpenses = expenseSumRows.isNotEmpty ? (expenseSumRows.first['net_expense'] as num? ?? 0).toInt() : 0;

    final currentPeriodEarningsPaise = cumulativeIncome - cumulativeExpenses;
    final totalEquityPaise = equityAccountsTotalPaise + currentPeriodEarningsPaise;

    return BalanceSheetReport(
      businessId: businessId,
      asOfDate: asOfDate,
      assetItems: assetItems,
      totalAssetsPaise: totalAssetsPaise,
      liabilityItems: liabilityItems,
      totalLiabilitiesPaise: totalLiabilitiesPaise,
      equityItems: equityItems,
      currentPeriodEarningsPaise: currentPeriodEarningsPaise,
      totalEquityPaise: totalEquityPaise,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<GstSummaryReport> getGstSummary(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _dbHelper.database;
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    // 1. Outward Tax from Invoices
    final invoiceRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(taxable_amount_paise), 0) as taxable,
        COALESCE(SUM(cgst_paise), 0) as cgst,
        COALESCE(SUM(sgst_paise), 0) as sgst,
        COALESCE(SUM(igst_paise), 0) as igst
      FROM invoices
      WHERE business_id = ? 
        AND status IN ('FINALIZED', 'PAID', 'PARTIAL')
        AND invoice_date >= ? AND invoice_date <= ?
        AND cancelled_at IS NULL
    ''', [businessId, startStr, endStr]);

    final invRow = invoiceRows.isNotEmpty ? invoiceRows.first : <String, dynamic>{};
    final outwardSupply = GstTaxBucket(
      taxableAmountPaise: (invRow['taxable'] as num? ?? 0).toInt(),
      cgstPaise: (invRow['cgst'] as num? ?? 0).toInt(),
      sgstPaise: (invRow['sgst'] as num? ?? 0).toInt(),
      igstPaise: (invRow['igst'] as num? ?? 0).toInt(),
    );

    // 2. Inward Purchase Tax (Purchases minus Purchase Returns)
    final purchaseRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN itc_eligibility = 'ELIGIBLE' THEN taxable_amount_paise ELSE 0 END), 0) as eligible_taxable,
        COALESCE(SUM(input_cgst_paise), 0) as cgst,
        COALESCE(SUM(input_sgst_paise), 0) as sgst,
        COALESCE(SUM(input_igst_paise), 0) as igst,
        COALESCE(SUM(CASE WHEN itc_eligibility != 'ELIGIBLE' THEN (cgst_paise + sgst_paise + igst_paise) ELSE 0 END), 0) as ineligible_tax
      FROM purchases
      WHERE business_id = ?
        AND status IN ('FINALIZED', 'PAID', 'PARTIAL')
        AND purchase_date >= ? AND purchase_date <= ?
        AND deleted_at IS NULL
    ''', [businessId, startStr, endStr]);

    final purRow = purchaseRows.isNotEmpty ? purchaseRows.first : <String, dynamic>{};

    // Purchase Returns
    final returnRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(taxable_amount_paise), 0) as ret_taxable,
        COALESCE(SUM(cgst_paise), 0) as ret_cgst,
        COALESCE(SUM(sgst_paise), 0) as ret_sgst,
        COALESCE(SUM(igst_paise), 0) as ret_igst
      FROM purchase_returns
      WHERE business_id = ?
        AND status = 'FINALIZED'
        AND return_date >= ? AND return_date <= ?
        AND deleted_at IS NULL
    ''', [businessId, startStr, endStr]);

    final retRow = returnRows.isNotEmpty ? returnRows.first : <String, dynamic>{};

    final netPurchaseTaxable = (purRow['eligible_taxable'] as num? ?? 0).toInt() -
        (retRow['ret_taxable'] as num? ?? 0).toInt();
    final netPurchaseCgst = (purRow['cgst'] as num? ?? 0).toInt() -
        (retRow['ret_cgst'] as num? ?? 0).toInt();
    final netPurchaseSgst = (purRow['sgst'] as num? ?? 0).toInt() -
        (retRow['ret_sgst'] as num? ?? 0).toInt();
    final netPurchaseIgst = (purRow['igst'] as num? ?? 0).toInt() -
        (retRow['ret_igst'] as num? ?? 0).toInt();

    final eligiblePurchaseItc = GstTaxBucket(
      taxableAmountPaise: netPurchaseTaxable > 0 ? netPurchaseTaxable : 0,
      cgstPaise: netPurchaseCgst > 0 ? netPurchaseCgst : 0,
      sgstPaise: netPurchaseSgst > 0 ? netPurchaseSgst : 0,
      igstPaise: netPurchaseIgst > 0 ? netPurchaseIgst : 0,
    );
    final ineligiblePurchaseItcPaise = (purRow['ineligible_tax'] as num? ?? 0).toInt();

    // 3. Expense Input Tax (from posted Expenses)
    final expenseRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(taxable_amount_paise), 0) as taxable,
        COALESCE(SUM(cgst_paise), 0) as cgst,
        COALESCE(SUM(sgst_paise), 0) as sgst,
        COALESCE(SUM(igst_paise), 0) as igst
      FROM expenses
      WHERE business_id = ?
        AND status = 'POSTED'
        AND expense_date >= ? AND expense_date <= ?
        AND deleted_at IS NULL
    ''', [businessId, startStr, endStr]);

    final expRow = expenseRows.isNotEmpty ? expenseRows.first : <String, dynamic>{};
    final eligibleExpenseItc = GstTaxBucket(
      taxableAmountPaise: (expRow['taxable'] as num? ?? 0).toInt(),
      cgstPaise: (expRow['cgst'] as num? ?? 0).toInt(),
      sgstPaise: (expRow['sgst'] as num? ?? 0).toInt(),
      igstPaise: (expRow['igst'] as num? ?? 0).toInt(),
    );

    return GstSummaryReport(
      businessId: businessId,
      startDate: startDate,
      endDate: endDate,
      outwardSupply: outwardSupply,
      eligiblePurchaseItc: eligiblePurchaseItc,
      ineligiblePurchaseItcPaise: ineligiblePurchaseItcPaise,
      eligibleExpenseItc: eligibleExpenseItc,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<Gstr1Report> getGstr1Report(
    String businessId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _dbHelper.database;
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    // 1. Fetch business details for state code and GSTIN
    final businessRows = await db.query(
      'businesses',
      columns: ['state_code', 'gstin'],
      where: 'id = ?',
      whereArgs: [businessId],
    );
    final businessStateCode = businessRows.isNotEmpty ? (businessRows.first['state_code'] as String? ?? '07') : '07';
    final businessGstin = businessRows.isNotEmpty ? businessRows.first['gstin'] as String? : null;

    // 2. Fetch finalized invoices with customer info
    final invoiceRows = await db.rawQuery('''
      SELECT 
        i.id,
        i.invoice_number,
        i.invoice_date,
        i.total_amount_paise,
        i.place_of_supply_state_code,
        c.name as customer_name,
        c.gstin as customer_gstin
      FROM invoices i
      JOIN customers c ON i.customer_id = c.id
      WHERE i.business_id = ?
        AND i.status IN ('FINALIZED', 'PAID', 'PARTIAL')
        AND i.invoice_date >= ? AND i.invoice_date <= ?
        AND i.cancelled_at IS NULL
      ORDER BY i.invoice_date ASC, i.invoice_number ASC
    ''', [businessId, startStr, endStr]);

    // 3. Fetch line items for these invoices grouped by rate
    final itemRows = await db.rawQuery('''
      SELECT 
        ii.invoice_id,
        (ii.cgst_rate_basis_points + ii.sgst_rate_basis_points + ii.igst_rate_basis_points) as total_rate_basis_points,
        SUM(ii.taxable_amount_paise) as taxable,
        SUM(ii.cgst_amount_paise) as cgst,
        SUM(ii.sgst_amount_paise) as sgst,
        SUM(ii.igst_amount_paise) as igst,
        SUM(ii.cess_amount_paise) as cess
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.business_id = ?
        AND i.status IN ('FINALIZED', 'PAID', 'PARTIAL')
        AND i.invoice_date >= ? AND i.invoice_date <= ?
        AND i.cancelled_at IS NULL
      GROUP BY ii.invoice_id, total_rate_basis_points
    ''', [businessId, startStr, endStr]);

    final invoiceRateMap = <String, List<Map<String, dynamic>>>{};
    for (final row in itemRows) {
      final invId = row['invoice_id'] as String;
      invoiceRateMap.putIfAbsent(invId, () => []).add(row);
    }

    final b2bInvoices = <Gstr1B2bInvoice>[];
    final b2clInvoices = <Gstr1B2clInvoice>[];
    final b2csAggregator = <String, Map<String, dynamic>>{};

    for (final inv in invoiceRows) {
      final invId = inv['id'] as String;
      final invNumber = inv['invoice_number'] as String;
      final invDate = DateTime.parse(inv['invoice_date'] as String);
      final totalValuePaise = (inv['total_amount_paise'] as num? ?? 0).toInt();
      final pos = inv['place_of_supply_state_code'] as String? ?? businessStateCode;
      final customerGstin = (inv['customer_gstin'] as String?)?.trim();
      final customerName = inv['customer_name'] as String? ?? 'Valued Customer';
      final hasGstin = customerGstin != null && customerGstin.isNotEmpty;

      final rates = invoiceRateMap[invId] ?? [];

      if (hasGstin) {
        if (rates.isEmpty) {
          b2bInvoices.add(Gstr1B2bInvoice(
            receiverGstin: customerGstin,
            receiverName: customerName,
            invoiceNumber: invNumber,
            invoiceDate: invDate,
            invoiceValuePaise: totalValuePaise,
            placeOfSupply: pos,
            rateBasisPoints: 0,
            taxableValuePaise: totalValuePaise,
          ));
        } else {
          for (final rateRow in rates) {
            b2bInvoices.add(Gstr1B2bInvoice(
              receiverGstin: customerGstin,
              receiverName: customerName,
              invoiceNumber: invNumber,
              invoiceDate: invDate,
              invoiceValuePaise: totalValuePaise,
              placeOfSupply: pos,
              rateBasisPoints: (rateRow['total_rate_basis_points'] as num? ?? 0).toInt(),
              taxableValuePaise: (rateRow['taxable'] as num? ?? 0).toInt(),
              cgstPaise: (rateRow['cgst'] as num? ?? 0).toInt(),
              sgstPaise: (rateRow['sgst'] as num? ?? 0).toInt(),
              igstPaise: (rateRow['igst'] as num? ?? 0).toInt(),
              cessPaise: (rateRow['cess'] as num? ?? 0).toInt(),
            ));
          }
        }
      } else {
        final isInterState = pos != businessStateCode;
        final isLarge = totalValuePaise > Gstr1Report.b2clThresholdPaise;

        if (isInterState && isLarge) {
          if (rates.isEmpty) {
            b2clInvoices.add(Gstr1B2clInvoice(
              invoiceNumber: invNumber,
              invoiceDate: invDate,
              invoiceValuePaise: totalValuePaise,
              placeOfSupply: pos,
              rateBasisPoints: 0,
              taxableValuePaise: totalValuePaise,
            ));
          } else {
            for (final rateRow in rates) {
              b2clInvoices.add(Gstr1B2clInvoice(
                invoiceNumber: invNumber,
                invoiceDate: invDate,
                invoiceValuePaise: totalValuePaise,
                placeOfSupply: pos,
                rateBasisPoints: (rateRow['total_rate_basis_points'] as num? ?? 0).toInt(),
                taxableValuePaise: (rateRow['taxable'] as num? ?? 0).toInt(),
                igstPaise: (rateRow['igst'] as num? ?? 0).toInt(),
                cessPaise: (rateRow['cess'] as num? ?? 0).toInt(),
              ));
            }
          }
        } else {
          if (rates.isEmpty) {
            final key = '$pos|0';
            final current = b2csAggregator.putIfAbsent(key, () => {
              'pos': pos,
              'rate': 0,
              'taxable': 0,
              'cgst': 0,
              'sgst': 0,
              'igst': 0,
              'cess': 0,
            });
            current['taxable'] = (current['taxable'] as int) + totalValuePaise;
          } else {
            for (final rateRow in rates) {
              final rate = (rateRow['total_rate_basis_points'] as num? ?? 0).toInt();
              final key = '$pos|$rate';
              final current = b2csAggregator.putIfAbsent(key, () => {
                'pos': pos,
                'rate': rate,
                'taxable': 0,
                'cgst': 0,
                'sgst': 0,
                'igst': 0,
                'cess': 0,
              });
              current['taxable'] = (current['taxable'] as int) + (rateRow['taxable'] as num? ?? 0).toInt();
              current['cgst'] = (current['cgst'] as int) + (rateRow['cgst'] as num? ?? 0).toInt();
              current['sgst'] = (current['sgst'] as int) + (rateRow['sgst'] as num? ?? 0).toInt();
              current['igst'] = (current['igst'] as int) + (rateRow['igst'] as num? ?? 0).toInt();
              current['cess'] = (current['cess'] as int) + (rateRow['cess'] as num? ?? 0).toInt();
            }
          }
        }
      }
    }

    final b2csItems = b2csAggregator.values.map((v) => Gstr1B2csItem(
      placeOfSupply: v['pos'] as String,
      rateBasisPoints: v['rate'] as int,
      taxableValuePaise: v['taxable'] as int,
      cgstPaise: v['cgst'] as int,
      sgstPaise: v['sgst'] as int,
      igstPaise: v['igst'] as int,
      cessPaise: v['cess'] as int,
    )).toList()
      ..sort((a, b) => a.placeOfSupply.compareTo(b.placeOfSupply));

    // 4. Table 12: HSN Summary
    final hsnRows = await db.rawQuery('''
      SELECT 
        COALESCE(ii.hsn_sac, 'N/A') as hsn_sac,
        MAX(ii.product_name) as sample_description,
        ii.unit_code,
        SUM(ii.quantity) as total_quantity,
        SUM(ii.total_amount_paise) as total_value,
        SUM(ii.taxable_amount_paise) as taxable_value,
        SUM(ii.cgst_amount_paise) as cgst,
        SUM(ii.sgst_amount_paise) as sgst,
        SUM(ii.igst_amount_paise) as igst,
        SUM(ii.cess_amount_paise) as cess
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.business_id = ?
        AND i.status IN ('FINALIZED', 'PAID', 'PARTIAL')
        AND i.invoice_date >= ? AND i.invoice_date <= ?
        AND i.cancelled_at IS NULL
      GROUP BY COALESCE(ii.hsn_sac, 'N/A'), ii.unit_code
      ORDER BY hsn_sac ASC
    ''', [businessId, startStr, endStr]);

    final hsnSummary = hsnRows.map((r) {
      final rawQty = (r['total_quantity'] as num? ?? 0).toInt();
      final totalQuantity = rawQty >= 0 ? (rawQty + 500) ~/ 1000 : (rawQty - 500) ~/ 1000;
      return Gstr1HsnSummaryItem(
        hsnSac: r['hsn_sac'] as String? ?? 'N/A',
        description: r['sample_description'] as String? ?? '',
        uqc: r['unit_code'] as String? ?? 'NOS',
        totalQuantity: totalQuantity,
        totalValuePaise: (r['total_value'] as num? ?? 0).toInt(),
        taxableValuePaise: (r['taxable_value'] as num? ?? 0).toInt(),
        cgstPaise: (r['cgst'] as num? ?? 0).toInt(),
        sgstPaise: (r['sgst'] as num? ?? 0).toInt(),
        igstPaise: (r['igst'] as num? ?? 0).toInt(),
        cessPaise: (r['cess'] as num? ?? 0).toInt(),
      );
    }).toList();

    return Gstr1Report(
      businessId: businessId,
      businessGstin: businessGstin,
      startDate: startDate,
      endDate: endDate,
      b2bInvoices: b2bInvoices,
      b2clInvoices: b2clInvoices,
      b2csItems: b2csItems,
      hsnSummary: hsnSummary,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<ReceivablesAgingReport> getReceivablesAgingReport(
    String businessId, {
    DateTime? asOfDate,
  }) async {
    final db = await _dbHelper.database;
    final referenceDate = asOfDate ?? DateTime.now();

    final rows = await db.rawQuery('''
      SELECT 
        c.id as customer_id,
        c.name as customer_name,
        c.phone as customer_phone,
        c.gstin as customer_gstin,
        i.due_date,
        i.balance_amount_paise
      FROM invoices i
      JOIN customers c ON i.customer_id = c.id
      WHERE i.business_id = ?
        AND i.status IN ('FINALIZED', 'PARTIAL')
        AND i.balance_amount_paise > 0
        AND i.cancelled_at IS NULL
      ORDER BY c.name ASC
    ''', [businessId]);

    final partyBuckets = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final custId = row['customer_id'] as String;
      final balancePaise = (row['balance_amount_paise'] as num? ?? 0).toInt();
      final dueDateStr = row['due_date'] as String;
      final dueDate = DateTime.parse(dueDateStr);

      final daysOverdue = referenceDate.difference(dueDate).inDays;

      final data = partyBuckets.putIfAbsent(custId, () => {
        'partyId': custId,
        'partyName': row['customer_name'] as String? ?? '',
        'phone': row['customer_phone'] as String?,
        'gstin': row['customer_gstin'] as String?,
        'total': 0,
        'current': 0,
        'd1_30': 0,
        'd31_60': 0,
        'd61_90': 0,
        'd90plus': 0,
      });

      data['total'] = (data['total'] as int) + balancePaise;

      if (daysOverdue <= 0) {
        data['current'] = (data['current'] as int) + balancePaise;
      } else if (daysOverdue <= 30) {
        data['d1_30'] = (data['d1_30'] as int) + balancePaise;
      } else if (daysOverdue <= 60) {
        data['d31_60'] = (data['d31_60'] as int) + balancePaise;
      } else if (daysOverdue <= 90) {
        data['d61_90'] = (data['d61_90'] as int) + balancePaise;
      } else {
        data['d90plus'] = (data['d90plus'] as int) + balancePaise;
      }
    }

    final items = partyBuckets.values.map((d) => PartyAgingItem(
      partyId: d['partyId'] as String,
      partyName: d['partyName'] as String,
      phone: d['phone'] as String?,
      gstin: d['gstin'] as String?,
      totalOutstandingPaise: d['total'] as int,
      currentPaise: d['current'] as int,
      days1To30Paise: d['d1_30'] as int,
      days31To60Paise: d['d31_60'] as int,
      days61To90Paise: d['d61_90'] as int,
      days90PlusPaise: d['d90plus'] as int,
    )).toList();

    return ReceivablesAgingReport(
      businessId: businessId,
      asOfDate: referenceDate,
      items: items,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<PayablesAgingReport> getPayablesAgingReport(
    String businessId, {
    DateTime? asOfDate,
  }) async {
    final db = await _dbHelper.database;
    final referenceDate = asOfDate ?? DateTime.now();

    final rows = await db.rawQuery('''
      SELECT 
        s.id as supplier_id,
        s.name as supplier_name,
        s.phone as supplier_phone,
        s.gstin as supplier_gstin,
        p.due_date,
        p.balance_amount_paise
      FROM purchases p
      JOIN suppliers s ON p.supplier_id = s.id
      WHERE p.business_id = ?
        AND p.status IN ('FINALIZED', 'PARTIAL', 'PARTIALLY_PAID')
        AND p.balance_amount_paise > 0
        AND (p.deleted_at IS NULL)
      ORDER BY s.name ASC
    ''', [businessId]);

    final partyBuckets = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final suppId = row['supplier_id'] as String;
      final balancePaise = (row['balance_amount_paise'] as num? ?? 0).toInt();
      final dueDateStr = row['due_date'] as String;
      final dueDate = DateTime.parse(dueDateStr);

      final daysOverdue = referenceDate.difference(dueDate).inDays;

      final data = partyBuckets.putIfAbsent(suppId, () => {
        'partyId': suppId,
        'partyName': row['supplier_name'] as String? ?? '',
        'phone': row['supplier_phone'] as String?,
        'gstin': row['supplier_gstin'] as String?,
        'total': 0,
        'current': 0,
        'd1_30': 0,
        'd31_60': 0,
        'd61_90': 0,
        'd90plus': 0,
      });

      data['total'] = (data['total'] as int) + balancePaise;

      if (daysOverdue <= 0) {
        data['current'] = (data['current'] as int) + balancePaise;
      } else if (daysOverdue <= 30) {
        data['d1_30'] = (data['d1_30'] as int) + balancePaise;
      } else if (daysOverdue <= 60) {
        data['d31_60'] = (data['d31_60'] as int) + balancePaise;
      } else if (daysOverdue <= 90) {
        data['d61_90'] = (data['d61_90'] as int) + balancePaise;
      } else {
        data['d90plus'] = (data['d90plus'] as int) + balancePaise;
      }
    }

    final items = partyBuckets.values.map((d) => PartyAgingItem(
      partyId: d['partyId'] as String,
      partyName: d['partyName'] as String,
      phone: d['phone'] as String?,
      gstin: d['gstin'] as String?,
      totalOutstandingPaise: d['total'] as int,
      currentPaise: d['current'] as int,
      days1To30Paise: d['d1_30'] as int,
      days31To60Paise: d['d31_60'] as int,
      days61To90Paise: d['d61_90'] as int,
      days90PlusPaise: d['d90plus'] as int,
    )).toList();

    return PayablesAgingReport(
      businessId: businessId,
      asOfDate: referenceDate,
      items: items,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<StockValuationReport> getStockValuationReport(
    String businessId,
  ) async {
    final db = await _dbHelper.database;

    final rows = await db.rawQuery('''
      SELECT 
        p.id,
        p.name,
        p.sku,
        p.current_stock,
        p.purchase_price_paise,
        p.selling_price_paise,
        p.low_stock_threshold,
        u.code as unit_code,
        c.name as category_name
      FROM products p
      JOIN units u ON p.unit_id = u.id
      LEFT JOIN product_categories c ON p.category_id = c.id
      WHERE p.business_id = ?
        AND p.deleted_at IS NULL
      ORDER BY p.name ASC
    ''', [businessId]);

    final items = rows.map((r) {
      final rawStock = (r['current_stock'] as num? ?? 0).toInt();
      final currentStock = rawStock >= 0 ? (rawStock + 500) ~/ 1000 : (rawStock - 500) ~/ 1000;
      return StockValuationItem(
        productId: r['id'] as String,
        productName: r['name'] as String,
        sku: r['sku'] as String?,
        categoryName: r['category_name'] as String?,
        unitCode: r['unit_code'] as String? ?? 'NOS',
        currentStock: currentStock,
        currentStockScaled: rawStock,
        purchasePricePaise: (r['purchase_price_paise'] as num? ?? 0).toInt(),
        sellingPricePaise: (r['selling_price_paise'] as num? ?? 0).toInt(),
        lowStockThreshold: (r['low_stock_threshold'] as num? ?? 5).toInt(),
      );
    }).toList();

    return StockValuationReport(
      businessId: businessId,
      asOfDate: DateTime.now(),
      items: items,
      generatedAt: DateTime.now().toUtc(),
    );
  }
}
