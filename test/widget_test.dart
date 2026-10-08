import 'package:flutter_test/flutter_test.dart';
import 'package:star_settlers/game/crew.dart';
import 'package:star_settlers/game/home.dart';
import 'package:star_settlers/game/josa.dart';
import 'package:star_settlers/game/missions.dart';
import 'package:star_settlers/game/models.dart';
import 'package:star_settlers/game/profile.dart';
import 'package:star_settlers/game/ships.dart';
import 'package:star_settlers/game/world.dart';

GameWorld rich({int seed = 1}) => GameWorld(seed: seed)
  ..credits = 1e6
  ..ore = 1e6;

void runFor(GameWorld w, double sec, [InputState? input]) {
  final i = input ?? InputState();
  for (var t = 0.0; t < sec; t += 1 / 60) {
    w.update(1 / 60, i);
  }
}

void main() {
  group('월드', () {
    test('생성: 행성/기지/게이트/소행성', () {
      final w = GameWorld(seed: 42);
      expect(w.planets.length, greaterThanOrEqualTo(5));
      expect(w.planets.first.name, '테라노바');
      expect(w.stations.length, 1);
      expect(w.gates.where((g) => g.forward).length, 1);
      expect(w.asteroids.length, GameWorld.maxAsteroids);
      expect(w.dialogs, isNotEmpty);
    });

    test('같은 시드면 같은 배치', () {
      final a = GameWorld(seed: 7);
      final b = GameWorld(seed: 7);
      expect(a.planets.map((p) => p.pos).toList(), b.planets.map((p) => p.pos).toList());
    });

    test('3분 시뮬레이션이 오류 없이 돌아가고 해적이 등장', () {
      final w = GameWorld(seed: 3);
      final input = InputState()
        ..move = const Offset(1, 0.3)
        ..fire = true;
      runFor(w, 180, input);
      expect(w.totalTime, closeTo(180, 0.5));
      expect(w.pirates, isNotEmpty);
    });
  });

  group('개척/경제', () {
    test('정착은 비용을 내고 수입을 만든다', () {
      final w = GameWorld(seed: 1)..credits = 1000;
      final p = w.planets.first;
      final before = w.creditIncome;
      expect(w.upgradePlanet(p), isTrue);
      expect(p.colonyLevel, 1);
      expect(w.credits, 1000 - 150);
      expect(w.creditIncome, greaterThan(before));
    });

    test('자원이 부족하면 실패', () {
      final w = GameWorld(seed: 1)..credits = 0;
      expect(w.upgradeShip(UpgradeKind.weapon), isFalse);
      expect(w.weaponLevel, 0);
    });

    test('습격 중인 행성은 생산하지 않는다', () {
      final w = rich();
      final p = w.planets.first;
      w.upgradePlanet(p);
      expect(w.planetCreditRate(p), greaterThan(0));
      p.raided = true;
      expect(w.planetCreditRate(p), 0);
    });

    test('광석 판매', () {
      final w = GameWorld(seed: 1)..ore = 100;
      final c = w.credits;
      expect(w.sellOre(50), isTrue);
      expect(w.ore, 50);
      expect(w.credits, greaterThan(c));
    });
  });

  group('전투/스킬', () {
    test('해적 격추 시 보상 드롭과 카운트', () {
      final w = GameWorld(seed: 5);
      final c = w.credits;
      w.pirates.add(Pirate(PirateKind.scout, w.player.pos + const Offset(0, -60), 1));
      w.player.angle = -1.5707963;
      runFor(w, 1.5, InputState()..fire = true);
      expect(w.counter('kills'), greaterThanOrEqualTo(1));
      // 드롭된 크레딧은 자석으로 자동 회수된다
      expect(w.credits, greaterThan(c + 20));
    });

    test('미사일은 장착해야 쓸 수 있고 해적을 추적한다', () {
      final w = rich();
      expect(w.fireMissiles(), isFalse);
      w.upgradeShip(UpgradeKind.missile);
      final e = Pirate(PirateKind.raider, w.player.pos + const Offset(300, 0), 30);
      w.pirates.add(e);
      expect(w.fireMissiles(), isTrue);
      expect(w.missiles, isNotEmpty);
      runFor(w, 2);
      expect(w.pirates.contains(e), isFalse);
    });

    test('실드가 피해를 막는다', () {
      final w = rich();
      w.upgradeShip(UpgradeKind.shield);
      w.activateShield();
      final hp = w.player.hp;
      w.bullets.add(Bullet(w.player.pos, Offset.zero, 50, false));
      w.update(1 / 60, InputState());
      expect(w.player.hp, hp);
    });

    test('격추 → 부활 선택 (제자리 / 기지)', () {
      final w = GameWorld(seed: 2)..credits = 1000;
      w.player.hp = 1;
      w.bullets.add(Bullet(w.player.pos, Offset.zero, 50, false));
      w.update(1 / 60, InputState());
      expect(w.player.alive, isFalse);
      expect(w.player.awaitingRevive, isTrue);
      w.reviveHere();
      expect(w.player.alive, isTrue);
      expect(w.credits, greaterThanOrEqualTo(1000));

      w.player.invulnerable = 0;
      w.player.hp = 1;
      w.bullets.add(Bullet(w.player.pos, Offset.zero, 50, false));
      w.update(1 / 60, InputState());
      final before = w.credits;
      w.respawnAtBase();
      expect(w.credits, lessThan(before));
    });
  });

  group('승무원', () {
    test('영입·배치·보너스', () {
      final w = rich();
      final dmg = w.playerDamage;
      final c = w.recruitWithCredits();
      expect(c, isNotNull);
      expect(c!.assigned, isTrue);
      w.roster
        ..clear()
        ..add(CrewMember(id: 99, name: '테스트', role: CrewRole.gunner, rarity: 3, lookSeed: 1, assigned: true));
      expect(w.playerDamage, greaterThan(dmg));
    });

    test('배치 슬롯 제한', () {
      final w = rich();
      for (var i = 0; i < 5; i++) {
        w.recruitWithCredits();
      }
      expect(w.assignedCount, w.crewSlots);
    });

    test('확률표 합은 100%', () {
      expect(CrewMember.creditOdds.values.reduce((a, b) => a + b), 100);
      expect(CrewMember.gemOdds.values.reduce((a, b) => a + b), 100);
    });
  });

  group('임무/스토리', () {
    test('처치 임무 진행 및 보상', () {
      final w = GameWorld(seed: 8);
      w.update(1 / 60, InputState()); // 게시판 생성
      final m = Mission(id: 999, type: MissionType.kill, target: 1, rewardCredits: 500);
      w.missionOffers.add(m);
      expect(w.acceptMission(m), isTrue);
      final c = w.credits;
      w.pirates.add(Pirate(PirateKind.scout, w.player.pos + const Offset(0, -60), 1));
      w.player.angle = -1.5707963;
      runFor(w, 0.6, InputState()..fire = true);
      expect(w.activeMissions.contains(m), isFalse);
      expect(w.credits, greaterThan(c + 400));
    });

    test('스토리 1단계: 소행성 3개 부수면 다음 단계', () {
      final w = GameWorld(seed: 4);
      expect(w.storyIndex, 0);
      w.counters['asteroids'] = 3;
      runFor(w, 1);
      expect(w.storyIndex, 1);
    });

    test('스토리 무한 단계 생성', () {
      expect(storyStepAt(storySteps.length).key, 'sectorBosses');
      expect(storyStepAt(storySteps.length).target, 2);
      expect(storyStepAt(storySteps.length + 1).key, 'sector');
    });
  });

  group('섹터/이벤트', () {
    test('두목 격파 전에는 게이트가 잠겨 있다', () {
      final w = GameWorld(seed: 6);
      final gate = w.gates.firstWhere((g) => g.forward);
      expect(w.warp(gate), isFalse);
      w.bossDefeated = true;
      expect(w.warp(gate), isTrue);
      expect(w.sector, 1);
      expect(w.gates.any((g) => !g.forward), isTrue);
    });

    test('섹터를 오가도 식민지가 유지되고 다른 섹터 수입이 합산된다', () {
      final w = rich(seed: 11);
      w.upgradePlanet(w.planets.first);
      w.bossDefeated = true;
      w.warp(w.gates.firstWhere((g) => g.forward));
      expect(w.otherSectorCredits, greaterThan(0));
      w.warp(w.gates.firstWhere((g) => !g.forward));
      expect(w.sector, 0);
      expect(w.planets.first.colonyLevel, 1);
      expect(w.bossDefeated, isTrue);
    });

    test('식민지 습격: 해적을 모두 물리치면 보상', () {
      final w = rich(seed: 12);
      w.upgradePlanet(w.planets.first);
      final ev = w.startEvent(EventKind.raid)!;
      expect(w.pirates.where((e) => e.eventId == ev.id), isNotEmpty);
      w.pirates.removeWhere((e) => e.eventId == ev.id);
      final gems = w.profile.gems;
      w.update(1 / 60, InputState());
      expect(w.events, isEmpty);
      expect(w.profile.gems, gems + 2);
    });

    test('떠돌이 상인 거래', () {
      final w = rich(seed: 13);
      w.startEvent(EventKind.merchant);
      expect(w.merchantCrew, isNotNull);
      expect(w.buyMerchantCrew(), isTrue);
      expect(w.roster.length, 1);
      expect(w.buyGemsFromMerchant(), isTrue);
    });
  });

  group('프로필/저장', () {
    test('저장 후 불러오면 진행 상황 유지', () {
      final w = rich(seed: 9);
      w.upgradePlanet(w.planets.first);
      w.upgradeShip(UpgradeKind.engine);
      w.recruitWithCredits();
      w.bossDefeated = true;
      w.warp(w.gates.firstWhere((g) => g.forward));
      final w2 = GameWorld.fromJson(w.toJson(), w.profile);
      expect(w2.sector, 1);
      expect(w2.sectors[0]!.colonyLevels.first, 1);
      expect(w2.level(UpgradeKind.engine), 1);
      expect(w2.roster.length, 1);
      expect(w2.credits, closeTo(w.credits, 0.01));
    });

    test('오프라인 수입은 최대 2시간, 프리미엄 8시간', () {
      final w = rich(seed: 10);
      w.upgradePlanet(w.planets.first);
      final now = DateTime(2026, 1, 1, 12);
      w.savedAt = now.subtract(const Duration(hours: 10));
      final (sec, c, _) = w.offlineEarnings(now);
      expect(sec, 7200);
      expect(c, greaterThan(0));
      w.profile.premium = true;
      expect(w.offlineEarnings(now).$1, 8 * 3600);
    });

    test('업적 달성과 수령', () {
      final p = Profile();
      p.addStat('kills');
      final a = achievements.firstWhere((a) => a.id == 'first_blood');
      expect(p.claimable, contains(a));
      expect(p.claim(a), isTrue);
      expect(p.gems, a.gems);
      expect(p.claim(a), isFalse);
    });

    test('출석: 연속 출석과 끊김', () {
      final p = Profile();
      final d1 = DateTime(2026, 3, 1);
      expect(p.claimLogin(d1), loginRewards[0]);
      expect(p.pendingLogin(d1), isNull);
      expect(p.claimLogin(DateTime(2026, 3, 2)), loginRewards[1]);
      expect(p.loginStreak, 2);
      expect(p.claimLogin(DateTime(2026, 3, 5)), loginRewards[0]);
      expect(p.loginStreak, 1);
    });

    test('광고 젬은 하루 3회', () {
      final p = Profile();
      final d = DateTime(2026, 3, 1);
      for (var i = 0; i < 3; i++) {
        expect(p.claimAdGems(d), isTrue);
      }
      expect(p.claimAdGems(d), isFalse);
      expect(p.claimAdGems(DateTime(2026, 3, 2)), isTrue);
    });

    test('프로필 JSON 왕복', () {
      final p = Profile()
        ..gems = 77
        ..premium = true
        ..skin = 'gold';
      p.ownedSkins.add('gold');
      p.addStat('kills', 5);
      final q = Profile.fromJson(p.toJson());
      expect(q.gems, 77);
      expect(q.premium, isTrue);
      expect(q.ownedSkins, contains('gold'));
      expect(q.stat('kills'), 5);
    });
  });

  test('한국어 조사', () {
    expect(eul('테라노바'), '테라노바를');
    expect(eul('볼카노'), '볼카노를');
    expect(eul('헤이븐 기지'), '헤이븐 기지를');
    expect(iGa('루비아'), '루비아가');
    expect(iGa('정거장 2호'), '정거장 2호가');
    expect(iGa('뭉치'), '뭉치가');
    expect(iGa('콩이'), '콩이가');
    expect(iGa('별'), '별이');
    expect(euro('유자'), '유자로');
    expect(euro('망고별'), '망고별로');
    expect(euro('섹터 3'), '섹터 3으로');
    expect(euro('섹터 2'), '섹터 2로');
    expect(eul('⭐100'), '⭐100을');
  });

  test('두목 2페이즈: 체력 절반 이하에서 부하 소환', () {
    final w = GameWorld(seed: 21);
    final boss = Pirate(PirateKind.boss, w.player.pos + const Offset(0, -500), 100)..hp = 40;
    w.pirates.add(boss);
    final before = w.pirates.length;
    w.update(1 / 60, InputState());
    expect(boss.enraged, isTrue);
    expect(w.pirates.length, greaterThan(before));
  });

  test('튜토리얼 안내: 정착 단계에서 가까운 미정착 행성을 가리킴', () {
    final w = GameWorld(seed: 22);
    w.storyIndex = storySteps.indexWhere((s) => s.key == 'colonies');
    expect(w.storyTarget, w.planets.first.pos);
  });

  group('라운드3', () {
    test('일일 퀘스트: 날마다 3개, 진행·수령·보너스', () {
      final p = Profile();
      final d = DateTime(2026, 5, 1);
      p.refreshDaily(d);
      expect(p.dailyQuests.length, 3);
      for (final q in p.dailyQuests) {
        p.addStat(q.stat, q.target);
      }
      final before = p.gems;
      for (final q in p.dailyQuests) {
        expect(p.claimDaily(q.id), isTrue);
        expect(p.claimDaily(q.id), isFalse);
      }
      expect(p.dailyBonusReady, isTrue);
      expect(p.claimDaily('bonus'), isTrue);
      expect(p.gems, greaterThan(before + dailyBonusGems));
      // 다음 날에는 새로 뽑히고 진행도가 0부터
      p.refreshDaily(DateTime(2026, 5, 2));
      expect(p.dailyClaimed, isEmpty);
      expect(p.dailyQuests.every((q) => p.dailyProgress(q) == 0), isTrue);
    });

    test('일일 퀘스트 상태가 저장/복원된다', () {
      final p = Profile()..refreshDaily(DateTime(2026, 5, 1));
      final q = Profile.fromJson(p.toJson());
      expect(q.dailyIds, p.dailyIds);
      expect(q.dailyDay, p.dailyDay);
    });

    test('함선: 잠김/해금/교체 시 성능 반영', () {
      final w = rich(seed: 31);
      final inter = shipTypeById('interceptor');
      expect(w.switchShip(inter), isFalse);
      w.profile.maxStat('sector', 2);
      final speed = w.playerSpeed;
      expect(w.switchShip(inter), isTrue);
      expect(w.playerSpeed, greaterThan(speed));
      expect(w.player.hp, lessThanOrEqualTo(w.playerMaxHp));
    });

    test('함선 젬 구매', () {
      final w = rich(seed: 32);
      w.profile.gems = 1000;
      expect(w.buyShip(shipTypeById('phantom')), isTrue);
      expect(w.profile.shipType, 'phantom');
      expect(w.profile.gems, 1000 - shipTypeById('phantom').gemPrice);
    });

    test('전투 드론이 근처 적을 쏜다', () {
      final w = rich(seed: 33);
      w.upgradeShip(UpgradeKind.drone);
      final e = Pirate(PirateKind.scout, w.player.pos + const Offset(200, 0), 5);
      w.pirates.add(e);
      runFor(w, 3);
      expect(w.pirates.contains(e), isFalse);
    });

    test('은하 명예 보너스와 환생 조건', () {
      final w = rich(seed: 34);
      final inc = w.creditIncome;
      final dmg = w.playerDamage;
      expect(w.canAscend, isFalse);
      w.profile.honor = 4;
      expect(w.creditIncome, closeTo(inc * 1.2, 0.01));
      expect(w.playerDamage, closeTo(dmg * 1.12, 0.01));
      w.counters['maxSector'] = 3;
      expect(w.canAscend, isTrue);
      expect(w.honorGain, greaterThanOrEqualTo(1));
    });
  });

  group('버그 회귀', () {
    test('격추 상태로 저장하면 불러와도 격추 상태 (공짜 부활 방지)', () {
      final w = GameWorld(seed: 41);
      w.player.hp = 1;
      w.bullets.add(Bullet(w.player.pos, Offset.zero, 50, false));
      w.update(1 / 60, InputState());
      expect(w.player.alive, isFalse);
      final w2 = GameWorld.fromJson(w.toJson(), w.profile);
      expect(w2.player.alive, isFalse);
      expect(w2.player.awaitingRevive, isTrue);
    });

    test('유성우 소행성은 맵 밖으로 나가면 사라진다', () {
      final w = GameWorld(seed: 42);
      final a = Asteroid(const Offset(GameWorld.worldHalf + 50, 0), 20, 1)
        ..drift = const Offset(500, 0);
      w.asteroids.add(a);
      runFor(w, 0.5);
      expect(w.asteroids.contains(a), isFalse);
    });

    test('임무 게시판은 비워도 타이머 전에는 다시 채워지지 않는다', () {
      final w = GameWorld(seed: 43);
      w.update(1 / 60, InputState());
      for (final m in [...w.missionOffers]) {
        w.acceptMission(m);
      }
      for (final m in [...w.activeMissions]) {
        w.abandonMission(m);
      }
      w.update(1 / 60, InputState());
      expect(w.missionOffers, isEmpty);
    });

    test('시계를 되돌려도 출석/광고 젬 중복 수령 불가', () {
      final p = Profile();
      expect(p.claimLogin(DateTime(2026, 6, 2)), greaterThan(0));
      expect(p.claimLogin(DateTime(2026, 6, 1)), 0);
      for (var i = 0; i < 3; i++) {
        p.claimAdGems(DateTime(2026, 6, 2));
      }
      expect(p.claimAdGems(DateTime(2026, 6, 1)), isFalse);
    });

    test('이전 섹터로 돌아가도 새 섹터 두목 목표가 완료되지 않는다', () {
      final w = rich(seed: 44);
      w.counters['sectorBosses'] = 1;
      w.bossDefeated = true;
      w.warp(w.gates.firstWhere((g) => g.forward));
      w.storyIndex = storySteps.length; // 섹터 2 두목 단계 (누적 2 필요)
      w.warp(w.gates.firstWhere((g) => !g.forward));
      expect(w.bossDefeated, isTrue);
      final (v, t) = w.storyProgress;
      expect(v < t, isTrue);
    });

    test('불러오기 후 현상수배범은 플레이어 근처에 다시 등장', () {
      final w = GameWorld(seed: 45);
      w.player.pos = const Offset(3000, 3000);
      final m = Mission(id: 77, type: MissionType.bounty, target: 1, rewardCredits: 10, bountyName: '외눈 잭');
      w.activeMissions.add(m);
      final w2 = GameWorld.fromJson(w.toJson(), w.profile);
      final b = w2.pirates.firstWhere((e) => e.missionId == 77);
      expect((b.pos - const Offset(3000, 3000)).distance, lessThan(3500));
      expect((b.pos - Offset.zero).distance, greaterThan(500));
    });
  });

  group('내 행성', () {
    test('건설·업그레이드·레벨업과 보너스 반영', () {
      final w = rich(seed: 51);
      final inc = w.creditIncome;
      final hp = w.playerMaxHp;
      expect(w.buildHome(0, BuildingType.farm), isTrue);
      expect(w.buildHome(0, BuildingType.mine), isFalse); // 이미 지어진 칸
      expect(w.buildHome(1, BuildingType.tower), isTrue);
      expect(w.creditIncome, closeTo(inc * 1.03, 0.01));
      expect(w.playerMaxHp, closeTo(hp * 1.04, 0.01));
      expect(w.upgradeHome(0), isTrue);
      expect(w.home.levelOf(BuildingType.farm), 2);
      final slots = w.home.slots.length;
      expect(w.levelUpHome(), isTrue);
      expect(w.home.slots.length, slots + 2);
    });

    test('동상은 젬으로만', () {
      final w = rich(seed: 52)..profile.gems = 0;
      expect(w.buildHome(0, BuildingType.statue), isFalse);
      w.profile.gems = 100;
      expect(w.buildHome(0, BuildingType.statue), isTrue);
      expect(w.profile.gems, 100 - w.home.statueGemCost(0));
    });

    test('행성 선물은 8시간마다', () {
      final w = rich(seed: 53);
      final now = DateTime(2026, 7, 1, 10);
      final gems = w.profile.gems;
      expect(w.harvestHome(now), isNotNull);
      expect(w.profile.gems, greaterThan(gems));
      expect(w.harvestHome(now.add(const Duration(hours: 7))), isNull);
      expect(w.harvestHome(now.add(const Duration(hours: 8))), isNotNull);
    });

    test('놀이공원은 오프라인 효율을 올린다', () {
      final w = rich(seed: 54);
      w.upgradePlanet(w.planets.first);
      final now = DateTime(2026, 7, 1, 12);
      w.savedAt = now.subtract(const Duration(hours: 1));
      final base = w.offlineEarnings(now).$2;
      w.buildHome(0, BuildingType.park);
      expect(w.offlineEarnings(now).$2, closeTo(base * 1.1, base * 0.01));
    });

    test('내 행성은 프로필에 저장되고 환생해도 유지', () {
      final w = rich(seed: 55);
      w.buildHome(2, BuildingType.lab);
      w.home
        ..name = '토끼별'
        ..palette = 3;
      final p2 = Profile.fromJson(w.profile.toJson());
      expect(p2.home.name, '토끼별');
      expect(p2.home.slots[2]?.type, BuildingType.lab);
      final w2 = GameWorld(seed: 56, profile: p2);
      expect(w2.home.levelOf(BuildingType.lab), 1);
    });
  });
}
