import 'package:billzo/domain/catalog/tax_rate.dart';

/// Repository interface for GST Tax Rates.
abstract class ITaxRateRepository {
  Future<List<TaxRate>> getTaxRates(String businessId, {bool includeInactive = false});
  Future<TaxRate?> getTaxRateById(String id);
  Future<TaxRate?> getDefaultTaxRate(String businessId);
}
