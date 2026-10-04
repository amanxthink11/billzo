import 'package:flutter/foundation.dart';

/// Type of stakeholder party.
enum PartyType {
  customer,
  supplier,
  both;

  String get dbValue {
    switch (this) {
      case PartyType.customer:
        return 'customer';
      case PartyType.supplier:
        return 'supplier';
      case PartyType.both:
        return 'both';
    }
  }

  static PartyType fromDbValue(String value) {
    switch (value.toLowerCase()) {
      case 'customer':
        return PartyType.customer;
      case 'supplier':
        return PartyType.supplier;
      case 'both':
        return PartyType.both;
      default:
        return PartyType.customer;
    }
  }

  String get displayName {
    switch (this) {
      case PartyType.customer:
        return 'Customer';
      case PartyType.supplier:
        return 'Supplier';
      case PartyType.both:
        return 'Customer & Supplier';
    }
  }
}

/// Balance direction for party opening balance.
enum OpeningBalanceType {
  toReceive, // Customer owes business (Receivable)
  toPay;     // Business owes supplier (Payable)

  String get dbValue {
    switch (this) {
      case OpeningBalanceType.toReceive:
        return 'to_receive';
      case OpeningBalanceType.toPay:
        return 'to_pay';
    }
  }

  static OpeningBalanceType fromDbValue(String value) {
    switch (value.toLowerCase()) {
      case 'to_receive':
      case 'receivable':
        return OpeningBalanceType.toReceive;
      case 'to_pay':
      case 'payable':
        return OpeningBalanceType.toPay;
      default:
        return OpeningBalanceType.toReceive;
    }
  }

  String get displayName {
    switch (this) {
      case OpeningBalanceType.toReceive:
        return 'To Receive (Receivable)';
      case OpeningBalanceType.toPay:
        return 'To Pay (Payable)';
    }
  }
}

/// Unified Party entity (Customer, Supplier, or Both).
@immutable
class Party {
  final String id;
  final String businessId;
  final String name;
  final String? companyName;
  final PartyType partyType;
  final String? contactPerson;
  final String? phone;
  final String? alternatePhone;
  final String? email;
  final String? gstin;
  final String? pan;
  final String? billingAddressLine1;
  final String? billingAddressLine2;
  final String? billingCity;
  final String? billingStateCode;
  final String? billingStateName;
  final String? billingPincode;
  final String? shippingAddressLine1;
  final String? shippingAddressLine2;
  final String? shippingCity;
  final String? shippingStateCode;
  final String? shippingStateName;
  final String? shippingPincode;
  final int creditLimitPaise;
  final int creditPeriodDays;
  final int openingBalancePaise;
  final OpeningBalanceType openingBalanceType;
  final int currentBalancePaise;
  final String? notes;
  final bool isActive;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Party({
    required this.id,
    required this.businessId,
    required this.name,
    this.companyName,
    required this.partyType,
    this.contactPerson,
    this.phone,
    this.alternatePhone,
    this.email,
    this.gstin,
    this.pan,
    this.billingAddressLine1,
    this.billingAddressLine2,
    this.billingCity,
    this.billingStateCode,
    this.billingStateName,
    this.billingPincode,
    this.shippingAddressLine1,
    this.shippingAddressLine2,
    this.shippingCity,
    this.shippingStateCode,
    this.shippingStateName,
    this.shippingPincode,
    this.creditLimitPaise = 0,
    this.creditPeriodDays = 0,
    this.openingBalancePaise = 0,
    this.openingBalanceType = OpeningBalanceType.toReceive,
    this.currentBalancePaise = 0,
    this.notes,
    this.isActive = true,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCustomer => partyType == PartyType.customer || partyType == PartyType.both;
  bool get isSupplier => partyType == PartyType.supplier || partyType == PartyType.both;

  String? get billingAddress {
    final parts = [billingAddressLine1, billingCity, billingStateName, billingPincode]
        .where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }

  Party copyWith({
    String? id,
    String? businessId,
    String? name,
    String? companyName,
    PartyType? partyType,
    String? contactPerson,
    String? phone,
    String? alternatePhone,
    String? email,
    String? gstin,
    String? pan,
    String? billingAddressLine1,
    String? billingAddressLine2,
    String? billingCity,
    String? billingStateCode,
    String? billingStateName,
    String? billingPincode,
    String? shippingAddressLine1,
    String? shippingAddressLine2,
    String? shippingCity,
    String? shippingStateCode,
    String? shippingStateName,
    String? shippingPincode,
    int? creditLimitPaise,
    int? creditPeriodDays,
    int? openingBalancePaise,
    OpeningBalanceType? openingBalanceType,
    int? currentBalancePaise,
    String? notes,
    bool? isActive,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Party(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      companyName: companyName ?? this.companyName,
      partyType: partyType ?? this.partyType,
      contactPerson: contactPerson ?? this.contactPerson,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      email: email ?? this.email,
      gstin: gstin ?? this.gstin,
      pan: pan ?? this.pan,
      billingAddressLine1: billingAddressLine1 ?? this.billingAddressLine1,
      billingAddressLine2: billingAddressLine2 ?? this.billingAddressLine2,
      billingCity: billingCity ?? this.billingCity,
      billingStateCode: billingStateCode ?? this.billingStateCode,
      billingStateName: billingStateName ?? this.billingStateName,
      billingPincode: billingPincode ?? this.billingPincode,
      shippingAddressLine1: shippingAddressLine1 ?? this.shippingAddressLine1,
      shippingAddressLine2: shippingAddressLine2 ?? this.shippingAddressLine2,
      shippingCity: shippingCity ?? this.shippingCity,
      shippingStateCode: shippingStateCode ?? this.shippingStateCode,
      shippingStateName: shippingStateName ?? this.shippingStateName,
      shippingPincode: shippingPincode ?? this.shippingPincode,
      creditLimitPaise: creditLimitPaise ?? this.creditLimitPaise,
      creditPeriodDays: creditPeriodDays ?? this.creditPeriodDays,
      openingBalancePaise: openingBalancePaise ?? this.openingBalancePaise,
      openingBalanceType: openingBalanceType ?? this.openingBalanceType,
      currentBalancePaise: currentBalancePaise ?? this.currentBalancePaise,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'company_name': companyName,
      'party_type': partyType.dbValue,
      'contact_person': contactPerson,
      'phone': phone,
      'alternate_phone': alternatePhone,
      'email': email,
      'gstin': gstin,
      'pan': pan,
      'billing_address_line1': billingAddressLine1,
      'billing_address_line2': billingAddressLine2,
      'billing_city': billingCity,
      'billing_state_code': billingStateCode,
      'billing_state_name': billingStateName,
      'billing_pincode': billingPincode,
      'shipping_address_line1': shippingAddressLine1,
      'shipping_address_line2': shippingAddressLine2,
      'shipping_city': shippingCity,
      'shipping_state_code': shippingStateCode,
      'shipping_state_name': shippingStateName,
      'shipping_pincode': shippingPincode,
      'credit_limit_paise': creditLimitPaise,
      'credit_period_days': creditPeriodDays,
      'opening_balance_paise': openingBalancePaise,
      'opening_balance_type': openingBalanceType.dbValue,
      'current_balance_paise': currentBalancePaise,
      'notes': notes,
      'is_active': isActive ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Party.fromMap(Map<String, dynamic> map) {
    return Party(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      name: map['name'] as String,
      companyName: map['company_name'] as String?,
      partyType: PartyType.fromDbValue(map['party_type'] as String),
      contactPerson: map['contact_person'] as String?,
      phone: map['phone'] as String?,
      alternatePhone: map['alternate_phone'] as String?,
      email: map['email'] as String?,
      gstin: map['gstin'] as String?,
      pan: map['pan'] as String?,
      billingAddressLine1: map['billing_address_line1'] as String?,
      billingAddressLine2: map['billing_address_line2'] as String?,
      billingCity: map['billing_city'] as String?,
      billingStateCode: map['billing_state_code'] as String?,
      billingStateName: map['billing_state_name'] as String?,
      billingPincode: map['billing_pincode'] as String?,
      shippingAddressLine1: map['shipping_address_line1'] as String?,
      shippingAddressLine2: map['shipping_address_line2'] as String?,
      shippingCity: map['shipping_city'] as String?,
      shippingStateCode: map['shipping_state_code'] as String?,
      shippingStateName: map['shipping_state_name'] as String?,
      shippingPincode: map['shipping_pincode'] as String?,
      creditLimitPaise: map['credit_limit_paise'] as int? ?? 0,
      creditPeriodDays: map['credit_period_days'] as int? ?? 0,
      openingBalancePaise: map['opening_balance_paise'] as int? ?? 0,
      openingBalanceType: OpeningBalanceType.fromDbValue(map['opening_balance_type'] as String? ?? 'to_receive'),
      currentBalancePaise: map['current_balance_paise'] as int? ?? 0,
      notes: map['notes'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
