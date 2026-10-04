/// Standard Indian States and Union Territories with statutory 2-digit GST state codes.
class IndianState {
  final String code;
  final String name;

  const IndianState(this.code, this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndianState &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => '$code - $name';
}

class IndianStates {
  IndianStates._();

  static List<IndianState> get allStates => all;

  static const List<IndianState> all = [
    IndianState('01', 'Jammu and Kashmir'),
    IndianState('02', 'Himachal Pradesh'),
    IndianState('03', 'Punjab'),
    IndianState('04', 'Chandigarh'),
    IndianState('05', 'Uttarakhand'),
    IndianState('06', 'Haryana'),
    IndianState('07', 'Delhi'),
    IndianState('08', 'Rajasthan'),
    IndianState('09', 'Uttar Pradesh'),
    IndianState('10', 'Bihar'),
    IndianState('11', 'Sikkim'),
    IndianState('12', 'Arunachal Pradesh'),
    IndianState('13', 'Nagaland'),
    IndianState('14', 'Manipur'),
    IndianState('15', 'Mizoram'),
    IndianState('16', 'Tripura'),
    IndianState('17', 'Meghalaya'),
    IndianState('18', 'Assam'),
    IndianState('19', 'West Bengal'),
    IndianState('20', 'Jharkhand'),
    IndianState('21', 'Odisha'),
    IndianState('22', 'Chhattisgarh'),
    IndianState('23', 'Madhya Pradesh'),
    IndianState('24', 'Gujarat'),
    IndianState('26', 'Dadra and Nagar Haveli and Daman and Diu'),
    IndianState('27', 'Maharashtra'),
    IndianState('28', 'Andhra Pradesh (Old)'),
    IndianState('29', 'Karnataka'),
    IndianState('30', 'Goa'),
    IndianState('31', 'Lakshadweep'),
    IndianState('32', 'Kerala'),
    IndianState('33', 'Tamil Nadu'),
    IndianState('34', 'Puducherry'),
    IndianState('35', 'Andaman and Nicobar Islands'),
    IndianState('36', 'Telangana'),
    IndianState('37', 'Andhra Pradesh'),
    IndianState('38', 'Ladakh'),
    IndianState('97', 'Other Territory'),
  ];

  static IndianState? findByCode(String code) {
    try {
      return all.firstWhere((s) => s.code == code);
    } catch (_) {
      return null;
    }
  }

  static IndianState? findByName(String name) {
    try {
      final normalized = name.trim().toLowerCase();
      return all.firstWhere((s) => s.name.toLowerCase() == normalized);
    } catch (_) {
      return null;
    }
  }

  static bool isValidCode(String code) {
    return all.any((s) => s.code == code);
  }
}
