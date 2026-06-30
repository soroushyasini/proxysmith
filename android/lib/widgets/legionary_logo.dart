import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The ProxySmith logo, rendered from the user-provided vector artwork at
/// assets/icon/app_logo.svg via flutter_svg.
///
/// Used in three places:
///  1. Small (32-36px) in the app bar
///  2. Large (96-120px) on the splash/loading screen and About dialog
///  3. Source artwork for the Android launcher icon — see README for the
///     flutter_launcher_icons setup using the same asset file.
class LegionaryLogo extends StatelessWidget {
  final double size;
  final bool rounded;

  const LegionaryLogo({
    super.key,
    this.size = 42,
    this.rounded = true,
  });

  static const String assetPath = 'assets/icon/app_logo.svg';

  @override
  Widget build(BuildContext context) {
    final svg = SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

    if (!rounded) return svg;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: svg,
    );
  }
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
        const LegionaryLogo(size: 112),
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
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
