import 'package:uuid/uuid.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_repository.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/business/business_validator.dart';

/// Application service orchestrating business profile workflows.
class BusinessService {
  final IBusinessRepository _repository;
  final Uuid _uuid = const Uuid();

  BusinessService(this._repository);

  /// Checks if this is the first application launch (no business configured).
  Future<bool> isFirstRun() async {
    final hasBusiness = await _repository.hasConfiguredBusiness();
    return !hasBusiness;
  }

  /// Retrieves the active merchant profile.
  Future<Business?> getActiveBusiness() async {
    return await _repository.getActiveBusiness();
  }

  /// Sets up the initial business profile during onboarding.
  Future<Business> setupInitialBusiness({
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
    final now = DateTime.now().toUtc();
    final sanitizedPhone = BusinessValidator.sanitizePhone(phone);
    final upperGstin = gstin != null && gstin.trim().isNotEmpty ? gstin.trim().toUpperCase() : null;
    final upperPan = pan != null && pan.trim().isNotEmpty
        ? pan.trim().toUpperCase()
        : (upperGstin != null && upperGstin.length >= 12 ? upperGstin.substring(2, 12) : null);

    final business = Business(
      id: _uuid.v4(),
      name: name.trim(),
      legalName: legalName?.trim().isNotEmpty == true ? legalName!.trim() : null,
      tradeName: tradeName?.trim().isNotEmpty == true ? tradeName!.trim() : null,
      email: email?.trim().isNotEmpty == true ? email!.trim() : null,
      phone: sanitizedPhone,
      gstin: upperGstin,
      pan: upperPan,
      addressLine1: addressLine1?.trim().isNotEmpty == true ? addressLine1!.trim() : null,
      addressLine2: addressLine2?.trim().isNotEmpty == true ? addressLine2!.trim() : null,
      city: city?.trim().isNotEmpty == true ? city!.trim() : null,
      stateCode: stateCode.trim(),
      stateName: stateName.trim(),
      pincode: pincode?.trim().isNotEmpty == true ? pincode!.trim() : null,
      upiId: upiId?.trim().isNotEmpty == true ? upiId!.trim() : null,
      bankAccountName: bankAccountName?.trim().isNotEmpty == true ? bankAccountName!.trim() : null,
      bankAccountNumber: bankAccountNumber?.trim().isNotEmpty == true ? bankAccountNumber!.trim() : null,
      bankIfsc: bankIfsc?.trim().isNotEmpty == true ? bankIfsc!.trim().toUpperCase() : null,
      bankName: bankName?.trim().isNotEmpty == true ? bankName!.trim() : null,
      bankBranch: bankBranch?.trim().isNotEmpty == true ? bankBranch!.trim() : null,
      createdAt: now,
      updatedAt: now,
    );

    return await _repository.createBusiness(business);
  }

  /// Updates business details.
  Future<Business> updateBusiness(Business business) async {
    return await _repository.updateBusiness(business);
  }

  /// Retrieves business settings.
  Future<BusinessSettings?> getBusinessSettings(String businessId) async {
    return await _repository.getBusinessSettings(businessId);
  }

  /// Updates business settings.
  Future<BusinessSettings> updateBusinessSettings(BusinessSettings settings) async {
    return await _repository.updateBusinessSettings(settings);
  }
}
