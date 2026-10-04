-- ==============================================================================
-- BILLZO DATABASE MIGRATION: 003_payments.sql
-- Payments, Payment Allocations enhancements, and Cash/Bank accounts
-- ==============================================================================

-- 1. Create cash_bank_accounts table
CREATE TABLE IF NOT EXISTS cash_bank_accounts (
    id TEXT PRIMARY KEY NOT NULL,
    business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    account_type TEXT NOT NULL,
    account_number TEXT,
    bank_name TEXT,
    ifsc_code TEXT,
    opening_balance_paise INTEGER NOT NULL DEFAULT 0,
    current_balance_paise INTEGER NOT NULL DEFAULT 0,
    is_default INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    ledger_account_id TEXT REFERENCES ledger_accounts(id),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'synced'
);
CREATE INDEX IF NOT EXISTS idx_cash_bank_business ON cash_bank_accounts(business_id, is_active);

-- 2. Add status, account_id, and cancellation metadata to payments table
ALTER TABLE payments ADD COLUMN status TEXT NOT NULL DEFAULT 'POSTED';
ALTER TABLE payments ADD COLUMN account_id TEXT REFERENCES cash_bank_accounts(id);
ALTER TABLE payments ADD COLUMN cancelled_at TEXT;
ALTER TABLE payments ADD COLUMN cancellation_reason TEXT;
ALTER TABLE payments ADD COLUMN deleted_at TEXT;

-- 3. Performance & query indexes
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(business_id, status);
CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(business_id, payment_date);
CREATE INDEX IF NOT EXISTS idx_payments_number ON payments(business_id, payment_number);
CREATE INDEX IF NOT EXISTS idx_payment_allocations_payment ON payment_allocations(payment_id);
