import 'package:billzo/core/constants/indian_states.dart';
import 'package:billzo/domain/party/party.dart';

/// Domain validation result containing error messages keyed by field name.
class PartyValidationResult {
  final Map<String, String> errors;

  const PartyValidationResult(this.errors);

  bool get isValid => errors.isEmpty;
  bool get hasErrors => errors.isNotEmpty;
  String? getError(String field) => errors[field];
}

/// Domain validator for Party entities outside widgets.
class PartyValidator {
  PartyValidator._();

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  static final RegExp _gstinRegex = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
  );

  static final RegExp _panRegex = RegExp(
    r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$',
  );

  static final RegExp _pincodeRegex = RegExp(r'^[1-9][0-9]{5}$');

  /// Validates a [Party] entity before creation or update.
  static PartyValidationResult validate(Party party) {
    final Map<String, String> errors = {};

    // 1. Party Name
    final trimmedName = party.name.trim();
    if (trimmedName.isEmpty) {
      errors['name'] = 'Party name is required';
    } else if (trimmedName.length < 2) {
      errors['name'] = 'Party name must be at least 2 characters';
    }

    // 2. Phone
    if (party.phone != null && party.phone!.trim().isNotEmpty) {
      final sanitizedPhone = sanitizePhone(party.phone!);
      if (sanitizedPhone.length != 10 || !RegExp(r'^[6-9][0-9]{9}$').hasMatch(sanitizedPhone)) {
        errors['phone'] = 'Enter a valid 10-digit Indian mobile number (starts with 6-9)';
      }
    }

    // 3. Alternate Phone
    if (party.alternatePhone != null && party.alternatePhone!.trim().isNotEmpty) {
      final sanitizedAlt = sanitizePhone(party.alternatePhone!);
      if (sanitizedAlt.length != 10 || !RegExp(r'^[6-9][0-9]{9}$').hasMatch(sanitizedAlt)) {
        errors['alternate_phone'] = 'Enter a valid 10-digit alternate mobile number';
      }
    }

    // 4. Email
    if (party.email != null && party.email!.trim().isNotEmpty) {
      if (!_emailRegex.hasMatch(party.email!.trim())) {
        errors['email'] = 'Enter a valid email address';
      }
    }

    // 5. GSTIN & State Code Alignment
    if (party.gstin != null && party.gstin!.trim().isNotEmpty) {
      final upperGstin = party.gstin!.trim().toUpperCase();
      if (!_gstinRegex.hasMatch(upperGstin)) {
        errors['gstin'] = 'Invalid GSTIN format (e.g. 29ABCDE1234F1Z5)';
      } else if (party.billingStateCode != null && party.billingStateCode!.isNotEmpty) {
        final gstinStateCode = upperGstin.substring(0, 2);
        if (gstinStateCode != party.billingStateCode) {
          final expectedState = IndianStates.findByCode(gstinStateCode)?.name ?? gstinStateCode;
          errors['gstin'] = 'GSTIN state ($gstinStateCode - $expectedState) does not match billing state (${party.billingStateCode})';
        }
      }
    }

    // 6. PAN
    if (party.pan != null && party.pan!.trim().isNotEmpty) {
      final upperPan = party.pan!.trim().toUpperCase();
      if (!_panRegex.hasMatch(upperPan)) {
        errors['pan'] = 'Invalid PAN format (e.g. ABCDE1234F)';
      }
    }

    // 7. PIN Code (Billing)
    if (party.billingPincode != null && party.billingPincode!.trim().isNotEmpty) {
      if (!_pincodeRegex.hasMatch(party.billingPincode!.trim())) {
        errors['billing_pincode'] = 'Enter a valid 6-digit Indian PIN code';
      }
    }

    // 8. PIN Code (Shipping)
    if (party.shippingPincode != null && party.shippingPincode!.trim().isNotEmpty) {
      if (!_pincodeRegex.hasMatch(party.shippingPincode!.trim())) {
        errors['shipping_pincode'] = 'Enter a valid 6-digit Indian PIN code';
      }
    }

    // 9. Credit Limit
    if (party.creditLimitPaise < 0) {
      errors['credit_limit'] = 'Credit limit cannot be negative';
    }

    // 10. Opening Balance
    if (party.openingBalancePaise < 0) {
      errors['opening_balance'] = 'Opening balance cannot be negative';
    }

    return PartyValidationResult(errors);
  }

  /// Strips +91, spaces, hyphens, and leading zero from Indian phone numbers.
  static String sanitizePhone(String input) {
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (cleaned.startsWith('91') && cleaned.length == 12) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.startsWith('0') && cleaned.length == 11) {
      cleaned = cleaned.substring(1);
    }
    return cleaned;
  }
}
