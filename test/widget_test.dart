import 'package:flutter_test/flutter_test.dart';
import 'package:star_settlers/game/crew.dart';
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
      expect(storyStepAt(storySteps.length).key, 'sectorBoss');
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
}
