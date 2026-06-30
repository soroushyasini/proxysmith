import 'package:flutter/material.dart';

/// The ProxySmith logo: a stylized Roman legionary helmet (galea).
///
/// Used in three places:
///  1. Small (32-36px) in the app bar
///  2. Large (120px+) on the splash/loading screen
///  3. Exported as the source artwork for the Android launcher icon
///     (see assets/icon/app_icon.png — generate from this widget via
///     screenshot or recreate in a vector tool at 512x512 for
///     flutter_launcher_icons)
class LegionaryLogo extends StatelessWidget {
  final double size;
  final bool showBackground;

  const LegionaryLogo({
    super.key,
    this.size = 36,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bronze = const Color(0xFFB08A5C);
    final gold = const Color(0xFFC9A070);
    final paleGold = const Color(0xFFE8C990);
    final cream = const Color(0xFFFFF5D0);
    final bgColor = isDark ? const Color(0xFF252B40) : const Color(0xFFF0E8DC);
    final lineColor = isDark ? gold : const Color(0xFF8A6A40);

    return CustomPaint(
      size: Size(size, size),
      painter: _HelmetPainter(
        bgColor: showBackground ? bgColor : Colors.transparent,
        bronze: bronze,
        gold: gold,
        paleGold: paleGold,
        cream: cream,
        lineColor: lineColor,
        drawBorder: showBackground,
      ),
    );
  }
}

class _HelmetPainter extends CustomPainter {
  final Color bgColor;
  final Color bronze;
  final Color gold;
  final Color paleGold;
  final Color cream;
  final Color lineColor;
  final bool drawBorder;

  _HelmetPainter({
    required this.bgColor,
    required this.bronze,
    required this.gold,
    required this.paleGold,
    required this.cream,
    required this.lineColor,
    required this.drawBorder,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 36; // scale factor against the 36x36 design grid
    final center = Offset(size.width / 2, size.height / 2);

    // Background circle
    if (bgColor != Colors.transparent) {
      final bgPaint = Paint()..color = bgColor;
      canvas.drawCircle(center, 17 * s, bgPaint);
      if (drawBorder) {
        final borderPaint = Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * s;
        canvas.drawCircle(center, 17 * s, borderPaint);
      }
    }

    // Helmet dome
    final domePaint = Paint()..color = bronze;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(18 * s, 15 * s), width: 14 * s, height: 9 * s),
      domePaint,
    );

    // Brow band
    final bandPaint = Paint()..color = const Color(0xFF8A6A40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(11 * s, 14 * s, 14 * s, 2.5 * s),
        Radius.circular(1.25 * s),
      ),
      bandPaint,
    );

    // Cheek guards
    final cheekPath = Path()
      ..moveTo(13 * s, 16.5 * s)
      ..lineTo(11 * s, 26 * s)
      ..quadraticBezierTo(18 * s, 29 * s, 25 * s, 26 * s)
      ..lineTo(23 * s, 16.5 * s)
      ..close();
    canvas.drawPath(cheekPath, domePaint);

    final cheekLinePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7 * s;
    final cheekLine1 = Path()
      ..moveTo(15 * s, 19 * s)
      ..quadraticBezierTo(18 * s, 20.5 * s, 21 * s, 19 * s);
    final cheekLine2 = Path()
      ..moveTo(14.5 * s, 22 * s)
      ..quadraticBezierTo(18 * s, 23.5 * s, 21.5 * s, 22 * s);
    canvas.drawPath(cheekLine1, cheekLinePaint);
    canvas.drawPath(cheekLine2, cheekLinePaint..strokeWidth = 0.6 * s);

    // Transverse crest (the plume)
    final crestPaint = Paint()..color = gold;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(18 * s, 10.5 * s), width: 7 * s, height: 4 * s),
      crestPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(16.5 * s, 8 * s, 3 * s, 5 * s),
        Radius.circular(1.5 * s),
      ),
      Paint()..color = gold,
    );

    // Side plumes
    final plumePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * s
      ..strokeCap = StrokeCap.round;
    final leftPlume = Path()
      ..moveTo(7 * s, 15 * s)
      ..quadraticBezierTo(10 * s, 12 * s, 11 * s, 15 * s);
    final rightPlume = Path()
      ..moveTo(29 * s, 15 * s)
      ..quadraticBezierTo(26 * s, 12 * s, 25 * s, 15 * s);
    canvas.drawPath(leftPlume, plumePaint);
    canvas.drawPath(rightPlume, plumePaint);
  }

  @override
  bool shouldRepaint(covariant _HelmetPainter oldDelegate) => false;
}

/// Large splash-screen version with app name beneath it.
/// Shown briefly on cold start while the Flutter engine initializes.
class SplashLogo extends StatelessWidget {
  final String appName;
  final String tagline;

  const SplashLogo({
    super.key,
    required this.appName,
    required this.tagline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LegionaryLogo(size: 96),
        const SizedBox(height: 16),
        Text(
          appName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tagline,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.extension<dynamic>() != null
                ? null
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
