import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/pipeline_screen.dart';

void main() => runApp(const ProxySmithApp());

/// Root widget. Owns theme-mode and locale state so both can be toggled
/// from anywhere in the app (top bar switches) without a state management
/// package — this app is small enough that InheritedWidget-via-StatefulWidget
/// is the right amount of complexity.
class ProxySmithApp extends StatefulWidget {
  const ProxySmithApp({super.key});

  /// Lets descendant widgets (the theme/language toggles in the top bar)
  /// reach up and flip app-wide state without prop-drilling callbacks
  /// through every intermediate widget.
  static ProxySmithAppState of(BuildContext context) {
    return context.findAncestorStateOfType<ProxySmithAppState>()!;
  }

  @override
  State<ProxySmithApp> createState() => ProxySmithAppState();
}

class ProxySmithAppState extends State<ProxySmithApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  Locale _locale = const Locale('en');

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;

  void toggleTheme(bool isDark) {
    setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
  }

  void setLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProxySmith',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('fa'),
      ],
      // Full RTL flip for Persian — Flutter handles this automatically via
      // Directionality once locale=fa, because GlobalWidgetsLocalizations
      // reports fa as an RTL language. No manual mirroring needed.
      home: const PipelineScreen(),
    );
  }
}