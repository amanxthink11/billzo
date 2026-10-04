/// Predefined standard categories with associated default accounting codes.
class PredefinedExpenseCategory {
  final String name;
  final String accountCode;
  final String description;

  const PredefinedExpenseCategory({
    required this.name,
    required this.accountCode,
    required this.description,
  });
}

/// Domain model representing an Expense Category.
class ExpenseCategory {
  final String id;
  final String businessId;
  final String name;
  final String accountCode;
  final String? description;
  final bool isPredefined;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ExpenseCategory({
    required this.id,
    required this.businessId,
    required this.name,
    this.accountCode = '5100',
    this.description,
    this.isPredefined = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  ExpenseCategory copyWith({
    String? id,
    String? businessId,
    String? name,
    String? accountCode,
    String? description,
    bool? isPredefined,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpenseCategory(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      accountCode: accountCode ?? this.accountCode,
      description: description ?? this.description,
      isPredefined: isPredefined ?? this.isPredefined,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'account_code': accountCode,
      'description': description,
      'is_predefined': isPredefined ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ExpenseCategory.fromMap(Map<String, dynamic> map) {
    return ExpenseCategory(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      name: map['name'] as String,
      accountCode: map['account_code'] as String? ?? '5100',
      description: map['description'] as String?,
      isPredefined: (map['is_predefined'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// Standard predefined categories per Indian commercial business standards.
  static const List<PredefinedExpenseCategory> standardCategories = [
    PredefinedExpenseCategory(
      name: 'Rent',
      accountCode: '5110',
      description: 'Office, warehouse, or store rental expenses',
    ),
    PredefinedExpenseCategory(
      name: 'Utilities',
      accountCode: '5120',
      description: 'Electricity, water, heating, and power bills',
    ),
    PredefinedExpenseCategory(
      name: 'Salaries/Wages',
      accountCode: '5130',
      description: 'Staff payroll, wages, contractor stipends, and bonuses',
    ),
    PredefinedExpenseCategory(
      name: 'Office Supplies',
      accountCode: '5140',
      description: 'Stationery, printing paper, toner, and pantry items',
    ),
    PredefinedExpenseCategory(
      name: 'Internet/Telephone',
      accountCode: '5150',
      description: 'Broadband, cellular lines, cloud communication tools',
    ),
    PredefinedExpenseCategory(
      name: 'Travel',
      accountCode: '5160',
      description: 'Conveyance, fuel, flights, train tickets, and lodging',
    ),
    PredefinedExpenseCategory(
      name: 'Advertising/Marketing',
      accountCode: '5170',
      description: 'Promotions, digital ads, social media, print flyers',
    ),
    PredefinedExpenseCategory(
      name: 'Repairs & Maintenance',
      accountCode: '5180',
      description: 'Equipment servicing, office renovation, hardware upkeep',
    ),
    PredefinedExpenseCategory(
      name: 'Professional Fees',
      accountCode: '5190',
      description: 'Legal, accounting, audit, CA, and consultancy fees',
    ),
    PredefinedExpenseCategory(
      name: 'Bank Charges',
      accountCode: '5191',
      description: 'Transaction fees, payment gateway charges, account maintenance',
    ),
    PredefinedExpenseCategory(
      name: 'Insurance',
      accountCode: '5192',
      description: 'Property, transit, health, and liability insurance premiums',
    ),
    PredefinedExpenseCategory(
      name: 'Miscellaneous',
      accountCode: '5199',
      description: 'Sundry and other non-categorized operational expenses',
    ),
  ];
}
