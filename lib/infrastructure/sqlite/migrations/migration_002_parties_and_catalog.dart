/// Version 2 Migration: Parties contact details & catalog search performance indexes.
class Migration002PartiesAndCatalog {
  Migration002PartiesAndCatalog._();

  static const int version = 2;
  static const String description = '002_parties_and_catalog_enhancements';

  static const List<String> statements = [
    // 1. Add contact_person, alternate_phone, and notes to parties
    'ALTER TABLE parties ADD COLUMN contact_person TEXT;',
    'ALTER TABLE parties ADD COLUMN alternate_phone TEXT;',
    'ALTER TABLE parties ADD COLUMN notes TEXT;',

    // 2. Performance indexes for high-speed lookups and filtering
    'CREATE INDEX IF NOT EXISTS idx_parties_name ON parties(business_id, name);',
    'CREATE INDEX IF NOT EXISTS idx_parties_phone ON parties(business_id, phone);',
    'CREATE INDEX IF NOT EXISTS idx_parties_gstin ON parties(business_id, gstin);',
    'CREATE INDEX IF NOT EXISTS idx_products_sku ON products(business_id, sku);',
    'CREATE INDEX IF NOT EXISTS idx_products_name ON products(business_id, name);',
    'CREATE INDEX IF NOT EXISTS idx_products_hsn ON products(business_id, hsn_sac_code);',
    'CREATE INDEX IF NOT EXISTS idx_products_category ON products(business_id, category_id);',
    'CREATE INDEX IF NOT EXISTS idx_categories_business ON categories(business_id, is_active, is_deleted);',
    'CREATE INDEX IF NOT EXISTS idx_units_business ON units(business_id, is_default);',
    'CREATE INDEX IF NOT EXISTS idx_accounts_business_code ON accounts(business_id, account_code);',
  ];
}
