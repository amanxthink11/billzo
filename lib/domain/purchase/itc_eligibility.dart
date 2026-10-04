/// Input Tax Credit (ITC) statutory eligibility classification under Indian GST rules.
///
/// Under Section 16/17(5) of the CGST Act, certain purchases qualify for full Input Tax Credit
/// (e.g. raw materials, resale merchandise, office equipment used for business), while others
/// fall under blocked credit (Section 17(5) - personal consumption, motor vehicles, employee benefits).
///
/// Since products do not encode statutory blocked-credit status, Billzo provides an explicit
/// purchase-level and item-level eligibility flag defaulting safely to [eligible].
enum ItcEligibility {
  eligible,
  ineligible;

  String get dbValue {
    switch (this) {
      case ItcEligibility.eligible:
        return 'ELIGIBLE';
      case ItcEligibility.ineligible:
        return 'INELIGIBLE';
    }
  }

  static ItcEligibility fromDbValue(String? value) {
    if (value == null) return ItcEligibility.eligible;
    switch (value.toUpperCase()) {
      case 'ELIGIBLE':
        return ItcEligibility.eligible;
      case 'INELIGIBLE':
        return ItcEligibility.ineligible;
      default:
        return ItcEligibility.eligible;
    }
  }

  String get displayName {
    switch (this) {
      case ItcEligibility.eligible:
        return 'Eligible for ITC';
      case ItcEligibility.ineligible:
        return 'Ineligible (Blocked)';
    }
  }

  bool get isEligible => this == ItcEligibility.eligible;
}
