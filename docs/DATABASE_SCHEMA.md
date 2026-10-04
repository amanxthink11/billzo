# Billzo — Database Schema Specification

**Document Version:** 1.0.0  
**Database Engine:** SQLite 3  
**Data Integrity:** Foreign Keys Enabled (`PRAGMA foreign_keys = ON`), Write-Ahead Logging (`PRAGMA journal_mode = WAL`)  
**Key Strategy:** UUIDv4 Primary Keys, Integer Paise (Minor Units) for all monetary fields  

---

## 1. Schema Conventions & Global Columns

To ensure auditability, financial integrity, and zero-conflict future multi-device synchronization:
1. **Primary Keys:** Every entity uses a 36-character UUID string: `id TEXT PRIMARY KEY NOT NULL`.
2. **Multi-Tenancy / Organization:** Business-owned tables include `business_id TEXT NOT NULL REFERENCES businesses(id)`.
3. **Audit Timestamps:** All tables record ISO-8601 UTC timestamp strings: `created_at TEXT NOT NULL`, `updated_at TEXT NOT NULL`.
4. **Soft Deletion / Tombstones:** Master records (Customers, Suppliers, Products) support soft deletes: `deleted_at TEXT DEFAULT NULL`.
5. **Synchronization Metadata:** Every table contains `sync_version INTEGER NOT NULL DEFAULT 1` and `sync_status TEXT NOT NULL DEFAULT 'synced'`.
6. **Monetary Values:** All prices, rates, taxes, totals, discounts, and payments are stored as 64-bit integer paise (e.g. ₹1,250.50 is stored as `125050`). No floats.

---

## 2. Table Definitions

### 2.1 Core Business & Settings

#### `businesses`
Stores merchant organization profiles.
```sql
CREATE TABLE businesses (
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
    state_code TEXT NOT NULL,          -- Indian 2-digit State Code (e.g., '27' for Maharashtra)
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
```

#### `business_settings`
Configurable operational flags and defaults.
```sql
CREATE TABLE business_settings (
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
    thermal_printer_type TEXT NOT NULL DEFAULT 'A4', -- 'A4', '80mm', '58mm'
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
```

#### `invoice_sequences`
Atomic counter sequences for serial numbers (e.g., INV-2026-001).
```sql
CREATE TABLE invoice_sequences (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    document_type TEXT NOT NULL,       -- 'INVOICE', 'ESTIMATE', 'PURCHASE', 'CREDIT_NOTE', 'DEBIT_NOTE'
    prefix TEXT NOT NULL,              -- e.g. 'INV-2026-'
    current_number INTEGER NOT NULL,   -- e.g. 1
    padding_zeros INTEGER NOT NULL DEFAULT 4, -- produces '0001'
    fiscal_year TEXT NOT NULL,         -- '2026-2027'
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(business_id, document_type, fiscal_year)
);
```

---

### 2.2 Masters: Parties, Products, Tax

#### `tax_rates`
Statutory GST tax brackets.
```sql
CREATE TABLE tax_rates (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,                -- 'GST 18%', 'GST 5%', 'GST Exempt'
    rate_basis_points INTEGER NOT NULL,-- 1800 for 18.00%, 500 for 5.00%
    cgst_basis_points INTEGER NOT NULL,-- 900 for 9.00%
    sgst_basis_points INTEGER NOT NULL,-- 900 for 9.00%
    igst_basis_points INTEGER NOT NULL,-- 1800 for 18.00%
    cess_basis_points INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);
```

#### `units`
Units of measurement (UOM).
```sql
CREATE TABLE units (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    code TEXT NOT NULL,                -- 'PCS', 'BOX', 'KG', 'MTR', 'LTR'
    name TEXT NOT NULL,                -- 'Pieces', 'Boxes', 'Kilograms'
    allow_decimal INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    UNIQUE(business_id, code)
);
```

#### `product_categories`
Product classification hierarchy.
```sql
CREATE TABLE product_categories (
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
```

#### `products`
Item catalog master.
```sql
CREATE TABLE products (
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
    selling_price_paise INTEGER NOT NULL,     -- In integer paise
    purchase_price_paise INTEGER NOT NULL DEFAULT 0,
    mrp_paise INTEGER NOT NULL DEFAULT 0,
    is_tax_inclusive INTEGER NOT NULL DEFAULT 0,
    track_inventory INTEGER NOT NULL DEFAULT 1,
    current_stock INTEGER NOT NULL DEFAULT 0, -- Scaled by unit decimal factor
    low_stock_threshold INTEGER NOT NULL DEFAULT 5,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);
CREATE INDEX idx_products_barcode ON products(business_id, barcode);
CREATE INDEX idx_products_sku ON products(business_id, sku);
CREATE INDEX idx_products_name ON products(business_id, name);
```

#### `customers` & `suppliers`
Stakeholder relationship records.
```sql
CREATE TABLE customers (
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
    billing_state_code TEXT NOT NULL,   -- Indian 2-digit State Code
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
    opening_balance_type TEXT NOT NULL DEFAULT 'RECEIVABLE', -- 'RECEIVABLE', 'PAYABLE'
    current_balance_paise INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);
CREATE INDEX idx_customers_phone ON customers(business_id, phone);
CREATE INDEX idx_customers_name ON customers(business_id, name);

CREATE TABLE suppliers (
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
CREATE INDEX idx_suppliers_name ON suppliers(business_id, name);
```

---

### 2.3 Sales, Invoices & Estimates

#### `invoices`
Tax Invoices and Bills of Supply.
```sql
CREATE TABLE invoices (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    customer_id TEXT NOT NULL REFERENCES customers(id),
    recurring_invoice_id TEXT,         -- Nullable reference to originating recurring schedule
    invoice_number TEXT NOT NULL,      -- e.g. 'INV-2026-0001'
    invoice_date TEXT NOT NULL,        -- 'YYYY-MM-DD'
    due_date TEXT NOT NULL,            -- 'YYYY-MM-DD'
    place_of_supply_state_code TEXT NOT NULL,
    invoice_type TEXT NOT NULL DEFAULT 'TAX_INVOICE', -- 'TAX_INVOICE', 'BILL_OF_SUPPLY'
    status TEXT NOT NULL DEFAULT 'DRAFT',            -- 'DRAFT', 'FINALIZED', 'PARTIAL', 'PAID', 'CANCELLED'
    
    -- Financial Totals (all in integer paise)
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
CREATE INDEX idx_invoices_date ON invoices(business_id, invoice_date);
CREATE INDEX idx_invoices_customer ON invoices(business_id, customer_id);
CREATE INDEX idx_invoices_status ON invoices(business_id, status);
```

#### `invoice_items`
Individual line items in an invoice.
```sql
CREATE TABLE invoice_items (
    id TEXT PRIMARY KEY NOT NULL,
    invoice_id TEXT NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES products(id),
    tax_rate_id TEXT NOT NULL REFERENCES tax_rates(id),
    product_name TEXT NOT NULL,
    hsn_sac TEXT,
    quantity INTEGER NOT NULL,          -- Quantity * 1000 to support up to 3 decimals
    unit_code TEXT NOT NULL,
    rate_paise INTEGER NOT NULL,        -- Base unit rate in paise
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
CREATE INDEX idx_invoice_items_invoice ON invoice_items(invoice_id);
```

#### `estimates` & `estimate_items`
Quotations / Estimates convertible into invoices.
```sql
CREATE TABLE estimates (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    customer_id TEXT NOT NULL REFERENCES customers(id),
    estimate_number TEXT NOT NULL,
    estimate_date TEXT NOT NULL,
    expiry_date TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE', -- 'ACTIVE', 'CONVERTED', 'EXPIRED', 'REJECTED'
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

CREATE TABLE estimate_items (
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
```

---

### 2.4 Recurring Invoices Engine

#### `recurring_invoices`
Recurring billing schedule configurations.
```sql
CREATE TABLE recurring_invoices (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    customer_id TEXT NOT NULL REFERENCES customers(id),
    profile_name TEXT NOT NULL,        -- e.g., 'Monthly Retainer - ABC Tech'
    frequency TEXT NOT NULL,           -- 'DAILY', 'WEEKLY', 'BI_WEEKLY', 'MONTHLY', 'QUARTERLY', 'HALF_YEARLY', 'YEARLY', 'CUSTOM'
    custom_interval_days INTEGER,
    start_date TEXT NOT NULL,          -- 'YYYY-MM-DD'
    end_date TEXT,                     -- Nullable for indefinite
    next_run_date TEXT NOT NULL,       -- 'YYYY-MM-DD'
    last_run_date TEXT,
    payment_terms_days INTEGER NOT NULL DEFAULT 15,
    auto_generate INTEGER NOT NULL DEFAULT 0, -- 1 = auto create finalized, 0 = create review draft
    require_review INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'ACTIVE',    -- 'ACTIVE', 'PAUSED', 'COMPLETED', 'CANCELLED'
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);
CREATE INDEX idx_recurring_next_run ON recurring_invoices(business_id, status, next_run_date);
```

#### `recurring_invoice_items`
Item line template for recurring runs.
```sql
CREATE TABLE recurring_invoice_items (
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
```

#### `recurring_invoice_executions`
Execution logs preventing duplicate invoice generation for the same scheduled period (idempotency key).
```sql
CREATE TABLE recurring_invoice_executions (
    id TEXT PRIMARY KEY NOT NULL,
    recurring_invoice_id TEXT NOT NULL REFERENCES recurring_invoices(id) ON DELETE CASCADE,
    invoice_id TEXT REFERENCES invoices(id),
    scheduled_for_date TEXT NOT NULL,  -- 'YYYY-MM-DD' of the scheduled milestone
    executed_at TEXT NOT NULL,         -- Actual timestamp when created
    execution_status TEXT NOT NULL,    -- 'SUCCESS', 'SKIPPED', 'REVIEW_QUEUED'
    notes TEXT,
    created_at TEXT NOT NULL,
    UNIQUE(recurring_invoice_id, scheduled_for_date) -- Idempotency guarantee
);
```

---

### 2.5 Payments & Allocations

#### `payments`
Inward (customer receipt) and outward (supplier payment) transaction records.
```sql
CREATE TABLE payments (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    party_id TEXT NOT NULL,            -- Can reference customer_id or supplier_id
    party_type TEXT NOT NULL,          -- 'CUSTOMER', 'SUPPLIER'
    payment_type TEXT NOT NULL,        -- 'RECEIPT' (inward), 'PAYMENT' (outward)
    payment_number TEXT NOT NULL,      -- e.g. 'REC-2026-0001'
    payment_date TEXT NOT NULL,
    payment_mode TEXT NOT NULL,        -- 'CASH', 'UPI', 'BANK_TRANSFER', 'CHEQUE'
    amount_paise INTEGER NOT NULL,
    reference_number TEXT,             -- Cheque no., UTR no., UPI txn ID
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    UNIQUE(business_id, payment_number)
);
CREATE INDEX idx_payments_party ON payments(business_id, party_id, payment_date);
```

#### `payment_allocations`
Maps payments directly to specific invoices/bills.
```sql
CREATE TABLE payment_allocations (
    id TEXT PRIMARY KEY NOT NULL,
    payment_id TEXT NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    document_id TEXT NOT NULL,         -- References invoices(id) or purchases(id)
    document_type TEXT NOT NULL,       -- 'INVOICE', 'PURCHASE'
    allocated_amount_paise INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_payment_allocations_doc ON payment_allocations(document_id);
```

---

### 2.6 Purchases, Returns & Stock Movements

#### `purchases` & `purchase_items`
```sql
CREATE TABLE purchases (
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

CREATE TABLE purchase_items (
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
```

#### `sales_returns` & `purchase_returns`
Credit notes and debit notes with item lines.
```sql
CREATE TABLE sales_returns (
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

CREATE TABLE sales_return_items (
    id TEXT PRIMARY KEY NOT NULL,
    sales_return_id TEXT NOT NULL REFERENCES sales_returns(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL,
    rate_paise INTEGER NOT NULL,
    total_amount_paise INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE purchase_returns (
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

CREATE TABLE purchase_return_items (
    id TEXT PRIMARY KEY NOT NULL,
    purchase_return_id TEXT NOT NULL REFERENCES purchase_returns(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL,
    rate_paise INTEGER NOT NULL,
    total_amount_paise INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

#### `stock_movements`
Immutable append-only ledger for all physical stock alterations.
```sql
CREATE TABLE stock_movements (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    reference_id TEXT NOT NULL,        -- invoice_id, purchase_id, return_id, or adjustment_id
    reference_type TEXT NOT NULL,      -- 'SALE', 'PURCHASE', 'SALE_RETURN', 'PURCHASE_RETURN', 'ADJUSTMENT', 'OPENING_STOCK'
    movement_date TEXT NOT NULL,
    quantity_delta INTEGER NOT NULL,   -- Positive for incoming stock, negative for outgoing stock (scaled by 1000)
    balance_after INTEGER NOT NULL,    -- Running balance after movement
    unit_cost_paise INTEGER NOT NULL,
    notes TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX idx_stock_product ON stock_movements(product_id, movement_date);
```

---

### 2.7 Financial Accounting & Ledgers

#### `ledger_accounts` & `ledger_entries`
Double-entry bookkeeping accounts and balanced journal entries.
```sql
CREATE TABLE ledger_accounts (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    code TEXT NOT NULL,                -- e.g. '1001-CASH', '2001-ACCOUNTS-RECEIVABLE'
    name TEXT NOT NULL,
    account_type TEXT NOT NULL,        -- 'ASSET', 'LIABILITY', 'EQUITY', 'INCOME', 'EXPENSE'
    is_system_account INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(business_id, code)
);

CREATE TABLE ledger_entries (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
    transaction_id TEXT NOT NULL,      -- Associated document id (invoice, payment, expense)
    transaction_type TEXT NOT NULL,    -- 'INVOICE', 'PAYMENT', 'PURCHASE', 'EXPENSE'
    entry_date TEXT NOT NULL,
    debit_paise INTEGER NOT NULL DEFAULT 0,
    credit_paise INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX idx_ledger_account_date ON ledger_entries(account_id, entry_date);
CREATE INDEX idx_ledger_transaction ON ledger_entries(transaction_id);
```

#### `expenses`
```sql
CREATE TABLE expenses (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL REFERENCES ledger_accounts(id),
    category TEXT NOT NULL,            -- 'Rent', 'Utilities', 'Salaries', 'Travel', 'Office'
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
```

---

### 2.8 Audit, Configuration & Backups

#### `audit_logs`
Chronological activity trail.
```sql
CREATE TABLE audit_logs (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    entity_name TEXT NOT NULL,         -- 'INVOICE', 'PAYMENT', 'PRODUCT', 'BACKUP'
    entity_id TEXT NOT NULL,
    action TEXT NOT NULL,              -- 'CREATE', 'FINALIZE', 'CANCEL', 'UPDATE', 'RESTORE'
    user_identifier TEXT NOT NULL DEFAULT 'Local Merchant',
    details_json TEXT,
    timestamp TEXT NOT NULL
);
CREATE INDEX idx_audit_entity ON audit_logs(business_id, entity_name, entity_id);
```

#### `app_settings`
Device-local application preferences (not synchronized across businesses).
```sql
CREATE TABLE app_settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

#### `backup_records`
Catalog of local and external backup archives.
```sql
CREATE TABLE backup_records (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    file_size_bytes INTEGER NOT NULL,
    sha256_checksum TEXT NOT NULL,
    backup_type TEXT NOT NULL,         -- 'MANUAL', 'AUTOMATIC'
    database_version INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'VALIDATED' -- 'VALIDATED', 'CORRUPT'
);
```
