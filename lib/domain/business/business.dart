/// Domain entity representing a Merchant Business Organization in Billzo.
class Business {
  final String id;
  final String name;
  final String? legalName;
  final String? tradeName;
  final String? gstin;
  final String? pan;
  final String? email;
  final String phone;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String stateCode;
  final String stateName;
  final String? pincode;
  final String country;
  final String currencyCode;
  final String currencySymbol;
  final String? logoPath;
  final String? signaturePath;
  final String? upiId;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? bankName;
  final String? bankBranch;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncVersion;
  final String syncStatus;

  const Business({
    required this.id,
    required this.name,
    this.legalName,
    this.tradeName,
    this.gstin,
    this.pan,
    this.email,
    required this.phone,
    this.addressLine1,
    this.addressLine2,
    this.city,
    required this.stateCode,
    required this.stateName,
    this.pincode,
    this.country = 'India',
    this.currencyCode = 'INR',
    this.currencySymbol = '₹',
    this.logoPath,
    this.signaturePath,
    this.upiId,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankIfsc,
    this.bankName,
    this.bankBranch,
    required this.createdAt,
    required this.updatedAt,
    this.syncVersion = 1,
    this.syncStatus = 'synced',
  });

  String get state => stateName;

  Business copyWith({
    String? id,
    String? name,
    String? legalName,
    String? tradeName,
    String? gstin,
    String? pan,
    String? email,
    String? phone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? stateCode,
    String? stateName,
    String? pincode,
    String? country,
    String? currencyCode,
    String? currencySymbol,
    String? logoPath,
    String? signaturePath,
    String? upiId,
    String? bankAccountName,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankName,
    String? bankBranch,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncVersion,
    String? syncStatus,
  }) {
    return Business(
      id: id ?? this.id,
      name: name ?? this.name,
      legalName: legalName ?? this.legalName,
      tradeName: tradeName ?? this.tradeName,
      gstin: gstin ?? this.gstin,
      pan: pan ?? this.pan,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      stateCode: stateCode ?? this.stateCode,
      stateName: stateName ?? this.stateName,
      pincode: pincode ?? this.pincode,
      country: country ?? this.country,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      logoPath: logoPath ?? this.logoPath,
      signaturePath: signaturePath ?? this.signaturePath,
      upiId: upiId ?? this.upiId,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankIfsc: bankIfsc ?? this.bankIfsc,
      bankName: bankName ?? this.bankName,
      bankBranch: bankBranch ?? this.bankBranch,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncVersion: syncVersion ?? this.syncVersion,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'legal_name': legalName,
      'trade_name': tradeName,
      'gstin': gstin,
      'pan': pan,
      'email': email,
      'phone': phone,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'city': city,
      'state_code': stateCode,
      'state_name': stateName,
      'pincode': pincode,
      'country': country,
      'currency_code': currencyCode,
      'currency_symbol': currencySymbol,
      'logo_path': logoPath,
      'signature_path': signaturePath,
      'upi_id': upiId,
      'bank_account_name': bankAccountName,
      'bank_account_number': bankAccountNumber,
      'bank_ifsc': bankIfsc,
      'bank_name': bankName,
      'bank_branch': bankBranch,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'sync_version': syncVersion,
      'sync_status': syncStatus,
    };
  }

  factory Business.fromMap(Map<String, dynamic> map) {
    return Business(
      id: map['id'] as String,
      name: map['name'] as String,
      legalName: map['legal_name'] as String?,
      tradeName: map['trade_name'] as String?,
      gstin: map['gstin'] as String?,
      pan: map['pan'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String,
      addressLine1: map['address_line1'] as String?,
      addressLine2: map['address_line2'] as String?,
      city: map['city'] as String?,
      stateCode: map['state_code'] as String,
      stateName: map['state_name'] as String,
      pincode: map['pincode'] as String?,
      country: map['country'] as String? ?? 'India',
      currencyCode: map['currency_code'] as String? ?? 'INR',
      currencySymbol: map['currency_symbol'] as String? ?? '₹',
      logoPath: map['logo_path'] as String?,
      signaturePath: map['signature_path'] as String?,
      upiId: map['upi_id'] as String?,
      bankAccountName: map['bank_account_name'] as String?,
      bankAccountNumber: map['bank_account_number'] as String?,
      bankIfsc: map['bank_ifsc'] as String?,
      bankName: map['bank_name'] as String?,
      bankBranch: map['bank_branch'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncVersion: map['sync_version'] as int? ?? 1,
      syncStatus: map['sync_status'] as String? ?? 'synced',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Business && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Business(id: $id, name: $name, phone: $phone, gstin: $gstin)';
}
