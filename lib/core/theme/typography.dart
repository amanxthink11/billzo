import 'package:flutter/material.dart';
import 'package:billzo/core/theme/colors.dart';

/// Typography hierarchy for Billzo based on the Inter font family.
class BillzoTypography {
  BillzoTypography._();

  static const String fontFamily = 'Inter';

  /// Display 1: Dashboard KPI totals (28px Bold)
  static const TextStyle display1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: BillzoColors.darkSlate,
    height: 1.28,
    letterSpacing: -0.5,
  );

  /// Headline 1: Page titles, primary modal headers (22px SemiBold)
  static const TextStyle headline1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: BillzoColors.darkSlate,
    height: 1.27,
    letterSpacing: -0.3,
  );

  /// Headline 2: Section headers, card titles (18px SemiBold)
  static const TextStyle headline2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: BillzoColors.darkSlate,
    height: 1.33,
  );

  /// Body Large: Navigation items, prominent table cells (15px Medium)
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: BillzoColors.darkSlate,
    height: 1.46,
  );

  /// Body Base: Standard inputs, descriptions, body text (13px Regular)
  static const TextStyle bodyBase = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: BillzoColors.darkSlate,
    height: 1.38,
  );

  /// Caption: Table column headers, metadata, badge tags (11px Medium)
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: BillzoColors.neutralText,
    height: 1.27,
    letterSpacing: 0.2,
  );

  /// Monetary Tabular: Numbers aligned vertically with fixed figure widths
  static const TextStyle monetary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: BillzoColors.darkSlate,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
