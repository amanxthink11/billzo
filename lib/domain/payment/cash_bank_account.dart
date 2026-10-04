import 'package:billzo/core/money/money.dart';

/// Type of financial holding account.
enum CashBankAccountType {
  cash,
  bank;

  String get dbValue => this == CashBankAccountType.cash ? 'CASH' : 'BANK';

  static CashBankAccountType fromDbValue(String value) {
    return value.toUpperCase() == 'CASH' ? CashBankAccountType.cash : CashBankAccountType.bank;
  }

  String get displayName => this == CashBankAccountType.cash ? 'Cash' : 'Bank';
}

/// Represents a physical Cash Register/Drawer or Bank Account holding funds for a business.
class CashBankAccount {
  final String id;
  final String businessId;
  final String name;
  final CashBankAccountType accountType;
  final String? accountNumber;
  final String? bankName;
  final String? ifscCode;
  final int openingBalancePaise;
  final int currentBalancePaise;
  final bool isDefault;
  final bool isActive;
  final String? ledgerAccountId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CashBankAccount({
    required this.id,
    required this.businessId,
    required this.name,
    required this.accountType,
    this.accountNumber,
    this.bankName,
    this.ifscCode,
    this.openingBalancePaise = 0,
    this.currentBalancePaise = 0,
    this.isDefault = false,
    this.isActive = true,
    this.ledgerAccountId,
    required this.createdAt,
    required this.updatedAt,
  });

  Money get currentBalance => Money.fromPaise(currentBalancePaise);
  Money get openingBalance => Money.fromPaise(openingBalancePaise);

  bool get isCash => accountType == CashBankAccountType.cash;
  bool get isBank => accountType == CashBankAccountType.bank;

  CashBankAccount copyWith({
    String? id,
    String? businessId,
    String? name,
    CashBankAccountType? accountType,
    String? accountNumber,
    String? bankName,
    String? ifscCode,
    int? openingBalancePaise,
    int? currentBalancePaise,
    bool? isDefault,
    bool? isActive,
    String? ledgerAccountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CashBankAccount(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      accountType: accountType ?? this.accountType,
      accountNumber: accountNumber ?? this.accountNumber,
      bankName: bankName ?? this.bankName,
      ifscCode: ifscCode ?? this.ifscCode,
      openingBalancePaise: openingBalancePaise ?? this.openingBalancePaise,
      currentBalancePaise: currentBalancePaise ?? this.currentBalancePaise,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      ledgerAccountId: ledgerAccountId ?? this.ledgerAccountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'account_type': accountType.dbValue,
      'account_number': accountNumber,
      'bank_name': bankName,
      'ifsc_code': ifscCode,
      'opening_balance_paise': openingBalancePaise,
      'current_balance_paise': currentBalancePaise,
      'is_default': isDefault ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'ledger_account_id': ledgerAccountId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CashBankAccount.fromMap(Map<String, dynamic> map) {
    return CashBankAccount(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      name: map['name'] as String,
      accountType: CashBankAccountType.fromDbValue(map['account_type'] as String? ?? 'CASH'),
      accountNumber: map['account_number'] as String?,
      bankName: map['bank_name'] as String?,
      ifscCode: map['ifsc_code'] as String?,
      openingBalancePaise: (map['opening_balance_paise'] as num? ?? 0).toInt(),
      currentBalancePaise: (map['current_balance_paise'] as num? ?? 0).toInt(),
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      ledgerAccountId: map['ledger_account_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
