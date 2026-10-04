/// Version 4 Migration: Purchases, Purchase Items, Purchase Returns (Debit Notes),
/// and Input Tax Credit (ITC) tracking enhancements.
class Migration004Purchases {
  Migration004Purchases._();

  static const int version = 4;
  static const String description = '004_purchases_and_ap';

  static const List<String> statements = [
    // 1. Add supplier invoice metadata, ITC tracking, and cancellation fields to purchases
    'ALTER TABLE purchases ADD COLUMN supplier_invoice_number TEXT;',
    'ALTER TABLE purchases ADD COLUMN supplier_invoice_date TEXT;',
    'ALTER TABLE purchases ADD COLUMN place_of_supply_state_code TEXT;',
    'ALTER TABLE purchases ADD COLUMN cess_paise INTEGER NOT NULL DEFAULT 0;',
    "ALTER TABLE purchases ADD COLUMN itc_eligibility TEXT NOT NULL DEFAULT 'ELIGIBLE';",
    'ALTER TABLE purchases ADD COLUMN input_cgst_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchases ADD COLUMN input_sgst_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchases ADD COLUMN input_igst_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchases ADD COLUMN input_cess_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchases ADD COLUMN finalized_at TEXT;',
    'ALTER TABLE purchases ADD COLUMN cancelled_at TEXT;',
    'ALTER TABLE purchases ADD COLUMN cancellation_reason TEXT;',
    'ALTER TABLE purchases ADD COLUMN deleted_at TEXT;',

    // 2. Add item metadata, discount, basis points, ITC eligibility, and inventory tracking to purchase_items
    'ALTER TABLE purchase_items ADD COLUMN product_name TEXT;',
    'ALTER TABLE purchase_items ADD COLUMN description TEXT;',
    'ALTER TABLE purchase_items ADD COLUMN hsn_sac TEXT;',
    'ALTER TABLE purchase_items ADD COLUMN discount_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_items ADD COLUMN rate_basis_points INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_items ADD COLUMN cgst_rate_basis_points INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_items ADD COLUMN sgst_rate_basis_points INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_items ADD COLUMN igst_rate_basis_points INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_items ADD COLUMN cess_rate_basis_points INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_items ADD COLUMN cess_amount_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_items ADD COLUMN is_tax_inclusive INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_items ADD COLUMN is_itc_eligible INTEGER NOT NULL DEFAULT 1;',
    'ALTER TABLE purchase_items ADD COLUMN track_inventory INTEGER NOT NULL DEFAULT 1;',

    // 3. Add tax breakdown, cancellation metadata, and status to purchase_returns
    'ALTER TABLE purchase_returns ADD COLUMN taxable_amount_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_returns ADD COLUMN cgst_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_returns ADD COLUMN sgst_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_returns ADD COLUMN igst_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_returns ADD COLUMN cess_paise INTEGER NOT NULL DEFAULT 0;',
    "ALTER TABLE purchase_returns ADD COLUMN status TEXT NOT NULL DEFAULT 'FINALIZED';",
    'ALTER TABLE purchase_returns ADD COLUMN cancelled_at TEXT;',
    'ALTER TABLE purchase_returns ADD COLUMN cancellation_reason TEXT;',
    'ALTER TABLE purchase_returns ADD COLUMN deleted_at TEXT;',

    // 4. Add tax columns and purchase_item reference to purchase_return_items
    'ALTER TABLE purchase_return_items ADD COLUMN purchase_item_id TEXT;',
    'ALTER TABLE purchase_return_items ADD COLUMN product_name TEXT;',
    'ALTER TABLE purchase_return_items ADD COLUMN unit_code TEXT;',
    'ALTER TABLE purchase_return_items ADD COLUMN taxable_amount_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_return_items ADD COLUMN cgst_amount_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_return_items ADD COLUMN sgst_amount_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_return_items ADD COLUMN igst_amount_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_return_items ADD COLUMN cess_amount_paise INTEGER NOT NULL DEFAULT 0;',
    'ALTER TABLE purchase_return_items ADD COLUMN tax_rate_basis_points INTEGER NOT NULL DEFAULT 0;',

    // 5. Performance and lookup indexes
    'CREATE INDEX IF NOT EXISTS idx_purchases_business_status ON purchases(business_id, status);',
    'CREATE INDEX IF NOT EXISTS idx_purchases_business_date ON purchases(business_id, purchase_date);',
    'CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON purchases(business_id, supplier_id);',
    'CREATE INDEX IF NOT EXISTS idx_purchases_supplier_inv ON purchases(business_id, supplier_id, vendor_invoice_number);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_returns_business ON purchase_returns(business_id, return_date);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_returns_orig ON purchase_returns(original_purchase_id);',
    'CREATE INDEX IF NOT EXISTS idx_purchase_return_items_ret ON purchase_return_items(purchase_return_id);',
  ];
}
