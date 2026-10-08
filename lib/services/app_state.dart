import 'package:flutter/services.dart';

import '../game/models.dart';
import '../game/profile.dart';
import '../game/save.dart';
import '../game/world.dart';
import 'audio.dart';
import 'monetization.dart';

/// 앱 전역 상태: 프로필, 결제, 오디오, 현재 월드
class AppState {
  AppState._();

  static Profile profile = Profile();
  static final MonetizationService money = MonetizationService.create();
  static GameWorld? world;

  static Future<void> init() async {
    profile = await SaveService.loadProfile();
    money.onGrant = grant;
    await money.init();
    AudioService.instance
      ..soundOn = profile.sound
      ..musicOn = profile.music;
    AudioService.instance.init();
  }

  static void haptic() {
    if (profile.haptics) HapticFeedback.lightImpact();
  }

  static void play(Sfx s) => AudioService.instance.play(s);

  /// 결제 완료 상품 지급 (중복 호출에도 안전하게)
  static void grant(String productId) {
    final p = profile;
    switch (productId) {
      case 'gems_100':
        p.gems += 100;
      case 'gems_550':
        p.gems += 550;
      case 'gems_1200':
        p.gems += 1200;
      case 'starter_pack':
        if (p.starterBought) break;
        p.starterBought = true;
        p.gems += 300;
        p.ownedSkins.add('galaxy');
        p.pendingStarCrew++;
      case 'premium_pass':
        p.premium = true;
        p.ownedSkins.add('gold');
    }
    p.dirty = true;
    deliverPending();
    SaveService.saveProfile(p);
    play(Sfx.gem);
  }

  /// 결제로 받은 승무원을 현재 월드에 지급
  static void deliverPending() {
    final w = world;
    if (w == null) return;
    while (profile.pendingStarCrew > 0 && w.roster.length < GameWorld.maxRoster) {
      profile.pendingStarCrew--;
      w.grantCrew(3);
    }
  }
}
