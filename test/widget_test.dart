import 'package:flutter_test/flutter_test.dart';
import 'package:star_settlers/game/models.dart';
import 'package:star_settlers/game/world.dart';

void main() {
  test('월드 생성: 행성/기지/소행성이 만들어진다', () {
    final w = GameWorld(seed: 42);
    expect(w.planets.length, greaterThanOrEqualTo(5));
    expect(w.stations.length, 1);
    expect(w.asteroids.length, GameWorld.maxAsteroids);
    expect(w.player.alive, isTrue);
  });

  test('같은 시드면 같은 행성 배치', () {
    final a = GameWorld(seed: 7);
    final b = GameWorld(seed: 7);
    expect(a.planets.map((p) => p.pos).toList(), b.planets.map((p) => p.pos).toList());
  });

  test('행성 정착은 비용을 지불하고 수입을 만든다', () {
    final w = GameWorld(seed: 1)..credits = 1000;
    final p = w.planets.first;
    expect(w.upgradePlanet(p), isTrue);
    expect(p.colonyLevel, 1);
    expect(w.credits, 1000 - 150);
    expect(w.creditIncome, greaterThan(2)); // 기지 2 + 행성 3
  });

  test('자원이 부족하면 업그레이드 실패', () {
    final w = GameWorld(seed: 1)..credits = 0;
    expect(w.upgradeShip(UpgradeKind.weapon), isFalse);
    expect(w.weaponLevel, 0);
  });

  test('시뮬레이션 60초 동안 오류 없이 돌아간다', () {
    final w = GameWorld(seed: 3);
    final input = InputState()
      ..move = const Offset(1, 0)
      ..fire = true;
    for (var i = 0; i < 60 * 60; i++) {
      w.update(1 / 60, input);
    }
    expect(w.elapsed, closeTo(60, 0.1));
    expect(w.pirates, isNotEmpty);
  });

  test('해적을 격추하면 보상 아이템이 떨어진다', () {
    final w = GameWorld(seed: 5);
    w.pirates.add(Pirate(PirateKind.scout, w.player.pos + const Offset(0, -60), 1));
    w.player.angle = -1.5707963;
    final input = InputState()..fire = true;
    for (var i = 0; i < 30; i++) {
      w.update(1 / 60, input);
    }
    expect(w.kills, greaterThanOrEqualTo(1));
  });

  test('저장 후 불러오면 진행 상황이 유지된다', () {
    final w = GameWorld(seed: 9)..credits = 5000;
    w.upgradePlanet(w.planets.first);
    w.upgradeShip(UpgradeKind.engine);
    final w2 = GameWorld.fromJson(w.toJson());
    expect(w2.planets.first.colonyLevel, 1);
    expect(w2.engineLevel, 1);
    expect(w2.credits, closeTo(w.credits, 0.01));
    expect(w2.stations.length, w.stations.length);
  });
}
