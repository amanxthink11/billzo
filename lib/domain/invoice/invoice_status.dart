import 'package:flutter/material.dart';
import 'package:billzo/core/theme/colors.dart';

/// Lifecycle statuses for sales invoices.
enum InvoiceStatus {
  draft,
  finalized,
  partiallyPaid,
  paid,
  cancelled;

  String get dbValue {
    switch (this) {
      case InvoiceStatus.draft:
        return 'DRAFT';
      case InvoiceStatus.finalized:
        return 'FINALIZED';
      case InvoiceStatus.partiallyPaid:
        return 'PARTIAL';
      case InvoiceStatus.paid:
        return 'PAID';
      case InvoiceStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static InvoiceStatus fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'DRAFT':
        return InvoiceStatus.draft;
      case 'FINALIZED':
        return InvoiceStatus.finalized;
      case 'PARTIAL':
      case 'PARTIALLY_PAID':
        return InvoiceStatus.partiallyPaid;
      case 'PAID':
        return InvoiceStatus.paid;
      case 'CANCELLED':
        return InvoiceStatus.cancelled;
      default:
        return InvoiceStatus.draft;
    }
  }

  String get displayName {
    switch (this) {
      case InvoiceStatus.draft:
        return 'Draft';
      case InvoiceStatus.finalized:
        return 'Finalized';
      case InvoiceStatus.partiallyPaid:
        return 'Partially Paid';
      case InvoiceStatus.paid:
        return 'Paid';
      case InvoiceStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case InvoiceStatus.draft:
        return BillzoColors.neutralText;
      case InvoiceStatus.finalized:
        return BillzoColors.primaryBlue;
      case InvoiceStatus.partiallyPaid:
        return BillzoColors.accentOrange;
      case InvoiceStatus.paid:
        return BillzoColors.successGreen;
      case InvoiceStatus.cancelled:
        return BillzoColors.dangerRed;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case InvoiceStatus.draft:
        return const Color(0xFFF1F5F9);
      case InvoiceStatus.finalized:
        return const Color(0xFFEFF6FF);
      case InvoiceStatus.partiallyPaid:
        return const Color(0xFFFFFBEB);
      case InvoiceStatus.paid:
        return const Color(0xFFECFDF5);
      case InvoiceStatus.cancelled:
        return const Color(0xFFFEF2F2);
    }
  }

  bool get isDraft => this == InvoiceStatus.draft;
  bool get isFinalized => this == InvoiceStatus.finalized;
  bool get isCancelled => this == InvoiceStatus.cancelled;
  bool get isPaid => this == InvoiceStatus.paid;
  bool get isPartiallyPaid => this == InvoiceStatus.partiallyPaid;
}
