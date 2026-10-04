-- ==============================================================================
-- BILLZO DATABASE MIGRATION: 005_expenses.sql
-- Expenses, Expense Categories, and Financial Reporting Enhancements
-- ==============================================================================

-- 1. Create expense_categories table
CREATE TABLE IF NOT EXISTS expense_categories (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    account_code TEXT NOT NULL DEFAULT '5100',
    description TEXT,
    is_predefined INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    UNIQUE(business_id, name)
);

-- 2. Add columns to expenses table
ALTER TABLE expenses ADD COLUMN expense_number TEXT;
ALTER TABLE expenses ADD COLUMN category_id TEXT REFERENCES expense_categories(id);
ALTER TABLE expenses ADD COLUMN payee TEXT;
ALTER TABLE expenses ADD COLUMN description TEXT;
ALTER TABLE expenses ADD COLUMN taxable_amount_paise INTEGER NOT NULL DEFAULT 0;
ALTER TABLE expenses ADD COLUMN cgst_paise INTEGER NOT NULL DEFAULT 0;
ALTER TABLE expenses ADD COLUMN sgst_paise INTEGER NOT NULL DEFAULT 0;
ALTER TABLE expenses ADD COLUMN igst_paise INTEGER NOT NULL DEFAULT 0;
ALTER TABLE expenses ADD COLUMN total_gst_paise INTEGER NOT NULL DEFAULT 0;
ALTER TABLE expenses ADD COLUMN total_amount_paise INTEGER NOT NULL DEFAULT 0;
ALTER TABLE expenses ADD COLUMN payment_account_id TEXT REFERENCES cash_bank_accounts(id);
ALTER TABLE expenses ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'CASH';
ALTER TABLE expenses ADD COLUMN status TEXT NOT NULL DEFAULT 'DRAFT';
ALTER TABLE expenses ADD COLUMN posted_at TEXT;
ALTER TABLE expenses ADD COLUMN cancelled_at TEXT;
ALTER TABLE expenses ADD COLUMN cancellation_reason TEXT;
ALTER TABLE expenses ADD COLUMN deleted_at TEXT;

-- 3. Performance & lookup indexes
CREATE INDEX IF NOT EXISTS idx_expense_categories_biz ON expense_categories(business_id, is_active);
CREATE INDEX IF NOT EXISTS idx_expenses_biz_status ON expenses(business_id, status);
CREATE INDEX IF NOT EXISTS idx_expenses_biz_date ON expenses(business_id, expense_date);
CREATE INDEX IF NOT EXISTS idx_expenses_biz_number ON expenses(business_id, expense_number);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category_id);
CREATE INDEX IF NOT EXISTS idx_expenses_account ON expenses(payment_account_id);
