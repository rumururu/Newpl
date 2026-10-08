import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'profile.dart';
import 'world.dart';

class SaveService {
  static const _worldKey = 'star_settlers_world_v2';
  static const _profileKey = 'star_settlers_profile_v1';

  static Future<void> save(GameWorld w) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_worldKey, jsonEncode(w.toJson()));
    await saveProfile(w.profile);
  }

  static Future<GameWorld?> load(Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_worldKey);
    if (raw == null) return null;
    try {
      return GameWorld.fromJson(jsonDecode(raw) as Map<String, dynamic>, profile);
    } catch (_) {
      return null; // 손상된 저장 파일은 무시
    }
  }

  static Future<bool> hasSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_worldKey);
  }

  static Future<void> clearWorld() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_worldKey);
  }

  static Future<void> saveProfile(Profile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(p.toJson()));
    p.dirty = false;
  }

  static Future<Profile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null) return Profile();
    try {
      return Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Profile();
    }
  }

  /// 모든 데이터 삭제 (설정 > 초기화)
  static Future<void> wipeAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_worldKey);
    await prefs.remove(_profileKey);
  }
}
