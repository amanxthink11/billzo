import 'package:flutter/material.dart';
import 'package:billzo/core/theme/colors.dart';

/// Renders the official Billzo brand mark:
/// The 'B' letterform integrated with the receipt/invoice glyph with horizontal lines and jagged bottom edge.
class BillzoBrandMark extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final bool showTagline;
  final bool isDark;
  final Axis layout;

  const BillzoBrandMark({
    super.key,
    this.size = 40,
    this.showWordmark = true,
    this.showTagline = true,
    this.isDark = false,
    this.layout = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white : BillzoColors.primaryBlue,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : BillzoColors.primaryBlue).withValues(alpha: 0.18),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.65, size * 0.65),
          painter: _BillzoGlyphPainter(
            accentColor: isDark ? BillzoColors.darkSlate : Colors.white,
            linesColor: isDark ? Colors.white : BillzoColors.primaryBlue,
          ),
        ),
      ),
    );

    if (!showWordmark) {
      return iconWidget;
    }

    final textColor = isDark ? Colors.white : BillzoColors.darkSlate;
    final taglineColor = isDark ? Colors.white70 : BillzoColors.neutralText;

    final textWidget = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          layout == Axis.horizontal ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          'Billzo',
          style: TextStyle(
            fontSize: size * 0.60,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        if (showTagline)
          Text(
            'Billing. Business. Simple.',
            style: TextStyle(
              fontSize: size * 0.24,
              fontWeight: FontWeight.w500,
              color: taglineColor,
              letterSpacing: 0.1,
            ),
          ),
      ],
    );

    if (layout == Axis.horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconWidget,
          SizedBox(width: size * 0.3),
          Flexible(child: textWidget),
        ],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconWidget,
          SizedBox(height: size * 0.25),
          textWidget,
        ],
      );
    }
  }
}

/// Vector painter that renders the bill/receipt glyph with 3 horizontal lines and serrated bottom
class _BillzoGlyphPainter extends CustomPainter {
  final Color accentColor;
  final Color linesColor;

  _BillzoGlyphPainter({
    required this.accentColor,
    required this.linesColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final receiptPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    // Draw folded/rounded receipt paper with jagged bottom
    final path = Path();
    const cornerRadius = 3.0;

    path.moveTo(w * 0.15 + cornerRadius, h * 0.08);
    path.lineTo(w * 0.85 - cornerRadius, h * 0.08);
    path.arcToPoint(Offset(w * 0.85, h * 0.08 + cornerRadius),
        radius: const Radius.circular(cornerRadius));

    // Right edge down
    path.lineTo(w * 0.85, h * 0.82);

    // Jagged bottom edge (3 serrations)
    path.lineTo(w * 0.73, h * 0.72);
    path.lineTo(w * 0.61, h * 0.82);
    path.lineTo(w * 0.50, h * 0.72);
    path.lineTo(w * 0.38, h * 0.82);
    path.lineTo(w * 0.26, h * 0.72);
    path.lineTo(w * 0.15, h * 0.82);

    // Left edge up
    path.lineTo(w * 0.15, h * 0.08 + cornerRadius);
    path.arcToPoint(Offset(w * 0.15 + cornerRadius, h * 0.08),
        radius: const Radius.circular(cornerRadius));
    path.close();

    canvas.drawPath(path, receiptPaint);

    // Draw three horizontal invoice lines
    final linePaint = Paint()
      ..color = linesColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round;

    final lineLeft = w * 0.30;
    final lineRight = w * 0.70;

    canvas.drawLine(Offset(lineLeft, h * 0.28), Offset(lineRight, h * 0.28), linePaint);
    canvas.drawLine(Offset(lineLeft, h * 0.44), Offset(lineRight, h * 0.44), linePaint);
    canvas.drawLine(Offset(lineLeft, h * 0.60), Offset(w * 0.55, h * 0.60), linePaint);
  }

  @override
  bool shouldRepaint(covariant _BillzoGlyphPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor || oldDelegate.linesColor != linesColor;
}
