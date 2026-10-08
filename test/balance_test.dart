
import 'package:flutter_test/flutter_test.dart';
import 'package:star_settlers/game/models.dart';
import 'package:star_settlers/game/world.dart';

/// 간단한 봇: 가까운 적에게 다가가 자동 조준 사격, 체력이 낮으면 기지로 후퇴,
/// 돈이 모이면 업그레이드/정착.
Map<String, num> playBot(int seed, double minutes, {bool smart = true}) {
  final w = GameWorld(seed: seed);
  final input = InputState()
    ..fire = true
    ..autoAim = smart;
  var deaths = 0;
  for (var t = 0.0; t < minutes * 60; t += 1 / 30) {
    final p = w.player;
    if (!p.alive) {
      deaths++;
      w.respawnAtBase();
    }
    Offset target;
    if (smart && p.hp < w.playerMaxHp * 0.35) {
      target = w.stations.first.pos;
    } else if (w.pirates.isNotEmpty) {
      final e = w.pirates.reduce((a, b) =>
          (a.pos - p.pos).distance < (b.pos - p.pos).distance ? a : b);
      target = (e.pos - p.pos).distance > 300 ? e.pos : p.pos + (p.pos - e.pos);
    } else {
      final a = w.asteroids.reduce((a, b) =>
          (a.pos - p.pos).distance < (b.pos - p.pos).distance ? a : b);
      target = a.pos;
    }
    final to = target - p.pos;
    input.move = to.distance > 40 ? to.normalized() : Offset.zero;
    w.update(1 / 30, input);
    // 소비
    for (final k in [UpgradeKind.weapon, UpgradeKind.hull, UpgradeKind.engine]) {
      if (w.canAfford(w.upgradeCost(k)) && w.credits > 300) w.upgradeShip(k);
    }
    final pl = w.planets.first;
    if (w.canAfford(w.planetCost(pl))) w.upgradePlanet(pl);
  }
  return {
    'deaths': deaths,
    'kills': w.counter('kills'),
    'threat': w.threat,
    'weapon': w.weaponLevel,
    'credits': w.credits.round(),
    'colony': w.planets.first.colonyLevel,
  };
}

void main() {
  test('봇 10분 플레이 밸런스', () {
    final results = [for (final s in [1, 2, 3]) playBot(s, 10)];
    for (final r in results) {
      // ignore: avoid_print
      print(r);
    }
    final avgDeaths = results.map((r) => r['deaths']!).reduce((a, b) => a + b) / results.length;
    final avgKills = results.map((r) => r['kills']!).reduce((a, b) => a + b) / results.length;
    expect(avgKills, greaterThan(20), reason: '10분에 해적을 충분히 잡을 수 있어야 함');
    expect(avgDeaths, lessThan(8), reason: '10분에 너무 자주 죽으면 안 됨');
  });

  test('덜 똑똑한 봇(후퇴 안 함, 전방 조준만)', () {
    for (final s in [1, 2, 3]) {
      // ignore: avoid_print
      print(playBot(s, 10, smart: false));
    }
  });
}
