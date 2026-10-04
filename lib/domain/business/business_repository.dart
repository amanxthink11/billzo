import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';

/// Abstract contract for Business profile and settings data access.
abstract class IBusinessRepository {
  /// Retrieves the currently active business profile, or null if no business is configured.
  Future<Business?> getActiveBusiness();

  /// Creates a new business profile with accompanying default settings and sequences.
  Future<Business> createBusiness(Business business, {BusinessSettings? settings});

  /// Updates an existing business profile.
  Future<Business> updateBusiness(Business business);

  /// Retrieves the operational settings for a business.
  Future<BusinessSettings?> getBusinessSettings(String businessId);

  /// Updates the operational settings for a business.
  Future<BusinessSettings> updateBusinessSettings(BusinessSettings settings);

  /// Returns true if at least one valid business profile has been initialized.
  Future<bool> hasConfiguredBusiness();
}
