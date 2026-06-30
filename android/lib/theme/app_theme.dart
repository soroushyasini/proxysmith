import 'package:flutter/material.dart';

/// Centralized palette for ProxySmith.
///
/// Design intent: swap the whole app's look by editing the seed colors
/// below. Everything else (ThemeData, individual widgets) derives from
/// these few constants — no hardcoded hex values should appear anywhere
/// else in the app. If you want a different palette later (e.g. back to
/// the original blue), change these four lines and rebuild.
class AppPalette {
  AppPalette._();

  // ── Brand seed colors ───────────────────────────────────────────────
  // These three define the whole bronze/gold identity. Swap them to
  // re-theme the entire app.
  static const Color seedPrimary = Color(0xFFB08A5C); // bronze
  static const Color seedSecondary = Color(0xFFC9A070); // gold
  static const Color seedTertiary = Color(0xFFE8C990); // pale gold

  // ── Semantic colors (latency chips, status) ─────────────────────────
  // These are independent of brand — green/amber/red carry universal
  // meaning (good/medium/poor) and shouldn't change with re-theming.
  static const Color semanticGood = Color(0xFF4A8030);
  static const Color semanticGoodBgLight = Color(0xFFE8F5E0);
  static const Color semanticGoodBgDark = Color(0xFF1A2E14);

  static const Color semanticMedium = Color(0xFF9A6820);
  static const Color semanticMediumBgLight = Color(0xFFFEF3E0);
  static const Color semanticMediumBgDark = Color(0xFF332817);

  static const Color semanticPoor = Color(0xFF9A3020);
  static const Color semanticPoorBgLight = Color(0xFFFCE8E6);
  static const Color semanticPoorBgDark = Color(0xFF3A1A16);

  /// Latency thresholds in ms — under [goodThresholdMs] is green,
  /// under [mediumThresholdMs] is amber, above is red.
  static const int goodThresholdMs = 150;
  static const int mediumThresholdMs = 400;
}

/// Builds the full light/dark ThemeData from [AppPalette] seeds.
/// Widgets should read colors from `Theme.of(context).colorScheme` and
/// `Theme.of(context).extension<ProxySmithColors>()` rather than
/// referencing [AppPalette] directly, so a future palette swap only
/// requires editing this file.
class AppTheme {
  AppTheme._();

  static ThemeData light({String languageCode = 'en'}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.seedPrimary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppPalette.seedPrimary,
      secondary: AppPalette.seedSecondary,
      surface: const Color(0xFFF5F0EB),
    );
    return _buildTheme(scheme, ProxySmithColors.light(), languageCode);
  }

  static ThemeData dark({String languageCode = 'en'}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.seedPrimary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppPalette.seedSecondary,
      secondary: AppPalette.seedTertiary,
      surface: const Color(0xFF1A1F2E),
    );
    return _buildTheme(scheme, ProxySmithColors.dark(), languageCode);
  }

  // ── Locale-aware font selection ─────────────────────────────────────
  // Roboto (Flutter/Android's default) has weak or missing Persian glyph
  // coverage, which is why Persian text looked bad. Vazirmatn is the
  // standard open-source font for Persian UI (also covers Latin cleanly),
  // so we switch the whole app's fontFamily when locale=fa.
  //
  // Requires: Vazirmatn font files bundled under assets/fonts/ and
  // declared in pubspec.yaml (see PUBSPEC_ADDITIONS.yaml).
  static String _fontForLocale(String languageCode) {
    return languageCode == 'fa' ? 'Vazirmatn' : 'Roboto';
  }

  static ThemeData _buildTheme(ColorScheme scheme, ProxySmithColors ext, String languageCode) {
    final fontFamily = _fontForLocale(languageCode);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: fontFamily,
      cardTheme: CardThemeData(
        color: ext.cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: ext.cardBorder, width: 0.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ),
      extensions: [ext],
    );
  }
}

/// Theme extension for colors that don't map cleanly onto Flutter's
/// built-in ColorScheme roles (card borders, muted text, chip backgrounds).
/// Keeping these here (rather than scattered as literals in widgets) is
/// what makes the whole palette swappable from one place.
class ProxySmithColors extends ThemeExtension<ProxySmithColors> {
  final Color cardBackground;
  final Color cardBorder;
  final Color mutedText;
  final Color subtleBackground;
  final Color goldBadge;
  final Color goldBadgeText;

  const ProxySmithColors({
    required this.cardBackground,
    required this.cardBorder,
    required this.mutedText,
    required this.subtleBackground,
    required this.goldBadge,
    required this.goldBadgeText,
  });

  factory ProxySmithColors.light() => const ProxySmithColors(
        cardBackground: Color(0xFFFFFFFF),
        cardBorder: Color(0xFFDDD5C8),
        mutedText: Color(0xFF9A8E7E),
        subtleBackground: Color(0xFFF5F0EB),
        goldBadge: Color(0xFFF9F0E0),
        goldBadgeText: Color(0xFFA07830),
      );

  factory ProxySmithColors.dark() => const ProxySmithColors(
        cardBackground: Color(0xFF222840),
        cardBorder: Color(0xFF2D3452),
        mutedText: Color(0xFF6E7A9A),
        subtleBackground: Color(0xFF1A1F2E),
        goldBadge: Color(0xFF3A2F1A),
        goldBadgeText: Color(0xFFE8C990),
      );

  @override
  ProxySmithColors copyWith({
    Color? cardBackground,
    Color? cardBorder,
    Color? mutedText,
    Color? subtleBackground,
    Color? goldBadge,
    Color? goldBadgeText,
  }) {
    return ProxySmithColors(
      cardBackground: cardBackground ?? this.cardBackground,
      cardBorder: cardBorder ?? this.cardBorder,
      mutedText: mutedText ?? this.mutedText,
      subtleBackground: subtleBackground ?? this.subtleBackground,
      goldBadge: goldBadge ?? this.goldBadge,
      goldBadgeText: goldBadgeText ?? this.goldBadgeText,
    );
  }

  @override
  ProxySmithColors lerp(ThemeExtension<ProxySmithColors>? other, double t) {
    if (other is! ProxySmithColors) return this;
    return ProxySmithColors(
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      subtleBackground: Color.lerp(subtleBackground, other.subtleBackground, t)!,
      goldBadge: Color.lerp(goldBadge, other.goldBadge, t)!,
      goldBadgeText: Color.lerp(goldBadgeText, other.goldBadgeText, t)!,
    );
  }
}
