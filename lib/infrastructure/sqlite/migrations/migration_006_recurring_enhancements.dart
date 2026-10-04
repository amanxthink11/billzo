/// Migration 006: Add snapshot fields to recurring invoice items.
class Migration006RecurringEnhancements {
  static const int version = 6;
  static const String description =
      '006_recurring_enhancements: Add product_name and hsn_sac to recurring_invoice_items';

  static const List<String> statements = [
    'ALTER TABLE recurring_invoice_items ADD COLUMN product_name TEXT;',
    'ALTER TABLE recurring_invoice_items ADD COLUMN hsn_sac TEXT;',
  ];
}
