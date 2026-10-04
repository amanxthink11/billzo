import 'package:flutter/material.dart';

/// Official color palette for Billzo.
/// Source of Truth: `F:\Billzo\assist\Billzo Brand Identity Asset Kit.png`
class BillzoColors {
  BillzoColors._();

  // Primary Brand Colors
  /// Primary Blue: Trust, Stability (#2563EB)
  static const Color primaryBlue = Color(0xFF2563EB);

  /// Secondary Blue: Modern, Friendly (#3B82F6)
  static const Color secondaryBlue = Color(0xFF3B82F6);

  /// Success Green: Growth, Positive, Paid (#10B981)
  static const Color successGreen = Color(0xFF10B981);

  /// Accent Orange: Action, Energy, Partial (#F59E0B)
  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color warningOrange = accentOrange;
  static const Color warningAmber = accentOrange;

  /// Danger / Overdue Red: (#EF4444)
  static const Color dangerRed = Color(0xFFEF4444);

  // Surface & Neutral Colors
  /// Dark Slate: Headings, High-contrast text (#0F172A)
  static const Color darkSlate = Color(0xFF0F172A);

  /// Light Canvas Background: (#F1F5F9)
  static const Color canvasLight = Color(0xFFF1F5F9);

  /// Pure Card Surface White: (#FFFFFF)
  static const Color cardSurface = Color(0xFFFFFFFF);

  /// Subtle Border / Divider Slate: (#E2E8F0)
  static const Color border = Color(0xFFE2E8F0);
  static const Color neutralBorder = border;

  /// Neutral / Muted Body Text: (#64748B)
  static const Color neutralText = Color(0xFF64748B);

  /// Subtle Table Row Hover: (#F8FAFC)
  static const Color hoverSurface = Color(0xFFF8FAFC);
  static const Color neutralLight = canvasLight;

  // Module Visual Accent Colors
  /// Invoices / Sales: Primary Blue (#2563EB)
  static const Color moduleInvoices = Color(0xFF2563EB);

  /// Inventory / Stock: Success Green (#10B981)
  static const Color moduleInventory = Color(0xFF10B981);

  /// GST / Tax: Vibrant Purple (#8B5CF6)
  static const Color moduleGst = Color(0xFF8B5CF6);

  /// Payments / Cash: Accent Gold/Amber (#F59E0B)
  static const Color modulePayments = Color(0xFFF59E0B);

  /// Recurring Invoices: Sky Cyan (#0284C7)
  static const Color moduleRecurring = Color(0xFF0284C7);

  /// Reports & Analytics: Crimson Rose (#F43F5E)
  static const Color moduleReports = Color(0xFFF43F5E);
}
