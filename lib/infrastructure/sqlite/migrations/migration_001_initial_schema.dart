/// Version 1 Migration: Initial Relational Database Schema for Billzo.
/// Exactly matches the specification in `docs/DATABASE_SCHEMA.md`.
class Migration001InitialSchema {
  Migration001InitialSchema._();

  static const int version = 1;
  static const String description = '001_initial_schema';

  static const List<String> statements = [
    // 1. Businesses
    '''
    CREATE TABLE IF NOT EXISTS businesses (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        legal_name TEXT,
        trade_name TEXT,
        gstin TEXT,
        pan TEXT,
        email TEXT,
        phone TEXT NOT NULL,
        address_line1 TEXT,
        address_line2 TEXT,
        city TEXT,
        state_code TEXT NOT NULL,
        state_name TEXT NOT NULL,
        pincode TEXT,
        country TEXT NOT NULL DEFAULT 'India',
        currency_code TEXT NOT NULL DEFAULT 'INR',
        currency_symbol TEXT NOT NULL DEFAULT '₹',
        logo_path TEXT,
        signature_path TEXT,
        upi_id TEXT,
        bank_account_name TEXT,
        bank_account_number TEXT,
        bank_ifsc TEXT,
        bank_name TEXT,
        bank_branch TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',

    // 2. Business Settings
    '''
    CREATE TABLE IF NOT EXISTS business_settings (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        default_tax_rate_id TEXT,
        default_invoice_terms TEXT,
        enable_hsn INTEGER NOT NULL DEFAULT 1,
        enable_mrp INTEGER NOT NULL DEFAULT 1,
        enable_discounts INTEGER NOT NULL DEFAULT 1,
        enable_round_off INTEGER NOT NULL DEFAULT 1,
        tax_inclusive_pricing INTEGER NOT NULL DEFAULT 0,
        low_stock_threshold INTEGER NOT NULL DEFAULT 5,
        thermal_printer_type TEXT NOT NULL DEFAULT 'A4',
        print_business_logo INTEGER NOT NULL DEFAULT 1,
        print_bank_details INTEGER NOT NULL DEFAULT 1,
        print_upi_qr INTEGER NOT NULL DEFAULT 1,
        auto_backup_enabled INTEGER NOT NULL DEFAULT 1,
        auto_backup_interval_days INTEGER NOT NULL DEFAULT 1,
        backup_directory_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',

    // 3. Invoice Sequences
    '''
    CREATE TABLE IF NOT EXISTS invoice_sequences (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        document_type TEXT NOT NULL,
        prefix TEXT NOT NULL,
        current_number INTEGER NOT NULL,
        padding_zeros INTEGER NOT NULL DEFAULT 4,
        fiscal_year TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(business_id, document_type, fiscal_year)
    );
    ''',

    // 4. Tax Rates
    '''
    CREATE TABLE IF NOT EXISTS tax_rates (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        rate_basis_points INTEGER NOT NULL,
        cgst_basis_points INTEGER NOT NULL,
        sgst_basis_points INTEGER NOT NULL,
        igst_basis_points INTEGER NOT NULL,
        cess_basis_points INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',

    // 5. Units
    '''
    CREATE TABLE IF NOT EXISTS units (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        allow_decimal INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        UNIQUE(business_id, code)
    );
    ''',

    // 6. Product Categories
    '''
    CREATE TABLE IF NOT EXISTS product_categories (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        parent_category_id TEXT REFERENCES product_categories(id),
        color_hex TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',

    // 7. Products
    '''
    CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        category_id TEXT REFERENCES product_categories(id),
        unit_id TEXT NOT NULL REFERENCES units(id),
        tax_rate_id TEXT NOT NULL REFERENCES tax_rates(id),
        name TEXT NOT NULL,
        sku TEXT,
        barcode TEXT,
        hsn_sac TEXT,
        description TEXT,
        selling_price_paise INTEGER NOT NULL,
        purchase_price_paise INTEGER NOT NULL DEFAULT 0,
        mrp_paise INTEGER NOT NULL DEFAULT 0,
        is_tax_inclusive INTEGER NOT NULL DEFAULT 0,
        track_inventory INTEGER NOT NULL DEFAULT 1,
        current_stock INTEGER NOT NULL DEFAULT 0,
        low_stock_threshold INTEGER NOT NULL DEFAULT 5,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(business_id, barcode);',
    'CREATE INDEX IF NOT EXISTS idx_products_sku ON products(business_id, sku);',
    'CREATE INDEX IF NOT EXISTS idx_products_name ON products(business_id, name);',

    // 8. Customers
    '''
    CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        company_name TEXT,
        phone TEXT,
        email TEXT,
        gstin TEXT,
        pan TEXT,
        billing_address_line1 TEXT,
        billing_address_line2 TEXT,
        billing_city TEXT,
        billing_state_code TEXT NOT NULL,
        billing_state_name TEXT NOT NULL,
        billing_pincode TEXT,
        shipping_address_line1 TEXT,
        shipping_address_line2 TEXT,
        shipping_city TEXT,
        shipping_state_code TEXT,
        shipping_state_name TEXT,
        shipping_pincode TEXT,
        credit_period_days INTEGER NOT NULL DEFAULT 0,
        credit_limit_paise INTEGER NOT NULL DEFAULT 0,
        opening_balance_paise INTEGER NOT NULL DEFAULT 0,
        opening_balance_type TEXT NOT NULL DEFAULT 'RECEIVABLE',
        current_balance_paise INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(business_id, phone);',
    'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(business_id, name);',

    // 9. Suppliers
    '''
    CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        company_name TEXT,
        phone TEXT,
        email TEXT,
        gstin TEXT,
        pan TEXT,
        address_line1 TEXT,
        address_line2 TEXT,
        city TEXT,
        state_code TEXT NOT NULL,
        state_name TEXT NOT NULL,
        pincode TEXT,
        credit_period_days INTEGER NOT NULL DEFAULT 0,
        opening_balance_paise INTEGER NOT NULL DEFAULT 0,
        opening_balance_type TEXT NOT NULL DEFAULT 'PAYABLE',
        current_balance_paise INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(business_id, name);',

    // 10. Invoices
    '''
    CREATE TABLE IF NOT EXISTS invoices (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        customer_id TEXT NOT NULL REFERENCES customers(id),
        recurring_invoice_id TEXT,
        invoice_number TEXT NOT NULL,
        invoice_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        place_of_supply_state_code TEXT NOT NULL,
        invoice_type TEXT NOT NULL DEFAULT 'TAX_INVOICE',
        status TEXT NOT NULL DEFAULT 'DRAFT',
        subtotal_paise INTEGER NOT NULL,
        discount_paise INTEGER NOT NULL DEFAULT 0,
        taxable_amount_paise INTEGER NOT NULL,
        cgst_paise INTEGER NOT NULL DEFAULT 0,
        sgst_paise INTEGER NOT NULL DEFAULT 0,
        igst_paise INTEGER NOT NULL DEFAULT 0,
        cess_paise INTEGER NOT NULL DEFAULT 0,
        round_off_paise INTEGER NOT NULL DEFAULT 0,
        total_amount_paise INTEGER NOT NULL,
        paid_amount_paise INTEGER NOT NULL DEFAULT 0,
        balance_amount_paise INTEGER NOT NULL,
        notes TEXT,
        terms_and_conditions TEXT,
        finalized_at TEXT,
        cancelled_at TEXT,
        cancellation_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        UNIQUE(business_id, invoice_number)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_invoices_date ON invoices(business_id, invoice_date);',
    'CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(business_id, customer_id);',
    'CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(business_id, status);',

    // 11. Invoice Items
    '''
    CREATE TABLE IF NOT EXISTS invoice_items (
        id TEXT PRIMARY KEY NOT NULL,
        invoice_id TEXT NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        tax_rate_id TEXT NOT NULL REFERENCES tax_rates(id),
        product_name TEXT NOT NULL,
        hsn_sac TEXT,
        quantity INTEGER NOT NULL,
        unit_code TEXT NOT NULL,
        rate_paise INTEGER NOT NULL,
        mrp_paise INTEGER NOT NULL DEFAULT 0,
        discount_paise INTEGER NOT NULL DEFAULT 0,
        taxable_amount_paise INTEGER NOT NULL,
        cgst_rate_basis_points INTEGER NOT NULL DEFAULT 0,
        cgst_amount_paise INTEGER NOT NULL DEFAULT 0,
        sgst_rate_basis_points INTEGER NOT NULL DEFAULT 0,
        sgst_amount_paise INTEGER NOT NULL DEFAULT 0,
        igst_rate_basis_points INTEGER NOT NULL DEFAULT 0,
        igst_amount_paise INTEGER NOT NULL DEFAULT 0,
        cess_rate_basis_points INTEGER NOT NULL DEFAULT 0,
        cess_amount_paise INTEGER NOT NULL DEFAULT 0,
        total_amount_paise INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items(invoice_id);',

    // 12. Estimates
    '''
    CREATE TABLE IF NOT EXISTS estimates (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        customer_id TEXT NOT NULL REFERENCES customers(id),
        estimate_number TEXT NOT NULL,
        estimate_date TEXT NOT NULL,
        expiry_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        converted_invoice_id TEXT REFERENCES invoices(id),
        subtotal_paise INTEGER NOT NULL,
        discount_paise INTEGER NOT NULL DEFAULT 0,
        taxable_amount_paise INTEGER NOT NULL,
        cgst_paise INTEGER NOT NULL DEFAULT 0,
        sgst_paise INTEGER NOT NULL DEFAULT 0,
        igst_paise INTEGER NOT NULL DEFAULT 0,
        round_off_paise INTEGER NOT NULL DEFAULT 0,
        total_amount_paise INTEGER NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        UNIQUE(business_id, estimate_number)
    );
    ''',

    // 13. Estimate Items
    '''
    CREATE TABLE IF NOT EXISTS estimate_items (
        id TEXT PRIMARY KEY NOT NULL,
        estimate_id TEXT NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        tax_rate_id TEXT NOT NULL REFERENCES tax_rates(id),
        product_name TEXT NOT NULL,
        hsn_sac TEXT,
        quantity INTEGER NOT NULL,
        unit_code TEXT NOT NULL,
        rate_paise INTEGER NOT NULL,
        discount_paise INTEGER NOT NULL DEFAULT 0,
        taxable_amount_paise INTEGER NOT NULL,
        cgst_amount_paise INTEGER NOT NULL DEFAULT 0,
        sgst_amount_paise INTEGER NOT NULL DEFAULT 0,
        igst_amount_paise INTEGER NOT NULL DEFAULT 0,
        total_amount_paise INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 14. Recurring Invoices
    '''
    CREATE TABLE IF NOT EXISTS recurring_invoices (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        customer_id TEXT NOT NULL REFERENCES customers(id),
        profile_name TEXT NOT NULL,
        frequency TEXT NOT NULL,
        custom_interval_days INTEGER,
        start_date TEXT NOT NULL,
        end_date TEXT,
        next_run_date TEXT NOT NULL,
        last_run_date TEXT,
        payment_terms_days INTEGER NOT NULL DEFAULT 15,
        auto_generate INTEGER NOT NULL DEFAULT 0,
        require_review INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_recurring_next_run ON recurring_invoices(business_id, status, next_run_date);',

    // 15. Recurring Invoice Items
    '''
    CREATE TABLE IF NOT EXISTS recurring_invoice_items (
        id TEXT PRIMARY KEY NOT NULL,
        recurring_invoice_id TEXT NOT NULL REFERENCES recurring_invoices(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        tax_rate_id TEXT NOT NULL REFERENCES tax_rates(id),
        quantity INTEGER NOT NULL,
        unit_code TEXT NOT NULL,
        rate_paise INTEGER NOT NULL,
        discount_paise INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 16. Recurring Invoice Executions
    '''
    CREATE TABLE IF NOT EXISTS recurring_invoice_executions (
        id TEXT PRIMARY KEY NOT NULL,
        recurring_invoice_id TEXT NOT NULL REFERENCES recurring_invoices(id) ON DELETE CASCADE,
        invoice_id TEXT REFERENCES invoices(id),
        scheduled_for_date TEXT NOT NULL,
        executed_at TEXT NOT NULL,
        execution_status TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(recurring_invoice_id, scheduled_for_date)
    );
    ''',

    // 17. Payments
    '''
    CREATE TABLE IF NOT EXISTS payments (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        party_id TEXT NOT NULL,
        party_type TEXT NOT NULL,
        payment_type TEXT NOT NULL,
        payment_number TEXT NOT NULL,
        payment_date TEXT NOT NULL,
        payment_mode TEXT NOT NULL,
        amount_paise INTEGER NOT NULL,
        reference_number TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        UNIQUE(business_id, payment_number)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_payments_party ON payments(business_id, party_id, payment_date);',

    // 18. Payment Allocations
    '''
    CREATE TABLE IF NOT EXISTS payment_allocations (
        id TEXT PRIMARY KEY NOT NULL,
        payment_id TEXT NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
        document_id TEXT NOT NULL,
        document_type TEXT NOT NULL,
        allocated_amount_paise INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_payment_allocations_doc ON payment_allocations(document_id);',

    // 19. Purchases
    '''
    CREATE TABLE IF NOT EXISTS purchases (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        supplier_id TEXT NOT NULL REFERENCES suppliers(id),
        purchase_number TEXT NOT NULL,
        vendor_invoice_number TEXT,
        purchase_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'FINALIZED',
        subtotal_paise INTEGER NOT NULL,
        discount_paise INTEGER NOT NULL DEFAULT 0,
        taxable_amount_paise INTEGER NOT NULL,
        cgst_paise INTEGER NOT NULL DEFAULT 0,
        sgst_paise INTEGER NOT NULL DEFAULT 0,
        igst_paise INTEGER NOT NULL DEFAULT 0,
        round_off_paise INTEGER NOT NULL DEFAULT 0,
        total_amount_paise INTEGER NOT NULL,
        paid_amount_paise INTEGER NOT NULL DEFAULT 0,
        balance_amount_paise INTEGER NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        UNIQUE(business_id, purchase_number)
    );
    ''',

    // 20. Purchase Items
    '''
    CREATE TABLE IF NOT EXISTS purchase_items (
        id TEXT PRIMARY KEY NOT NULL,
        purchase_id TEXT NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        tax_rate_id TEXT NOT NULL REFERENCES tax_rates(id),
        quantity INTEGER NOT NULL,
        unit_code TEXT NOT NULL,
        purchase_rate_paise INTEGER NOT NULL,
        taxable_amount_paise INTEGER NOT NULL,
        cgst_amount_paise INTEGER NOT NULL DEFAULT 0,
        sgst_amount_paise INTEGER NOT NULL DEFAULT 0,
        igst_amount_paise INTEGER NOT NULL DEFAULT 0,
        total_amount_paise INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 21. Sales Returns
    '''
    CREATE TABLE IF NOT EXISTS sales_returns (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        customer_id TEXT NOT NULL REFERENCES customers(id),
        original_invoice_id TEXT REFERENCES invoices(id),
        return_number TEXT NOT NULL,
        return_date TEXT NOT NULL,
        total_amount_paise INTEGER NOT NULL,
        taxable_amount_paise INTEGER NOT NULL,
        cgst_paise INTEGER NOT NULL DEFAULT 0,
        sgst_paise INTEGER NOT NULL DEFAULT 0,
        igst_paise INTEGER NOT NULL DEFAULT 0,
        reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        UNIQUE(business_id, return_number)
    );
    ''',

    // 22. Sales Return Items
    '''
    CREATE TABLE IF NOT EXISTS sales_return_items (
        id TEXT PRIMARY KEY NOT NULL,
        sales_return_id TEXT NOT NULL REFERENCES sales_returns(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        quantity INTEGER NOT NULL,
        rate_paise INTEGER NOT NULL,
        total_amount_paise INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 23. Purchase Returns
    '''
    CREATE TABLE IF NOT EXISTS purchase_returns (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        supplier_id TEXT NOT NULL REFERENCES suppliers(id),
        original_purchase_id TEXT REFERENCES purchases(id),
        return_number TEXT NOT NULL,
        return_date TEXT NOT NULL,
        total_amount_paise INTEGER NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        UNIQUE(business_id, return_number)
    );
    ''',

    // 24. Purchase Return Items
    '''
    CREATE TABLE IF NOT EXISTS purchase_return_items (
        id TEXT PRIMARY KEY NOT NULL,
        purchase_return_id TEXT NOT NULL REFERENCES purchase_returns(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id),
        quantity INTEGER NOT NULL,
        rate_paise INTEGER NOT NULL,
        total_amount_paise INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 25. Stock Movements
    '''
    CREATE TABLE IF NOT EXISTS stock_movements (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        reference_id TEXT NOT NULL,
        reference_type TEXT NOT NULL,
        movement_date TEXT NOT NULL,
        quantity_delta INTEGER NOT NULL,
        balance_after INTEGER NOT NULL,
        unit_cost_paise INTEGER NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_stock_product ON stock_movements(product_id, movement_date);',

    // 26. Ledger Accounts
    '''
    CREATE TABLE IF NOT EXISTS ledger_accounts (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        account_type TEXT NOT NULL,
        is_system_account INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(business_id, code)
    );
    ''',

    // 27. Ledger Entries
    '''
    CREATE TABLE IF NOT EXISTS ledger_entries (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
        transaction_id TEXT NOT NULL,
        transaction_type TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        debit_paise INTEGER NOT NULL DEFAULT 0,
        credit_paise INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        created_at TEXT NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_ledger_account_date ON ledger_entries(account_id, entry_date);',
    'CREATE INDEX IF NOT EXISTS idx_ledger_transaction ON ledger_entries(transaction_id);',

    // 28. Expenses
    '''
    CREATE TABLE IF NOT EXISTS expenses (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        account_id TEXT NOT NULL REFERENCES ledger_accounts(id),
        category TEXT NOT NULL,
        expense_date TEXT NOT NULL,
        amount_paise INTEGER NOT NULL,
        payment_mode TEXT NOT NULL,
        reference_number TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'synced'
    );
    ''',

    // 29. Audit Logs
    '''
    CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        entity_name TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        user_identifier TEXT NOT NULL DEFAULT 'Local Merchant',
        details_json TEXT,
        timestamp TEXT NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(business_id, entity_name, entity_id);',

    // 30. App Settings (Device-local)
    '''
    CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''',

    // 31. Backup Records
    '''
    CREATE TABLE IF NOT EXISTS backup_records (
        id TEXT PRIMARY KEY NOT NULL,
        business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        file_size_bytes INTEGER NOT NULL,
        sha256_checksum TEXT NOT NULL,
        backup_type TEXT NOT NULL,
        database_version INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'VALIDATED'
    );
    '''
  ];
}
