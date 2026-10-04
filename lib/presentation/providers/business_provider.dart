import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Notifier managing the active business profile state.
class ActiveBusinessNotifier extends AsyncNotifier<Business?> {
  @override
  Future<Business?> build() async {
    final service = ref.watch(businessServiceProvider);
    return await service.getActiveBusiness();
  }

  /// Sets up a new business profile and updates application state.
  Future<Business> setupBusiness({
    required String name,
    required String phone,
    required String stateCode,
    required String stateName,
    String? legalName,
    String? tradeName,
    String? email,
    String? gstin,
    String? pan,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? pincode,
    String? upiId,
    String? bankAccountName,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankName,
    String? bankBranch,
  }) async {
    state = const AsyncValue.loading();
    try {
      final service = ref.read(businessServiceProvider);
      final created = await service.setupInitialBusiness(
        name: name,
        phone: phone,
        stateCode: stateCode,
        stateName: stateName,
        legalName: legalName,
        tradeName: tradeName,
        email: email,
        gstin: gstin,
        pan: pan,
        addressLine1: addressLine1,
        addressLine2: addressLine2,
        city: city,
        pincode: pincode,
        upiId: upiId,
        bankAccountName: bankAccountName,
        bankAccountNumber: bankAccountNumber,
        bankIfsc: bankIfsc,
        bankName: bankName,
        bankBranch: bankBranch,
      );
      state = AsyncValue.data(created);
      return created;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Updates the active business profile.
  Future<Business> updateBusiness(Business business) async {
    state = const AsyncValue.loading();
    try {
      final service = ref.read(businessServiceProvider);
      final updated = await service.updateBusiness(business);
      state = AsyncValue.data(updated);
      return updated;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final activeBusinessProvider =
    AsyncNotifierProvider<ActiveBusinessNotifier, Business?>(() {
  return ActiveBusinessNotifier();
});

/// Provider resolving operational settings for a business.
final businessSettingsProvider = FutureProvider.family<BusinessSettings?, String>((ref, businessId) async {
  final repo = ref.watch(businessRepositoryProvider);
  return repo.getBusinessSettings(businessId);
});

