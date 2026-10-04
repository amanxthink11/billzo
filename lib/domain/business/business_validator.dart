import 'package:billzo/core/constants/indian_states.dart';

/// Validation results and domain business rules verification.
class ValidationResult {
  final bool isValid;
  final Map<String, String> errors;

  const ValidationResult({
    required this.isValid,
    this.errors = const {},
  });

  factory ValidationResult.success() => const ValidationResult(isValid: true);

  factory ValidationResult.failure(Map<String, String> errors) =>
      ValidationResult(isValid: false, errors: errors);

  String? get firstError => errors.values.isNotEmpty ? errors.values.first : null;
}

class BusinessValidator {
  BusinessValidator._();

  static final RegExp _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)*$",
  );

  static final RegExp _phoneRegex = RegExp(r'^[6-9]\d{9}$');
  static final RegExp _pincodeRegex = RegExp(r'^[1-9]\d{5}$');
  static final RegExp _gstinRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
  static final RegExp _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
  static final RegExp _ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final RegExp _upiRegex = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');

  /// Validates all business fields according to statutory and application rules.
  static ValidationResult validate({
    required String name,
    required String phone,
    required String stateCode,
    String? email,
    String? gstin,
    String? pan,
    String? pincode,
    String? bankIfsc,
    String? upiId,
  }) {
    final errors = <String, String>{};

    // 1. Business Name
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      errors['name'] = 'Business name is required';
    } else if (trimmedName.length < 2) {
      errors['name'] = 'Business name must be at least 2 characters';
    } else if (trimmedName.length > 150) {
      errors['name'] = 'Business name cannot exceed 150 characters';
    }

    // 2. Phone
    final sanitizedPhone = sanitizePhone(phone);
    if (sanitizedPhone.isEmpty) {
      errors['phone'] = 'Phone number is required';
    } else if (!_phoneRegex.hasMatch(sanitizedPhone)) {
      errors['phone'] = 'Enter a valid 10-digit Indian mobile number';
    }

    // 3. State Code
    if (stateCode.isEmpty || !IndianStates.isValidCode(stateCode)) {
      errors['stateCode'] = 'Please select a valid Indian State/UT';
    }

    // 4. Email (optional)
    if (email != null && email.trim().isNotEmpty) {
      final trimmedEmail = email.trim();
      if (!_emailRegex.hasMatch(trimmedEmail)) {
        errors['email'] = 'Enter a valid email address';
      }
    }

    // 5. GSTIN (optional)
    if (gstin != null && gstin.trim().isNotEmpty) {
      final upperGstin = gstin.trim().toUpperCase();
      if (!_gstinRegex.hasMatch(upperGstin)) {
        errors['gstin'] = 'Enter a valid 15-character Indian GSTIN (e.g. 27AAAAA0000A1Z5)';
      } else {
        // State code in GSTIN should match selected state
        final gstinState = upperGstin.substring(0, 2);
        if (stateCode.isNotEmpty && gstinState != stateCode) {
          errors['gstin'] = 'GSTIN state code ($gstinState) does not match selected state ($stateCode)';
        }
      }
    }

    // 6. PAN (optional)
    if (pan != null && pan.trim().isNotEmpty) {
      final upperPan = pan.trim().toUpperCase();
      if (!_panRegex.hasMatch(upperPan)) {
        errors['pan'] = 'Enter a valid 10-character Indian PAN (e.g. ABCDE1234F)';
      }
    }

    // 7. Pincode (optional)
    if (pincode != null && pincode.trim().isNotEmpty) {
      final trimmedPin = pincode.trim();
      if (!_pincodeRegex.hasMatch(trimmedPin)) {
        errors['pincode'] = 'Enter a valid 6-digit Indian PIN code';
      }
    }

    // 8. Bank IFSC (optional)
    if (bankIfsc != null && bankIfsc.trim().isNotEmpty) {
      final upperIfsc = bankIfsc.trim().toUpperCase();
      if (!_ifscRegex.hasMatch(upperIfsc)) {
        errors['bankIfsc'] = 'Enter a valid 11-character IFSC code (e.g. HDFC0001234)';
      }
    }

    // 9. UPI ID (optional)
    if (upiId != null && upiId.trim().isNotEmpty) {
      final trimmedUpi = upiId.trim();
      if (!_upiRegex.hasMatch(trimmedUpi)) {
        errors['upiId'] = 'Enter a valid UPI ID (e.g. merchant@upi)';
      }
    }

    if (errors.isNotEmpty) {
      return ValidationResult.failure(errors);
    }
    return ValidationResult.success();
  }

  /// Sanitizes phone numbers by stripping prefixes (+91, 0) and non-numeric characters.
  static String sanitizePhone(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'\D'), '');
    if (cleaned.startsWith('91') && cleaned.length == 12) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.startsWith('0') && cleaned.length == 11) {
      cleaned = cleaned.substring(1);
    }
    return cleaned;
  }
}
