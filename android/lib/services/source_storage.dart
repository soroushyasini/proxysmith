import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/config_source.dart';

/// Stores and retrieves user-defined subscription sources (alias + URL
/// pairs the user adds on the "Manage sources" screen). Built-in presets
/// from kBuiltInSources are never touched by this — only user additions
/// live here.
class SourceStorage {
  static const _key = 'user_config_sources_v1';

  static Future<List<ConfigSource>> loadUserSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ConfigSource.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveUserSources(List<ConfigSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(sources.map((s) => s.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}
