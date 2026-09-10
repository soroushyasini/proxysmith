import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/pipeline_screen.dart';
import 'models/app_settings.dart';
import 'services/settings_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStorage.load().onError(
    (Object _, StackTrace _) => AppSettings.defaults,
  );
  runApp(ProxySmithApp(initialSettings: settings));
}

/// Root widget. Owns theme-mode and locale state so both can be toggled
/// from anywhere in the app (top bar switches) without a state management
/// package — this app is small enough that InheritedWidget-via-StatefulWidget
/// is the right amount of complexity.
class ProxySmithApp extends StatefulWidget {
  const ProxySmithApp({super.key, this.initialSettings = AppSettings.defaults});

  final AppSettings initialSettings;

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
  late AppSettings _settings;

  ThemeMode get themeMode =>
      _settings.darkMode ? ThemeMode.dark : ThemeMode.light;
  Locale get locale => Locale(_settings.languageCode);
  AppSettings get settings => _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void updateSettings(AppSettings settings) {
    setState(() => _settings = settings);
    unawaited(SettingsStorage.save(settings).catchError((Object _) {}));
  }

  void toggleTheme(bool isDark) {
    updateSettings(_settings.copyWith(darkMode: isDark));
  }

  void setLocale(Locale locale) {
    updateSettings(_settings.copyWith(languageCode: locale.languageCode));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProxySmith',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(languageCode: locale.languageCode),
      darkTheme: AppTheme.dark(languageCode: locale.languageCode),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('fa')],
      // Full RTL flip for Persian — Flutter handles this automatically via
      // Directionality once locale=fa, because GlobalWidgetsLocalizations
      // reports fa as an RTL language. No manual mirroring needed.
      home: const PipelineScreen(),
    );
  }
}
