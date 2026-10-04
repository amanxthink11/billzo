/// Statutory type of invoice.
enum InvoiceType {
  taxInvoice,
  billOfSupply;

  String get dbValue {
    switch (this) {
      case InvoiceType.taxInvoice:
        return 'TAX_INVOICE';
      case InvoiceType.billOfSupply:
        return 'BILL_OF_SUPPLY';
    }
  }

  static InvoiceType fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'TAX_INVOICE':
        return InvoiceType.taxInvoice;
      case 'BILL_OF_SUPPLY':
        return InvoiceType.billOfSupply;
      default:
        return InvoiceType.taxInvoice;
    }
  }

  String get displayName {
    switch (this) {
      case InvoiceType.taxInvoice:
        return 'Tax Invoice';
      case InvoiceType.billOfSupply:
        return 'Bill of Supply';
    }
  }
}
