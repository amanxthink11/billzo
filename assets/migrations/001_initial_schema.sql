-- ==============================================================================
-- BILLZO DATABASE MIGRATION: 001_initial_schema.sql
-- Matches docs/DATABASE_SCHEMA.md exactly.
-- ==============================================================================

-- 1. Businesses
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

-- 2. Business Settings
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
    enable_e_invoicing INTEGER NOT NULL DEFAULT 0,
    enable_e_way_bill INTEGER NOT NULL DEFAULT 0,
    enable_composition_scheme INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 3. App Settings (Global device configuration)
CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- 4. Parties (Customers & Suppliers)
CREATE TABLE IF NOT EXISTS parties (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    company_name TEXT,
    party_type TEXT NOT NULL CHECK(party_type IN ('customer', 'supplier', 'both')),
    phone TEXT,
    email TEXT,
    gstin TEXT,
    pan TEXT,
    billing_address_line1 TEXT,
    billing_address_line2 TEXT,
    billing_city TEXT,
    billing_state_code TEXT,
    billing_state_name TEXT,
    billing_pincode TEXT,
    shipping_address_line1 TEXT,
    shipping_address_line2 TEXT,
    shipping_city TEXT,
    shipping_state_code TEXT,
    shipping_state_name TEXT,
    shipping_pincode TEXT,
    credit_limit_paise INTEGER NOT NULL DEFAULT 0,
    credit_period_days INTEGER NOT NULL DEFAULT 0,
    opening_balance_paise INTEGER NOT NULL DEFAULT 0,
    opening_balance_type TEXT NOT NULL DEFAULT 'to_receive' CHECK(opening_balance_type IN ('to_receive', 'to_pay')),
    current_balance_paise INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 5. Categories
CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    parent_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    description TEXT,
    color_hex TEXT,
    icon_name TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 6. Units
CREATE TABLE IF NOT EXISTS units (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    short_name TEXT NOT NULL,
    is_decimal_allowed INTEGER NOT NULL DEFAULT 0,
    decimal_places INTEGER NOT NULL DEFAULT 0,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 7. Tax Rates
CREATE TABLE IF NOT EXISTS tax_rates (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    rate_basis_points INTEGER NOT NULL,
    cgst_basis_points INTEGER NOT NULL,
    sgst_basis_points INTEGER NOT NULL,
    igst_basis_points INTEGER NOT NULL,
    cess_basis_points INTEGER NOT NULL DEFAULT 0,
    is_default INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 8. Products
CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
    unit_id TEXT NOT NULL REFERENCES units(id),
    tax_rate_id TEXT REFERENCES tax_rates(id),
    name TEXT NOT NULL,
    sku TEXT,
    barcode TEXT,
    hsn_sac_code TEXT,
    description TEXT,
    item_type TEXT NOT NULL DEFAULT 'product' CHECK(item_type IN ('product', 'service')),
    purchase_price_paise INTEGER NOT NULL DEFAULT 0,
    selling_price_paise INTEGER NOT NULL DEFAULT 0,
    mrp_paise INTEGER,
    minimum_selling_price_paise INTEGER,
    wholesale_price_paise INTEGER,
    is_tax_inclusive INTEGER NOT NULL DEFAULT 0,
    opening_stock REAL NOT NULL DEFAULT 0,
    current_stock REAL NOT NULL DEFAULT 0,
    low_stock_threshold REAL,
    image_path TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 9. Product Batches
CREATE TABLE IF NOT EXISTS product_batches (
    id TEXT PRIMARY KEY NOT NULL,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    batch_number TEXT NOT NULL,
    manufacturing_date TEXT,
    expiry_date TEXT,
    purchase_price_paise INTEGER NOT NULL DEFAULT 0,
    selling_price_paise INTEGER NOT NULL DEFAULT 0,
    mrp_paise INTEGER,
    quantity_available REAL NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 10. Serial Numbers
CREATE TABLE IF NOT EXISTS product_serial_numbers (
    id TEXT PRIMARY KEY NOT NULL,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    serial_number TEXT NOT NULL,
    batch_id TEXT REFERENCES product_batches(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'available' CHECK(status IN ('available', 'sold', 'defective', 'returned')),
    invoice_item_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 11. Invoice Sequences
CREATE TABLE IF NOT EXISTS invoice_sequences (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    document_type TEXT NOT NULL CHECK(document_type IN ('invoice', 'quotation', 'purchase_order', 'credit_note', 'debit_note', 'delivery_challan', 'payment_receipt')),
    prefix TEXT NOT NULL DEFAULT 'INV-',
    suffix TEXT,
    current_sequence INTEGER NOT NULL DEFAULT 0,
    padding_digits INTEGER NOT NULL DEFAULT 4,
    financial_year TEXT NOT NULL,
    is_default INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    UNIQUE(business_id, document_type, financial_year, prefix)
);

-- 12. Invoices
CREATE TABLE IF NOT EXISTS invoices (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    party_id TEXT REFERENCES parties(id),
    sequence_id TEXT REFERENCES invoice_sequences(id),
    invoice_number TEXT NOT NULL,
    reference_number TEXT,
    invoice_type TEXT NOT NULL DEFAULT 'tax_invoice' CHECK(invoice_type IN ('tax_invoice', 'bill_of_supply', 'proforma', 'quotation', 'credit_note', 'debit_note', 'delivery_challan')),
    status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft', 'unpaid', 'partially_paid', 'paid', 'overdue', 'cancelled')),
    invoice_date TEXT NOT NULL,
    due_date TEXT NOT NULL,
    place_of_supply_state_code TEXT NOT NULL,
    place_of_supply_state_name TEXT NOT NULL,
    is_interstate INTEGER NOT NULL DEFAULT 0,
    is_reverse_charge INTEGER NOT NULL DEFAULT 0,
    subtotal_paise INTEGER NOT NULL DEFAULT 0,
    item_discount_paise INTEGER NOT NULL DEFAULT 0,
    invoice_discount_type TEXT CHECK(invoice_discount_type IN ('percentage', 'fixed')),
    invoice_discount_value INTEGER NOT NULL DEFAULT 0,
    invoice_discount_paise INTEGER NOT NULL DEFAULT 0,
    total_taxable_paise INTEGER NOT NULL DEFAULT 0,
    cgst_paise INTEGER NOT NULL DEFAULT 0,
    sgst_paise INTEGER NOT NULL DEFAULT 0,
    igst_paise INTEGER NOT NULL DEFAULT 0,
    cess_paise INTEGER NOT NULL DEFAULT 0,
    round_off_paise INTEGER NOT NULL DEFAULT 0,
    total_amount_paise INTEGER NOT NULL DEFAULT 0,
    paid_amount_paise INTEGER NOT NULL DEFAULT 0,
    balance_amount_paise INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    terms_conditions TEXT,
    lut_number TEXT,
    e_way_bill_number TEXT,
    irn TEXT,
    irn_ack_date TEXT,
    irn_ack_number TEXT,
    signed_qr_code TEXT,
    cancel_reason TEXT,
    cancelled_at TEXT,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    UNIQUE(business_id, invoice_number)
);

-- 13. Invoice Items
CREATE TABLE IF NOT EXISTS invoice_items (
    id TEXT PRIMARY KEY NOT NULL,
    invoice_id TEXT NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    product_id TEXT REFERENCES products(id),
    batch_id TEXT REFERENCES product_batches(id),
    item_name TEXT NOT NULL,
    description TEXT,
    hsn_sac_code TEXT,
    unit_id TEXT REFERENCES units(id),
    unit_name TEXT NOT NULL,
    quantity REAL NOT NULL,
    unit_price_paise INTEGER NOT NULL,
    mrp_paise INTEGER,
    discount_type TEXT CHECK(discount_type IN ('percentage', 'fixed')),
    discount_value INTEGER NOT NULL DEFAULT 0,
    discount_paise INTEGER NOT NULL DEFAULT 0,
    taxable_amount_paise INTEGER NOT NULL,
    tax_rate_id TEXT REFERENCES tax_rates(id),
    rate_basis_points INTEGER NOT NULL DEFAULT 0,
    cgst_paise INTEGER NOT NULL DEFAULT 0,
    sgst_paise INTEGER NOT NULL DEFAULT 0,
    igst_paise INTEGER NOT NULL DEFAULT 0,
    cess_paise INTEGER NOT NULL DEFAULT 0,
    total_amount_paise INTEGER NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 14. Purchases
CREATE TABLE IF NOT EXISTS purchases (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    party_id TEXT REFERENCES parties(id),
    purchase_number TEXT NOT NULL,
    vendor_invoice_number TEXT,
    vendor_invoice_date TEXT,
    status TEXT NOT NULL DEFAULT 'received' CHECK(status IN ('ordered', 'received', 'partially_received', 'cancelled')),
    payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK(payment_status IN ('unpaid', 'partially_paid', 'paid')),
    purchase_date TEXT NOT NULL,
    due_date TEXT,
    place_of_supply_state_code TEXT NOT NULL,
    is_interstate INTEGER NOT NULL DEFAULT 0,
    subtotal_paise INTEGER NOT NULL DEFAULT 0,
    taxable_amount_paise INTEGER NOT NULL DEFAULT 0,
    cgst_paise INTEGER NOT NULL DEFAULT 0,
    sgst_paise INTEGER NOT NULL DEFAULT 0,
    igst_paise INTEGER NOT NULL DEFAULT 0,
    cess_paise INTEGER NOT NULL DEFAULT 0,
    round_off_paise INTEGER NOT NULL DEFAULT 0,
    total_amount_paise INTEGER NOT NULL DEFAULT 0,
    paid_amount_paise INTEGER NOT NULL DEFAULT 0,
    balance_amount_paise INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 15. Purchase Items
CREATE TABLE IF NOT EXISTS purchase_items (
    id TEXT PRIMARY KEY NOT NULL,
    purchase_id TEXT NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
    product_id TEXT REFERENCES products(id),
    batch_number TEXT,
    manufacturing_date TEXT,
    expiry_date TEXT,
    item_name TEXT NOT NULL,
    hsn_sac_code TEXT,
    unit_id TEXT REFERENCES units(id),
    unit_name TEXT NOT NULL,
    quantity REAL NOT NULL,
    unit_cost_paise INTEGER NOT NULL,
    discount_paise INTEGER NOT NULL DEFAULT 0,
    taxable_amount_paise INTEGER NOT NULL,
    tax_rate_id TEXT REFERENCES tax_rates(id),
    rate_basis_points INTEGER NOT NULL DEFAULT 0,
    cgst_paise INTEGER NOT NULL DEFAULT 0,
    sgst_paise INTEGER NOT NULL DEFAULT 0,
    igst_paise INTEGER NOT NULL DEFAULT 0,
    cess_paise INTEGER NOT NULL DEFAULT 0,
    total_amount_paise INTEGER NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 16. Inventory Ledger
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    batch_id TEXT REFERENCES product_batches(id),
    transaction_type TEXT NOT NULL CHECK(transaction_type IN ('purchase', 'sale', 'purchase_return', 'sale_return', 'adjustment_in', 'adjustment_out', 'damage', 'opening_stock')),
    reference_type TEXT CHECK(reference_type IN ('invoice', 'purchase', 'credit_note', 'debit_note', 'stock_adjustment', 'manual')),
    reference_id TEXT,
    quantity_changed REAL NOT NULL,
    stock_before REAL NOT NULL,
    stock_after REAL NOT NULL,
    cost_per_unit_paise INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    transaction_date TEXT NOT NULL,
    created_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 17. Payment Methods
CREATE TABLE IF NOT EXISTS payment_methods (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('cash', 'bank_transfer', 'cheque', 'upi', 'card', 'other')),
    account_number TEXT,
    ifsc TEXT,
    upi_id TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 18. Payments
CREATE TABLE IF NOT EXISTS payments (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    party_id TEXT REFERENCES parties(id),
    payment_number TEXT NOT NULL,
    payment_type TEXT NOT NULL CHECK(payment_type IN ('payment_in', 'payment_out')),
    amount_paise INTEGER NOT NULL,
    payment_date TEXT NOT NULL,
    payment_method_id TEXT REFERENCES payment_methods(id),
    reference_number TEXT,
    cheque_number TEXT,
    cheque_date TEXT,
    bank_name TEXT,
    notes TEXT,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 19. Payment Allocations
CREATE TABLE IF NOT EXISTS payment_allocations (
    id TEXT PRIMARY KEY NOT NULL,
    payment_id TEXT NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    document_type TEXT NOT NULL CHECK(document_type IN ('invoice', 'purchase')),
    document_id TEXT NOT NULL,
    allocated_amount_paise INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 20. Expense Categories
CREATE TABLE IF NOT EXISTS expense_categories (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    code TEXT,
    is_tax_deductible INTEGER NOT NULL DEFAULT 1,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 21. Expenses
CREATE TABLE IF NOT EXISTS expenses (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    category_id TEXT NOT NULL REFERENCES expense_categories(id),
    payment_method_id TEXT REFERENCES payment_methods(id),
    expense_number TEXT NOT NULL,
    expense_date TEXT NOT NULL,
    amount_paise INTEGER NOT NULL,
    taxable_amount_paise INTEGER NOT NULL DEFAULT 0,
    cgst_paise INTEGER NOT NULL DEFAULT 0,
    sgst_paise INTEGER NOT NULL DEFAULT 0,
    igst_paise INTEGER NOT NULL DEFAULT 0,
    cess_paise INTEGER NOT NULL DEFAULT 0,
    gstin_of_vendor TEXT,
    vendor_name TEXT,
    description TEXT,
    receipt_image_path TEXT,
    is_recurring INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 22. Chart of Accounts
CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    parent_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
    account_code TEXT NOT NULL,
    account_name TEXT NOT NULL,
    account_type TEXT NOT NULL CHECK(account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
    is_system INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    UNIQUE(business_id, account_code)
);

-- 23. Journal Entries
CREATE TABLE IF NOT EXISTS journal_entries (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    entry_number TEXT NOT NULL,
    entry_date TEXT NOT NULL,
    narration TEXT,
    reference_type TEXT,
    reference_id TEXT,
    is_reversed INTEGER NOT NULL DEFAULT 0,
    reversed_by_id TEXT REFERENCES journal_entries(id),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 24. Journal Entry Lines
CREATE TABLE IF NOT EXISTS journal_entry_lines (
    id TEXT PRIMARY KEY NOT NULL,
    journal_entry_id TEXT NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL REFERENCES accounts(id),
    debit_paise INTEGER NOT NULL DEFAULT 0,
    credit_paise INTEGER NOT NULL DEFAULT 0,
    line_narration TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    CHECK((debit_paise > 0 AND credit_paise = 0) OR (credit_paise > 0 AND debit_paise = 0))
);

-- 25. Recurring Invoices
CREATE TABLE IF NOT EXISTS recurring_invoices (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    party_id TEXT NOT NULL REFERENCES parties(id),
    template_name TEXT NOT NULL,
    frequency TEXT NOT NULL CHECK(frequency IN ('daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'half_yearly', 'yearly')),
    start_date TEXT NOT NULL,
    end_date TEXT,
    last_generated_date TEXT,
    next_due_date TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    auto_generate INTEGER NOT NULL DEFAULT 0,
    auto_send_email INTEGER NOT NULL DEFAULT 0,
    auto_send_whatsapp INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 26. Recurring Invoice Items
CREATE TABLE IF NOT EXISTS recurring_invoice_items (
    id TEXT PRIMARY KEY NOT NULL,
    recurring_invoice_id TEXT NOT NULL REFERENCES recurring_invoices(id) ON DELETE CASCADE,
    product_id TEXT REFERENCES products(id),
    item_name TEXT NOT NULL,
    description TEXT,
    hsn_sac_code TEXT,
    unit_id TEXT REFERENCES units(id),
    unit_name TEXT NOT NULL,
    quantity REAL NOT NULL,
    unit_price_paise INTEGER NOT NULL,
    discount_paise INTEGER NOT NULL DEFAULT 0,
    tax_rate_id TEXT REFERENCES tax_rates(id),
    rate_basis_points INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 27. Delivery Challans
CREATE TABLE IF NOT EXISTS delivery_challans (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    party_id TEXT NOT NULL REFERENCES parties(id),
    challan_number TEXT NOT NULL,
    challan_date TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'converted_to_invoice', 'cancelled')),
    transport_mode TEXT,
    vehicle_number TEXT,
    notes TEXT,
    invoice_id TEXT REFERENCES invoices(id),
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- 28. Audit Logs
CREATE TABLE IF NOT EXISTS audit_logs (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT REFERENCES businesses(id) ON DELETE CASCADE,
    user_id TEXT,
    action TEXT NOT NULL,
    entity_name TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    changes_json TEXT,
    ip_address TEXT,
    device_info TEXT,
    created_at TEXT NOT NULL
);

-- 29. Sync Queue
CREATE TABLE IF NOT EXISTS sync_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    operation TEXT NOT NULL CHECK(operation IN ('INSERT', 'UPDATE', 'DELETE')),
    payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT
);

-- 30. Backups
CREATE TABLE IF NOT EXISTS backups (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    backup_type TEXT NOT NULL CHECK(backup_type IN ('manual', 'auto', 'scheduled')),
    file_size_bytes INTEGER NOT NULL,
    checksum_sha256 TEXT NOT NULL,
    is_encrypted INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
);

-- 31. Schema Migrations (Internal tracker)
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY NOT NULL,
    description TEXT NOT NULL,
    applied_at TEXT NOT NULL,
    checksum TEXT NOT NULL
);

-- Performance & Integrity Indexes
CREATE INDEX IF NOT EXISTS idx_parties_business_type ON parties(business_id, party_type, is_active);
CREATE INDEX IF NOT EXISTS idx_products_business_active ON products(business_id, is_active, is_deleted);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(business_id, barcode);
CREATE INDEX IF NOT EXISTS idx_invoices_business_date ON invoices(business_id, invoice_date, status);
CREATE INDEX IF NOT EXISTS idx_invoices_party ON invoices(party_id, invoice_date);
CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items(invoice_id);
CREATE INDEX IF NOT EXISTS idx_purchases_business_date ON purchases(business_id, purchase_date);
CREATE INDEX IF NOT EXISTS idx_inventory_product_date ON inventory_ledger(product_id, transaction_date);
CREATE INDEX IF NOT EXISTS idx_payments_party_date ON payments(party_id, payment_date);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_entry_lines(account_id);
