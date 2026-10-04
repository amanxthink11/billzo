import 'package:flutter/material.dart';

/// Supported payment methods for customer payments.
enum PaymentMethod {
  cash,
  bankTransfer,
  upi,
  card,
  cheque,
  other;

  String get dbValue {
    switch (this) {
      case PaymentMethod.cash:
        return 'CASH';
      case PaymentMethod.bankTransfer:
        return 'BANK_TRANSFER';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'CARD';
      case PaymentMethod.cheque:
        return 'CHEQUE';
      case PaymentMethod.other:
        return 'OTHER';
    }
  }

  static PaymentMethod fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'CASH':
        return PaymentMethod.cash;
      case 'BANK_TRANSFER':
      case 'BANK':
      case 'NEFT':
      case 'RTGS':
      case 'IMPS':
        return PaymentMethod.bankTransfer;
      case 'UPI':
        return PaymentMethod.upi;
      case 'CARD':
      case 'DEBIT_CARD':
      case 'CREDIT_CARD':
        return PaymentMethod.card;
      case 'CHEQUE':
        return PaymentMethod.cheque;
      default:
        return PaymentMethod.other;
    }
  }

  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.cheque:
        return 'Cheque';
      case PaymentMethod.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case PaymentMethod.cash:
        return Icons.payments_outlined;
      case PaymentMethod.bankTransfer:
        return Icons.account_balance_outlined;
      case PaymentMethod.upi:
        return Icons.qr_code_2;
      case PaymentMethod.card:
        return Icons.credit_card;
      case PaymentMethod.cheque:
        return Icons.description_outlined;
      case PaymentMethod.other:
        return Icons.more_horiz;
    }
  }

  /// Whether this method typically settles through a bank account (vs physical cash).
  bool get isBankSettled => this != PaymentMethod.cash;
}
