import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsStorage {
  static final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  static Future<AppSettings> load() async => AppSettings.sanitized(
    darkMode:
        await _preferences.getBool('darkMode') ?? AppSettings.defaults.darkMode,
    languageCode:
        await _preferences.getString('languageCode') ??
        AppSettings.defaults.languageCode,
    selectedSourceId: await _preferences.getString('selectedSourceId'),
    testCount:
        await _preferences.getInt('testCount') ??
        AppSettings.defaults.testCount,
    maxPingMs:
        await _preferences.getInt('maxPingMs') ??
        AppSettings.defaults.maxPingMs,
    concurrency:
        await _preferences.getInt('concurrency') ??
        AppSettings.defaults.concurrency,
    testUrl:
        await _preferences.getString('testUrl') ?? AppSettings.defaults.testUrl,
  );

  static Future<void> save(AppSettings settings) async {
    await Future.wait([
      _preferences.setBool('darkMode', settings.darkMode),
      _preferences.setString('languageCode', settings.languageCode),
      _preferences.setInt('testCount', settings.testCount),
      _preferences.setInt('maxPingMs', settings.maxPingMs),
      _preferences.setInt('concurrency', settings.concurrency),
      _preferences.setString('testUrl', settings.testUrl),
      if (settings.selectedSourceId case final sourceId?)
        _preferences.setString('selectedSourceId', sourceId),
    ]);
  }
}
