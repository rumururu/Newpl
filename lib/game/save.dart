import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'world.dart';

class SaveService {
  static const _key = 'star_settlers_save_v1';

  static Future<void> save(GameWorld w) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(w.toJson()));
  }

  static Future<GameWorld?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return GameWorld.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // 손상된 저장 파일은 무시
    }
  }

  static Future<bool> hasSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
