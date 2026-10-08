import 'dart:math';
import 'dart:ui';

import 'crew.dart';
import 'missions.dart';
import 'models.dart';
import 'profile.dart';

class InputState {
  Offset move = Offset.zero; // 길이 0..1
  bool fire = false;
}

enum UpgradeKind { weapon, hull, engine, missile, shield }

extension UpgradeInfo on UpgradeKind {
  String get label => switch (this) {
        UpgradeKind.weapon => '무기',
        UpgradeKind.hull => '장갑',
        UpgradeKind.engine => '엔진',
        UpgradeKind.missile => '유도 미사일',
        UpgradeKind.shield => '에너지 실드',
      };
  int get maxLevel => switch (this) {
        UpgradeKind.missile || UpgradeKind.shield => 5,
        _ => 8,
      };
}

/// 다른 섹터에 두고 온 개척 상태
class SectorSave {
  SectorSave({
    required this.colonyLevels,
    required this.stations,
    required this.elapsed,
    required this.bossDefeated,
    required this.bossesSpawned,
    required this.idleCredits,
    required this.idleOre,
  });
  final List<int> colonyLevels;
  final List<Map<String, dynamic>> stations;
  final double elapsed;
  final bool bossDefeated;
  final int bossesSpawned;
  final double idleCredits;
  final double idleOre;

  Map<String, dynamic> toJson() => {
        'colonies': colonyLevels,
        'stations': stations,
        'elapsed': elapsed,
        'boss': bossDefeated,
        'bosses': bossesSpawned,
        'ic': idleCredits,
        'io': idleOre,
      };

  static SectorSave fromJson(Map<String, dynamic> j) => SectorSave(
        colonyLevels: (j['colonies'] as List).cast<int>(),
        stations: (j['stations'] as List).cast<Map<String, dynamic>>(),
        elapsed: (j['elapsed'] as num).toDouble(),
        bossDefeated: j['boss'] as bool,
        bossesSpawned: j['bosses'] as int,
        idleCredits: (j['ic'] as num).toDouble(),
        idleOre: (j['io'] as num).toDouble(),
      );
}

const sectorNames = [
  '알파 성역', '베타 성운', '감마 협곡', '델타 해적지대', '엡실론 심연',
  '제타 얼음벨트', '에타 불꽃성단', '세타 유령항로', '이오타 왕관성운', '카파 블랙홀',
];

const _planetPool = [
  '아쿠아리스', '루비아', '프로스타', '볼카노', '젤리오', '솔라리스', '모모별',
  '네뷸라', '카시오페', '오로라', '두리안', '시나몬', '마시멜로', '팝콘별',
  '라벤더', '에메랄디아', '크림슨', '폴라리스', '베가', '리겔', '미라', '토파즈',
  '코발트', '사파이어', '오닉스', '페리도트', '민트별', '바닐라', '캐러멜',
  '피스타치오', '블루베리', '레몬별', '체리', '멜론', '키위', '망고별', '유자',
  '자몽', '호박별',
];

/// 게임 전체 상태와 규칙. 렌더링/위젯과 분리되어 있어 테스트 가능.
class GameWorld {
  GameWorld({int? seed, Profile? profile})
      : seed = seed ?? Random().nextInt(1 << 30),
        profile = profile ?? Profile() {
    _rng = Random(this.seed);
    _loadSector(0, null);
    player.pos = const Offset(0, 160);
    player.hp = playerMaxHp;
    say(Speaker.advisor, '선장님, 환영합니다! 저는 부관 미나예요.');
    _startStoryStep();
  }

  static const double worldHalf = 4000;
  static const int maxAsteroids = 110;
  static const int maxRoster = 12;

  final int seed;
  final Profile profile;
  late Random _rng;

  // ---------- 현재 섹터 ----------
  int sector = 0;
  double sectorElapsed = 0;
  bool bossDefeated = false;
  bool sectorBossSpawned = false;
  int bossesSpawned = 0;
  final planets = <Planet>[];
  final stations = <Station>[];
  final gates = <WarpGate>[];
  final sectors = <int, SectorSave>{};

  // ---------- 엔티티 ----------
  final player = PlayerShip();
  final pirates = <Pirate>[];
  final bullets = <Bullet>[];
  final missiles = <Missile>[];
  final asteroids = <Asteroid>[];
  final pickups = <Pickup>[];
  final particles = <Particle>[];
  final floats = <FloatText>[];
  final dialogs = <DialogLine>[];
  final events = <WorldEvent>[];
  final buffs = <PowerUpKind, double>{};

  /// UI에서 꺼내 재생하는 효과음 큐
  final sfx = <Sfx>[];

  // ---------- 진행 ----------
  double credits = 120;
  double ore = 20;
  final levels = {for (final k in UpgradeKind.values) k: 0};
  final counters = <String, int>{};
  final roster = <CrewMember>[];
  int recruitCount = 0;
  int _nextId = 1;
  final missionOffers = <Mission>[];
  final activeMissions = <Mission>[];
  double offerTimer = 0;
  int storyIndex = 0;
  int storyBase = 0;
  double storyTimer = 0;

  double totalTime = 0;
  double spawnTimer = 8;
  double eventTimer = 70;
  double jellyTimer = 20;
  double _secondTimer = 0;
  double shake = 0;
  double boostTime = 0;
  bool paused = false;

  // 떠돌이 상인
  CrewMember? merchantCrew;
  int merchantGemTrades = 0;
  Pickup? _supplyCapsule;
  Pickup? get supplyCapsule => _supplyCapsule;

  // ---------- 파생 스탯 ----------
  int level(UpgradeKind k) => levels[k]!;
  int get weaponLevel => level(UpgradeKind.weapon);

  double crewBonus(CrewRole r) =>
      roster.where((c) => c.assigned && c.role == r).fold(0, (s, c) => s + c.bonusPct) /
      100;

  int get crewSlots => 3 + (profile.extraCrewSlot ? 1 : 0);
  int get assignedCount => roster.where((c) => c.assigned).length;

  double get playerMaxHp =>
      (100 + level(UpgradeKind.hull) * 40.0) * (1 + crewBonus(CrewRole.engineer));
  double get playerSpeed =>
      (260 + level(UpgradeKind.engine) * 40.0) * (1 + crewBonus(CrewRole.pilot));
  double get playerDamage =>
      (10 + weaponLevel * 5.0) * (1 + crewBonus(CrewRole.gunner));
  double get playerFireInterval =>
      0.25 * pow(0.9, weaponLevel) * (buffs.containsKey(PowerUpKind.rapid) ? 0.45 : 1);
  int get playerShots => weaponLevel >= 6 ? 3 : (weaponLevel >= 3 ? 2 : 1);
  double get cooldownMul => 1 - min(0.5, crewBonus(CrewRole.scientist));
  double get missileCooldownMax => 8 * cooldownMul;
  double get shieldCooldownMax => 18 * cooldownMul;
  double get boostCooldownMax => 4 * cooldownMul;
  bool get shielded => player.shieldTime > 0 || buffs.containsKey(PowerUpKind.shield);

  double get sectorMul => 1 + sector * 0.5;
  double get costMul => 1 + sector * 0.3;
  String get sectorName =>
      sector < sectorNames.length ? sectorNames[sector] : '미지의 섹터 ${sector + 1}';

  int get colonyCount => planets.where((p) => p.colonyLevel > 0).length;

  double get threat =>
      1 +
      sector * 1.0 +
      sectorElapsed / 90 +
      colonyCount * 0.3 +
      stations.fold<int>(0, (s, st) => s + st.habitatLevel - 1) * 0.15;

  double get _incomeMul =>
      (1 + crewBonus(CrewRole.trader)) * (profile.premium ? 1.25 : 1);

  double planetCreditRate(Planet p) =>
      p.raided ? 0 : p.ratePerLevel.$1 * p.colonyLevel * sectorMul * _incomeMul;
  double planetOreRate(Planet p) => p.raided
      ? 0
      : p.ratePerLevel.$2 * p.colonyLevel * sectorMul * (1 + crewBonus(CrewRole.miner));
  double stationCreditRate(Station s) => s.baseCreditRate * sectorMul * _incomeMul;

  double get otherSectorCredits =>
      sectors.values.fold(0.0, (s, e) => s + e.idleCredits) * _incomeMul;
  double get otherSectorOre => sectors.values.fold(0.0, (s, e) => s + e.idleOre);

  double get creditIncome =>
      planets.fold(0.0, (s, p) => s + planetCreditRate(p)) +
      stations.fold(0.0, (s, st) => s + stationCreditRate(st)) +
      otherSectorCredits;
  double get oreIncome =>
      planets.fold(0.0, (s, p) => s + planetOreRate(p)) + otherSectorOre;

  /// 제국 가치 (진행도 점수)
  int get empireValue =>
      planets.fold<int>(0, (s, p) => s + p.colonyLevel * 100) +
      stations.fold<int>(0, (s, st) => s + (st.habitatLevel + st.turretLevel) * 120) +
      sectors.values.fold<int>(
          0, (s, e) => s + e.colonyLevels.fold<int>(0, (a, b) => a + b) * 100) +
      levels.values.fold<int>(0, (s, l) => s + l) * 80 +
      roster.fold<int>(0, (s, c) => s + c.rarity * c.level * 30) +
      sector * 1000 +
      counter('kills') * 5;

  int counter(String k) => counters[k] ?? 0;
  void _count(String k, [int n = 1]) => counters[k] = counter(k) + n;

  // ---------- 비용 ----------
  Cost planetCost(Planet p) {
    final c = p.baseCost();
    return ((c.$1 * costMul).round(), (c.$2 * costMul).round());
  }

  Cost upgradeCost(UpgradeKind k) {
    final lv = level(k);
    return switch (k) {
      UpgradeKind.missile || UpgradeKind.shield => (
          (250 * pow(1.8, lv)).round(),
          50 * (lv + 1)
        ),
      _ => ((100 * pow(1.6, lv)).round(), 30 * lv),
    };
  }

  Cost get stationBuildCost =>
      (((400 + (stations.length - 1) * 200) * costMul).round(), 150);
  Cost habitatCost(Station s) {
    final c = s.habitatCost;
    return ((c.$1 * costMul).round(), (c.$2 * costMul).round());
  }

  Cost turretCost(Station s) {
    final c = s.turretCost;
    return ((c.$1 * costMul).round(), (c.$2 * costMul).round());
  }

  int get recruitCost => 300 + recruitCount * 150;
  static const recruitGemCost = 30;

  double get orePrice =>
      (2 + sector * 0.6) * (1 + 0.35 * sin(totalTime / 40));

  // ---------- 섹터 생성 / 이동 ----------
  void _loadSector(int index, SectorSave? save) {
    sector = index;
    planets.clear();
    stations.clear();
    gates.clear();
    asteroids.clear();
    pirates.clear();
    bullets.clear();
    missiles.clear();
    pickups.clear();
    events.clear();
    merchantCrew = null;
    _supplyCapsule = null;

    final r = Random(seed + index * 7919);
    final kinds = PlanetKind.values;
    final names = [..._planetPool]..shuffle(r);
    planets.add(Planet(index == 0 ? '테라노바' : names.removeLast(),
        const Offset(900, -350), 110, index == 0 ? PlanetKind.garden : kinds[r.nextInt(kinds.length)]));
    var tries = 0;
    while (planets.length < 11 && tries < 2000) {
      tries++;
      final pos = Offset(randRange(r, -worldHalf + 400, worldHalf - 400),
          randRange(r, -worldHalf + 400, worldHalf - 400));
      if (pos.distance < 700) continue;
      if (planets.any((p) => (p.pos - pos).distance < 1100)) continue;
      final kind = kinds[r.nextInt(kinds.length)];
      final radius =
          kind == PlanetKind.gas ? randRange(r, 150, 200) : randRange(r, 90, 140);
      planets.add(Planet(names.removeLast(), pos, radius, kind));
    }

    // 워프 게이트: 앞으로 가는 게이트는 멀리, 돌아가는 게이트는 시작점 근처
    Offset gatePos;
    var gt = 0;
    do {
      final a = r.nextDouble() * 2 * pi;
      gatePos = OffsetX.fromAngle(a, randRange(r, 2600, 3400));
      gt++;
    } while (gt < 100 &&
        (gatePos.dx.abs() > worldHalf - 200 ||
            gatePos.dy.abs() > worldHalf - 200 ||
            planets.any((p) => (p.pos - gatePos).distance < p.radius + 300)));
    gates.add(WarpGate(gatePos, true));
    if (index > 0) gates.add(WarpGate(const Offset(-450, 250), false));

    if (save != null) {
      for (var i = 0; i < save.colonyLevels.length && i < planets.length; i++) {
        planets[i].colonyLevel = save.colonyLevels[i];
      }
      for (final s in save.stations) {
        stations.add(_stationFromJson(s));
      }
      sectorElapsed = save.elapsed;
      bossDefeated = save.bossDefeated;
      bossesSpawned = save.bossesSpawned;
    } else {
      stations.add(Station(index == 0 ? '헤이븐 기지' : '$sectorName 전진기지', Offset.zero)
        ..hp = 300);
      sectorElapsed = 0;
      bossDefeated = false;
      bossesSpawned = 0;
    }
    if (stations.isEmpty) {
      stations.add(Station('$sectorName 전진기지', Offset.zero));
    }
    sectorBossSpawned = false;
    for (var i = 0; i < maxAsteroids; i++) {
      _spawnAsteroid(awayFrom: Offset.zero, minDist: 500);
    }
  }

  SectorSave _saveCurrentSector() => SectorSave(
        colonyLevels: planets.map((p) => p.colonyLevel).toList(),
        stations: stations.map(_stationToJson).toList(),
        elapsed: sectorElapsed,
        bossDefeated: bossDefeated,
        bossesSpawned: bossesSpawned,
        idleCredits: planets.fold(0.0, (s, p) => s + p.ratePerLevel.$1 * p.colonyLevel * sectorMul) +
            stations.fold(0.0, (s, st) => s + st.baseCreditRate * sectorMul),
        idleOre: planets.fold(0.0, (s, p) => s + p.ratePerLevel.$2 * p.colonyLevel * sectorMul),
      );

  WarpGate? get nearbyGate {
    for (final g in gates) {
      if ((g.pos - player.pos).distance < 160) return g;
    }
    return null;
  }

  bool gateOpen(WarpGate g) => !g.forward || bossDefeated;

  bool warp(WarpGate g) {
    if (!gateOpen(g) || !player.alive) return false;
    final from = sector;
    final to = g.forward ? sector + 1 : sector - 1;
    sectors[from] = _saveCurrentSector();
    final save = sectors.remove(to);
    _loadSector(to, save);
    // 섹터에 묶인 임무는 취소
    final cancelled = activeMissions
        .where((m) => m.type == MissionType.deliver || m.type == MissionType.bounty)
        .toList();
    activeMissions.removeWhere(cancelled.contains);
    missionOffers.clear();
    offerTimer = 0;
    // 도착 위치
    final arrive = g.forward
        ? (to > 0 ? const Offset(-450, 250) : Offset.zero)
        : gates.firstWhere((x) => x.forward).pos;
    player
      ..pos = arrive + const Offset(0, 180)
      ..vel = Offset.zero
      ..invulnerable = 2;
    if (to > counter('maxSector')) counters['maxSector'] = to;
    profile.maxStat('sector', to + 1);
    sfx.add(Sfx.warp);
    shake = 12;
    _burst(player.pos, const Color(0xFFB388FF), 80);
    say(Speaker.advisor, '$sectorName에 도착했어요!${save == null ? ' 새로운 개척지예요.' : ''}');
    if (cancelled.isNotEmpty) {
      say(Speaker.advisor, '이전 섹터의 운송·현상수배 임무는 취소됐어요.');
    }
    return true;
  }

  void _spawnAsteroid({required Offset awayFrom, double minDist = 900}) {
    for (var t = 0; t < 50; t++) {
      final pos = Offset(randRange(_rng, -worldHalf, worldHalf),
          randRange(_rng, -worldHalf, worldHalf));
      if ((pos - awayFrom).distance < minDist) continue;
      if (planets.any((p) => (p.pos - pos).distance < p.radius + 120)) continue;
      if (stations.any((s) => (s.pos - pos).distance < 250)) continue;
      if (gates.any((g) => (g.pos - pos).distance < 200)) continue;
      asteroids.add(Asteroid(pos, randRange(_rng, 18, 55), _rng.nextInt(99999)));
      return;
    }
  }

  void say(Speaker s, String text) {
    if (dialogs.any((d) => d.text == text)) return;
    dialogs.add(DialogLine(s, text));
    if (dialogs.length > 5) dialogs.removeAt(0);
  }

  void _float(Offset pos, String text, Color c, {bool big = false}) {
    floats.add(FloatText(pos + Offset(randRange(_rng, -10, 10), -10), text, c, big: big));
    if (floats.length > 60) floats.removeAt(0);
  }

  /// 현재 임무 목표 위치들 (화살표/미니맵 표시용)
  List<Offset> get missionTargets => [
        for (final m in activeMissions)
          if (m.type == MissionType.deliver &&
              m.planetIndex != null &&
              m.planetIndex! < planets.length)
            planets[m.planetIndex!].pos,
        for (final e in pirates)
          if (e.name != null || e.sectorBoss) e.pos,
      ];

  // ---------- 상호작용 ----------
  Planet? get nearbyPlanet {
    for (final p in planets) {
      if ((p.pos - player.pos).distance < p.radius + 130) return p;
    }
    return null;
  }

  Station? get nearbyStation {
    for (final s in stations) {
      if ((s.pos - player.pos).distance < 220) return s;
    }
    return null;
  }

  WorldEvent? get nearbyMerchant {
    for (final e in events) {
      if (e.kind == EventKind.merchant && (e.pos - player.pos).distance < 200) return e;
    }
    return null;
  }

  bool get canBuildStationHere =>
      player.alive &&
      nearbyStation == null &&
      planets.every((p) => (p.pos - player.pos).distance > p.radius + 300) &&
      stations.every((s) => (s.pos - player.pos).distance > 900) &&
      gates.every((g) => (g.pos - player.pos).distance > 400);

  bool canAfford(Cost cost) => credits >= cost.$1 && ore >= cost.$2;

  bool _pay(Cost cost) {
    if (!canAfford(cost)) return false;
    credits -= cost.$1;
    ore -= cost.$2;
    return true;
  }

  bool upgradePlanet(Planet p) {
    if (p.colonyLevel >= Planet.maxLevel) return false;
    if (!_pay(planetCost(p))) return false;
    p.colonyLevel++;
    if (p.colonyLevel == 1) {
      _count('colonies');
      profile.addStat('colonies');
      say(Speaker.captain, '${p.name}에 깃발을 꽂았다! 정착 완료!');
    } else {
      say(Speaker.advisor, '${p.name} 식민지가 Lv.${p.colonyLevel}로 성장했어요.');
    }
    if (p.colonyLevel == Planet.maxLevel) profile.maxStat('maxColony', 1);
    sfx.add(Sfx.upgrade);
    _burst(p.pos + Offset(0, -p.radius), const Color(0xFF7CFFB2), 30);
    return true;
  }

  bool buildStation() {
    if (!canBuildStationHere) return false;
    if (!_pay(stationBuildCost)) return false;
    final st = Station('정거장 ${stations.length + 1}호', player.pos + const Offset(0, -140));
    st.hp = st.maxHp;
    stations.add(st);
    profile.addStat('stations');
    sfx.add(Sfx.upgrade);
    say(Speaker.advisor, '${st.name} 건설 완료! 수입이 늘어납니다.');
    _burst(st.pos, const Color(0xFF8AD8FF), 40);
    return true;
  }

  bool upgradeHabitat(Station s) {
    if (s.habitatLevel >= Station.maxLevel) return false;
    if (!_pay(habitatCost(s))) return false;
    s.habitatLevel++;
    s.hp = s.maxHp;
    sfx.add(Sfx.upgrade);
    say(Speaker.advisor, '${s.name} 거주구역 Lv.${s.habitatLevel}!');
    return true;
  }

  bool upgradeTurret(Station s) {
    if (s.turretLevel >= Station.maxLevel) return false;
    if (!_pay(turretCost(s))) return false;
    s.turretLevel++;
    sfx.add(Sfx.upgrade);
    say(Speaker.advisor, '${s.name} 방어포탑 Lv.${s.turretLevel}!');
    return true;
  }

  bool upgradeShip(UpgradeKind k) {
    if (level(k) >= k.maxLevel) return false;
    if (!_pay(upgradeCost(k))) return false;
    levels[k] = level(k) + 1;
    sfx.add(Sfx.upgrade);
    switch (k) {
      case UpgradeKind.weapon:
        say(Speaker.captain, '무기 강화! 해적들 각오해라!');
      case UpgradeKind.hull:
        player.hp = playerMaxHp;
        say(Speaker.captain, '장갑 강화! 이제 좀 든든하군.');
      case UpgradeKind.engine:
        say(Speaker.captain, '엔진 강화! 더 빠르게!');
      case UpgradeKind.missile:
        say(Speaker.captain, level(k) == 1 ? '유도 미사일 장착! (Q)' : '미사일 강화!');
      case UpgradeKind.shield:
        say(Speaker.captain, level(k) == 1 ? '에너지 실드 장착! (F)' : '실드 강화!');
    }
    return true;
  }

  bool sellOre(int amount) {
    final n = min(amount, ore.floor());
    if (n <= 0) return false;
    ore -= n;
    final gain = n * orePrice;
    credits += gain;
    sfx.add(Sfx.coin);
    say(Speaker.advisor, '광석 $n개를 💰${gain.round()}에 팔았어요.');
    return true;
  }

  static const creditPackGems = 20;
  int get creditPackAmount => (1500 * sectorMul).round();

  bool buyCreditsWithGems() {
    if (!profile.spendGems(creditPackGems)) return false;
    credits += creditPackAmount;
    sfx.add(Sfx.coin);
    return true;
  }

  // ---------- 승무원 ----------
  CrewMember? recruitWithCredits() {
    if (roster.length >= maxRoster) return null;
    if (!_pay((recruitCost, 0))) return null;
    return _addCrew(CrewMember.random(_rng, _nextId++, odds: CrewMember.creditOdds));
  }

  CrewMember? recruitWithGems() {
    if (roster.length >= maxRoster) return null;
    if (!profile.spendGems(recruitGemCost)) return null;
    return _addCrew(CrewMember.random(_rng, _nextId++, odds: CrewMember.gemOdds));
  }

  CrewMember _addCrew(CrewMember c) {
    recruitCount++;
    if (assignedCount < crewSlots) c.assigned = true;
    roster.add(c);
    profile.addStat('crew');
    if (c.rarity == 3) profile.addStat('crew3');
    sfx.add(Sfx.gem);
    say(Speaker.advisor, '${c.stars} ${c.role.label} ${c.name}이(가) 합류했어요!');
    if (c.role == CrewRole.engineer) player.hp = min(player.hp, playerMaxHp);
    return c;
  }

  /// 결제 상품 등으로 지급되는 승무원
  CrewMember grantCrew(int rarity) =>
      _addCrew(CrewMember.random(_rng, _nextId++, odds: {rarity: 100}));

  bool toggleAssign(CrewMember c) {
    if (c.assigned) {
      c.assigned = false;
    } else {
      if (assignedCount >= crewSlots) return false;
      c.assigned = true;
    }
    player.hp = min(player.hp, playerMaxHp);
    return true;
  }

  bool levelUpCrew(CrewMember c) {
    if (c.level >= CrewMember.maxLevel) return false;
    if (!_pay((c.levelUpCost, 0))) return false;
    c.level++;
    sfx.add(Sfx.upgrade);
    say(Speaker.advisor, '${c.name} Lv.${c.level}! 실력이 늘었어요.');
    return true;
  }

  void dismissCrew(CrewMember c) => roster.remove(c);

  // ---------- 임무 ----------
  void _refreshOffers() {
    missionOffers.clear();
    for (var i = 0; i < 3; i++) {
      missionOffers.add(_randomMission());
    }
    offerTimer = 180;
  }

  Mission _randomMission() {
    final t = threat;
    final gemBonus = _rng.nextDouble() < 0.15 ? 2 : 0;
    switch (_rng.nextInt(4)) {
      case 0:
        final n = 5 + (t * 2).round();
        return Mission(
            id: _nextId++, type: MissionType.kill, target: n,
            rewardCredits: (35 * n * sectorMul).round(), rewardGems: gemBonus);
      case 1:
        final n = 40 + _rng.nextInt(9) * 10;
        return Mission(
            id: _nextId++, type: MissionType.mine, target: n,
            rewardCredits: (3 * n * sectorMul).round(), rewardGems: gemBonus);
      case 2:
        final idx = _rng.nextInt(planets.length);
        final d = (planets[idx].pos - player.pos).distance;
        return Mission(
            id: _nextId++, type: MissionType.deliver, target: 1, planetIndex: idx,
            rewardCredits: ((150 + d / 8) * sectorMul).round(), rewardGems: gemBonus);
      default:
        return Mission(
            id: _nextId++, type: MissionType.bounty, target: 1,
            bountyName: bountyNames[_rng.nextInt(bountyNames.length)],
            rewardCredits: (450 * sectorMul).round(), rewardGems: 5);
    }
  }

  bool acceptMission(Mission m) {
    if (activeMissions.length >= 3 || !missionOffers.contains(m)) return false;
    missionOffers.remove(m);
    activeMissions.add(m);
    if (m.type == MissionType.bounty) _spawnBounty(m);
    if (m.type == MissionType.deliver) {
      say(Speaker.advisor, '화물을 실었어요! ${m.title(planets)}');
    }
    return true;
  }

  void abandonMission(Mission m) {
    activeMissions.remove(m);
    pirates.removeWhere((e) => e.missionId == m.id);
  }

  void _spawnBounty(Mission m) {
    final a = _rng.nextDouble() * 2 * pi;
    final pos = _clampWorld(player.pos + OffsetX.fromAngle(a, randRange(_rng, 1500, 2400)), (_) {});
    final e = Pirate(PirateKind.raider, pos, Pirate.baseHp(PirateKind.raider) * 5 * sectorMul,
        name: m.bountyName, dmgScale: 1.5 * (1 + sector * 0.3))
      ..missionId = m.id
      ..wanderAngle = a;
    pirates.add(e);
    m.bountySpawned = true;
    say(Speaker.pirate, '${m.bountyName}을(를) 잡겠다고? 어디 한번 와봐라!');
  }

  void _completeMission(Mission m) {
    activeMissions.remove(m);
    final c = (m.rewardCredits * (1 + crewBonus(CrewRole.trader))).round();
    credits += c;
    if (m.rewardGems > 0) profile.gems += m.rewardGems;
    _count('missions');
    profile.addStat('missions');
    sfx.add(Sfx.coin);
    _float(player.pos + const Offset(0, -40), '임무 완료! +💰$c', const Color(0xFFFFD54F), big: true);
    say(Speaker.advisor,
        '임무 완료: ${m.title(planets)}! 💰$c${m.rewardGems > 0 ? ' ⭐${m.rewardGems}' : ''}');
  }

  // ---------- 스토리 ----------
  StoryStep get story => storyStepAt(storyIndex);

  int storyValue(String key) => switch (key) {
        'shipLevels' => levels.values.fold(0, (s, l) => s + l),
        'crew' => roster.length,
        'stations' => stations.length,
        'sectorBoss' => bossDefeated ? 1 : 0,
        'sector' => counter('maxSector'),
        _ => counter(key),
      };

  (int, int) get storyProgress {
    final s = story;
    final v = storyValue(s.key) - (s.relative ? storyBase : 0);
    return (min(v, s.target), s.target);
  }

  void _startStoryStep() {
    final s = story;
    storyBase = storyValue(s.key);
    storyTimer = 0;
    for (final (sp, line) in s.lines) {
      say(sp, line);
    }
  }

  void _checkStory() {
    final (v, t) = storyProgress;
    if (v < t) return;
    final s = story;
    credits += s.credits;
    profile.gems += s.gems;
    sfx.add(Sfx.upgrade);
    _float(player.pos + const Offset(0, -50), '목표 달성! +💰${s.credits} ⭐${s.gems}',
        const Color(0xFF7CFFB2), big: true);
    storyIndex++;
    if (storyIndex == storySteps.length) profile.tutorialDone = true;
    _startStoryStep();
  }

  // ---------- 스킬 ----------
  bool fireMissiles() {
    final lv = level(UpgradeKind.missile);
    if (lv == 0 || player.missileCooldown > 0 || !player.alive) return false;
    player.missileCooldown = missileCooldownMax;
    final n = 2 + lv ~/ 2;
    final dmg = 22 * (1 + 0.3 * (lv - 1)) * (1 + crewBonus(CrewRole.gunner));
    final targets = [...pirates]
      ..sort((a, b) =>
          (a.pos - player.pos).distance.compareTo((b.pos - player.pos).distance));
    for (var i = 0; i < n; i++) {
      final a = player.angle + (i - (n - 1) / 2) * 0.5;
      final m = Missile(player.pos, OffsetX.fromAngle(a, 300) + player.vel * 0.5, dmg);
      if (targets.isNotEmpty) m.target = targets[i % targets.length];
      missiles.add(m);
    }
    sfx.add(Sfx.missile);
    return true;
  }

  bool activateShield() {
    final lv = level(UpgradeKind.shield);
    if (lv == 0 || player.shieldCooldown > 0 || !player.alive) return false;
    player.shieldCooldown = shieldCooldownMax;
    player.shieldTime = 2.5 + lv * 0.5;
    sfx.add(Sfx.shield);
    return true;
  }

  bool boost() {
    if (player.boostCooldown > 0 || !player.alive) return false;
    player.boostCooldown = boostCooldownMax;
    player.vel += OffsetX.fromAngle(player.angle, 750);
    player.invulnerable = max(player.invulnerable, 0.35);
    boostTime = 0.4;
    sfx.add(Sfx.boost);
    for (var i = 0; i < 16; i++) {
      particles.add(Particle(player.pos, -OffsetX.fromAngle(player.angle + randRange(_rng, -0.6, 0.6), 200),
          0.4, const Color(0xFF80D8FF), 3));
    }
    return true;
  }

  // ---------- 부활 ----------
  void reviveHere() {
    if (player.alive) return;
    player
      ..alive = true
      ..awaitingRevive = false
      ..pos = player.deathPos
      ..vel = Offset.zero
      ..hp = playerMaxHp
      ..invulnerable = 3;
    bullets.removeWhere((b) => !b.fromPlayer);
    for (final e in pirates) {
      if ((e.pos - player.pos).distance < 400) {
        e.vel = (e.pos - player.pos).normalized() * 500;
      }
    }
    sfx.add(Sfx.shield);
    say(Speaker.captain, '아직 끝나지 않았다!');
  }

  void respawnAtBase() {
    if (player.alive) return;
    final lost = (credits * 0.25).floor();
    credits -= lost;
    final home = stations
        .reduce((a, b) =>
            (a.pos - player.pos).distance < (b.pos - player.pos).distance ? a : b)
        .pos;
    player
      ..alive = true
      ..awaitingRevive = false
      ..pos = home + const Offset(0, 160)
      ..vel = Offset.zero
      ..hp = playerMaxHp
      ..invulnerable = 3;
    say(Speaker.advisor, '선장님 무사하시군요! 수리비로 💰$lost을(를) 썼어요.');
  }

  // ---------- 오프라인 수입 ----------
  DateTime? savedAt;

  /// 오프라인 시간(초)과 그동안의 수입
  (int seconds, double credits, double ore) offlineEarnings(DateTime now) {
    if (savedAt == null) return (0, 0, 0);
    final cap = profile.premium ? 8 * 3600 : 2 * 3600;
    final sec = now.difference(savedAt!).inSeconds.clamp(0, cap);
    if (sec < 60) return (0, 0, 0);
    return (sec, creditIncome * sec * 0.5, oreIncome * sec * 0.5);
  }

  void applyOffline(double c, double o) {
    credits += c;
    ore += o;
    savedAt = null;
  }

  // ---------- 업데이트 ----------
  void update(double dt, InputState input) {
    if (paused) return;
    dt = dt.clamp(0, 0.05);
    totalTime += dt;
    sectorElapsed += dt;
    storyTimer += dt;

    credits += creditIncome * dt;
    ore += oreIncome * dt;

    for (final k in buffs.keys.toList()) {
      final t = buffs[k]! - dt;
      if (t <= 0) {
        buffs.remove(k);
      } else {
        buffs[k] = t;
      }
    }
    shake = max(0, shake - dt * 30);
    boostTime = max(0, boostTime - dt);

    _updatePlayer(dt, input);
    _updatePirates(dt);
    _updateStations(dt);
    _updateMissiles(dt);
    _updateBullets(dt);
    _updateAsteroids(dt);
    _updatePickups(dt);
    _updateParticles(dt);
    _updateEvents(dt);
    _updateSpawning(dt);
    _updateMissions(dt);

    _secondTimer += dt;
    if (_secondTimer > 0.5) {
      _secondTimer = 0;
      _checkStory();
      profile.maxStat('credits', credits.floor());
    }

    for (final d in dialogs) {
      d.time -= dt;
    }
    dialogs.removeWhere((d) => d.time <= 0);
    for (final f in floats) {
      f.life -= dt;
      f.pos += Offset(0, -40 * dt);
    }
    floats.removeWhere((f) => f.life <= 0);
  }

  void _updatePlayer(double dt, InputState input) {
    final p = player;
    p.missileCooldown = max(0, p.missileCooldown - dt);
    p.shieldCooldown = max(0, p.shieldCooldown - dt);
    p.boostCooldown = max(0, p.boostCooldown - dt);
    p.shieldTime = max(0, p.shieldTime - dt);
    if (!p.alive) {
      p.deadTime += dt;
      // 오랫동안 선택이 없으면 기지에서 자동 재출격
      if (p.deadTime > 20) respawnAtBase();
      return;
    }
    p.invulnerable = max(0, p.invulnerable - dt);
    final move = input.move.clampLength(1);
    p.thrusting = move.distance > 0.1;
    if (p.thrusting) {
      final target = atan2(move.dy, move.dx);
      p.angle += angleDiff(p.angle, target).clamp(-8 * dt, 8 * dt);
      p.vel += OffsetX.fromAngle(p.angle, 900 * move.distance) * dt;
    }
    final cap = boostTime > 0 ? playerSpeed * 2.4 : playerSpeed;
    p.vel = (p.vel * pow(0.35, dt).toDouble()).clampLength(cap);
    p.pos += p.vel * dt;
    p.pos = _clampWorld(p.pos, (v) => p.vel = v);

    if (p.thrusting && _rng.nextDouble() < 0.7) {
      particles.add(Particle(
        p.pos - OffsetX.fromAngle(p.angle, 20),
        -OffsetX.fromAngle(p.angle + randRange(_rng, -0.3, 0.3), 120) + p.vel * 0.3,
        0.35,
        const Color(0xFFFFB347),
        randRange(_rng, 2, 4),
      ));
    }

    for (final a in asteroids) {
      final d = p.pos - a.pos;
      final minD = a.radius + 16;
      if (d.distance < minD && d.distance > 0) {
        final n = d.normalized();
        p.pos = a.pos + n * minD;
        p.vel = p.vel - n * (2 * (p.vel.dx * n.dx + p.vel.dy * n.dy)) * 0.6;
      }
    }

    if (nearbyStation != null && p.hp < playerMaxHp) {
      p.hp = min(playerMaxHp, p.hp + 20 * (1 + crewBonus(CrewRole.engineer)) * dt);
    }

    p.fireCooldown -= dt;
    if (input.fire && p.fireCooldown <= 0) {
      p.fireCooldown = playerFireInterval;
      final shots = playerShots;
      for (var i = 0; i < shots; i++) {
        final spread = shots == 1 ? 0.0 : (i - (shots - 1) / 2) * 0.12;
        final dir = OffsetX.fromAngle(p.angle + spread);
        bullets.add(Bullet(p.pos + dir * 22, dir * 760 + p.vel * 0.5, playerDamage, true));
      }
      sfx.add(Sfx.shoot);
    }
  }

  Offset _clampWorld(Offset pos, void Function(Offset) setVel) {
    const h = worldHalf;
    if (pos.dx.abs() > h || pos.dy.abs() > h) {
      setVel(Offset.zero);
      return Offset(pos.dx.clamp(-h, h), pos.dy.clamp(-h, h));
    }
    return pos;
  }

  void _damagePlayer(double dmg) {
    final p = player;
    if (!p.alive || p.invulnerable > 0) return;
    if (shielded) {
      _float(p.pos, '막음!', const Color(0xFF80D8FF));
      return;
    }
    p.hp -= dmg;
    shake = min(14, shake + 4 + dmg * 0.2);
    sfx.add(Sfx.hurt);
    _float(p.pos, '-${dmg.round()}', const Color(0xFFFF5252));
    if (p.hp <= 0) {
      p
        ..alive = false
        ..awaitingRevive = true
        ..deadTime = 0
        ..deathPos = p.pos;
      shake = 20;
      sfx.add(Sfx.bigExplode);
      _burst(p.pos, const Color(0xFFFF7043), 70);
      say(Speaker.pirate, ['크하하! 별것 아니군!', '다음엔 더 강해져서 와라, 꼬마!', '네 함선은 고철이 됐다!'][_rng.nextInt(3)]);
    }
  }

  void _updatePirates(double dt) {
    final exploded = <Pirate>[];
    for (final e in pirates) {
      e.hitFlash = max(0, e.hitFlash - dt);
      e.contactCooldown = max(0, e.contactCooldown - dt);

      if (e.kind == PirateKind.jelly) {
        _updateJelly(e, dt);
        continue;
      }

      // 목표 선택
      Offset? target;
      var targetDist = double.infinity;
      if (player.alive) {
        target = player.pos;
        targetDist = (player.pos - e.pos).distance;
      }
      final raid = e.eventId == null
          ? null
          : events.where((ev) => ev.id == e.eventId && ev.kind == EventKind.raid).firstOrNull;
      if (raid != null && raid.planet != null && targetDist > 450) {
        target = raid.planet!.pos;
        targetDist = (target - e.pos).distance;
      }
      for (final s in stations) {
        final d = (s.pos - e.pos).distance;
        if (d < 900 && d < targetDist) {
          target = s.pos;
          targetDist = d;
        }
      }

      Offset desired;
      if (target == null || (targetDist > 1600 && raid == null && e.name == null)) {
        e.wanderAngle += randRange(_rng, -1, 1) * dt;
        desired = OffsetX.fromAngle(e.wanderAngle, e.speed * 0.4);
      } else {
        final to = (target - e.pos).normalized();
        if (e.name != null && targetDist > 1100) {
          // 현상수배범은 멀리서는 배회
          e.wanderAngle += randRange(_rng, -1, 1) * dt;
          desired = OffsetX.fromAngle(e.wanderAngle, e.speed * 0.3);
        } else if (e.kind == PirateKind.bomber) {
          desired = to * e.speed;
        } else if (e.kind == PirateKind.sniper) {
          if (targetDist > 750) {
            desired = to * e.speed;
          } else if (targetDist < 520) {
            desired = to * -e.speed;
          } else {
            desired = Offset(-to.dy, to.dx) * e.speed * 0.5;
          }
        } else if (raid != null && target == raid.planet?.pos && targetDist < raid.planet!.radius + 200) {
          desired = Offset(-to.dy, to.dx) * e.speed * 0.7;
        } else if (targetDist > 260) {
          desired = to * e.speed;
        } else {
          desired = Offset(-to.dy, to.dx) * e.speed * 0.8 + to * -40;
        }
      }
      e.vel += (desired - e.vel) * min(1, 2.5 * dt);
      e.pos += e.vel * dt;
      e.pos = _clampWorld(e.pos, (v) => e.vel = v);

      if (target == null) continue;
      final aim = atan2(target.dy - e.pos.dy, target.dx - e.pos.dx);
      e.angle += angleDiff(e.angle, aim).clamp(-4 * dt, 4 * dt);

      if (e.kind == PirateKind.bomber) {
        if (targetDist < e.radius + 40) exploded.add(e);
        continue;
      }
      e.fireCooldown -= dt;
      final range = e.kind == PirateKind.sniper ? 950 : 560;
      if (targetDist < range &&
          e.fireCooldown <= 0 &&
          angleDiff(e.angle, aim).abs() < 0.35) {
        e.fireCooldown = e.fireInterval * randRange(_rng, 0.8, 1.3);
        final shots = e.kind == PirateKind.boss ? 3 : 1;
        final speed = e.kind == PirateKind.sniper ? 820.0 : 430.0;
        for (var i = 0; i < shots; i++) {
          final dir = OffsetX.fromAngle(e.angle + (i - (shots - 1) / 2) * 0.2);
          bullets.add(Bullet(e.pos + dir * e.radius, dir * speed, e.damage, false,
              life: e.kind == PirateKind.sniper ? 1.4 : 1.6,
              big: e.kind == PirateKind.sniper || e.kind == PirateKind.boss));
        }
      }
    }
    for (final e in exploded) {
      pirates.remove(e);
      _burst(e.pos, const Color(0xFFFFAB40), 50);
      sfx.add(Sfx.explode);
      shake = min(16, shake + 6);
      if (player.alive && (player.pos - e.pos).distance < 100) _damagePlayer(e.damage);
      for (final s in stations) {
        if ((s.pos - e.pos).distance < 120) s.hp -= e.damage;
      }
    }
  }

  void _updateJelly(Pirate e, double dt) {
    final d = player.alive ? (player.pos - e.pos).distance : double.infinity;
    Offset desired;
    if (d < 380) {
      desired = (player.pos - e.pos).normalized() * e.speed * 1.4;
    } else {
      e.wanderAngle += randRange(_rng, -0.6, 0.6) * dt;
      desired = OffsetX.fromAngle(e.wanderAngle, e.speed);
    }
    e.vel += (desired - e.vel) * min(1, 1.2 * dt);
    e.pos += e.vel * dt;
    e.pos = _clampWorld(e.pos, (v) {
      e.vel = v;
      e.wanderAngle += pi;
    });
    e.angle += dt;
    if (d < e.radius + 16 && e.contactCooldown <= 0) {
      e.contactCooldown = 0.8;
      _damagePlayer(e.damage * (1 + sector * 0.3));
    }
  }

  void _updateStations(double dt) {
    for (final s in stations) {
      s.spin += dt * 0.3;
      if (s.hp < s.maxHp) s.hp = min(s.maxHp, s.hp + 2 * dt);
      if (s.turretLevel == 0) continue;
      s.turretCooldown -= dt;
      if (s.turretCooldown > 0) continue;
      Pirate? best;
      var bestD = s.turretRange;
      for (final e in pirates) {
        if (!e.isPirate) continue;
        final d = (e.pos - s.pos).distance;
        if (d < bestD) {
          bestD = d;
          best = e;
        }
      }
      if (best != null) {
        s.turretCooldown = s.turretInterval;
        final dir = (best.pos - s.pos).normalized();
        bullets.add(Bullet(s.pos + dir * 50, dir * 700, s.turretDamage * sectorMul, true));
      }
    }
  }

  void _updateMissiles(double dt) {
    final dead = <Missile>{};
    for (final m in missiles) {
      m.life -= dt;
      if (m.target == null || !pirates.contains(m.target)) {
        Pirate? best;
        var bd = 900.0;
        for (final e in pirates) {
          final d = (e.pos - m.pos).distance;
          if (d < bd) {
            bd = d;
            best = e;
          }
        }
        m.target = best;
      }
      final t = m.target;
      if (t != null) {
        final desired = (t.pos - m.pos).normalized() * 620;
        m.vel += (desired - m.vel) * min(1, 4 * dt);
      }
      m.pos += m.vel * dt;
      if (_rng.nextDouble() < 0.8) {
        particles.add(Particle(m.pos, -m.vel * 0.1, 0.3, const Color(0xFFFFCC80), 2.5));
      }
      if (t != null && (t.pos - m.pos).distance < t.radius + 6) {
        _hitPirate(t, m.damage, m.pos);
        _burst(m.pos, const Color(0xFFFFAB40), 14);
        sfx.add(Sfx.explode);
        dead.add(m);
      } else if (m.life <= 0) {
        dead.add(m);
      }
    }
    missiles.removeWhere(dead.contains);
  }

  void _hitPirate(Pirate e, double dmg, Offset at) {
    e.hp -= dmg;
    e.hitFlash = 0.1;
    if (_rng.nextDouble() < 0.6) _float(at, dmg.round().toString(), const Color(0xFFFFF59D));
  }

  void _updateBullets(double dt) {
    final dead = <Bullet>{};
    for (final b in bullets) {
      b.pos += b.vel * dt;
      b.life -= dt;
      if (b.life <= 0) {
        dead.add(b);
        continue;
      }
      if (b.fromPlayer) {
        for (final e in pirates) {
          if ((e.pos - b.pos).distance < e.radius) {
            _hitPirate(e, b.damage, b.pos);
            dead.add(b);
            _spark(b.pos, const Color(0xFFFFF59D));
            sfx.add(Sfx.hit);
            break;
          }
        }
      } else {
        if (player.alive && (player.pos - b.pos).distance < (shielded ? 30 : 18)) {
          _damagePlayer(b.damage);
          dead.add(b);
          _spark(b.pos, const Color(0xFFFF8A80));
          continue;
        }
        for (final s in stations) {
          if ((s.pos - b.pos).distance < 60) {
            s.hp -= b.damage;
            dead.add(b);
            _spark(b.pos, const Color(0xFFFF8A80));
            break;
          }
        }
      }
      if (dead.contains(b)) continue;
      for (final a in asteroids) {
        if ((a.pos - b.pos).distance < a.radius) {
          if (b.fromPlayer) {
            a.hp -= b.damage;
            a.hitFlash = 0.08;
          }
          dead.add(b);
          _spark(b.pos, const Color(0xFFBCAAA4));
          break;
        }
      }
    }
    bullets.removeWhere(dead.contains);

    final killed = pirates.where((e) => e.hp <= 0).toList();
    for (final e in killed) {
      pirates.remove(e);
      _onKilled(e);
    }

    final destroyed = stations.where((s) => s.hp <= 0).toList();
    for (final s in destroyed) {
      if (s == stations.first) {
        s.hp = 1;
        continue;
      }
      stations.remove(s);
      _burst(s.pos, const Color(0xFFFF5252), 100);
      sfx.add(Sfx.bigExplode);
      say(Speaker.advisor, '${s.name}이(가) 파괴됐어요! 방어포탑이 필요해요!');
    }
  }

  void _onKilled(Pirate e) {
    final boss = e.kind == PirateKind.boss;
    _burst(e.pos, e.kind == PirateKind.jelly ? const Color(0xFFE040FB) : const Color(0xFFFF7043),
        boss ? 100 : 35);
    sfx.add(boss ? Sfx.bigExplode : Sfx.explode);
    shake = min(20, shake + (boss ? 16 : 3));
    final bounty = (e.bounty * sectorMul * (1 + crewBonus(CrewRole.trader)) *
            (e.name != null ? 4 : 1))
        .round();
    _dropPickups(e.pos, PickupKind.credits, bounty, boss ? 10 : 3);

    if (e.kind == PirateKind.jelly) {
      profile.addStat('jelly');
      _dropPickups(e.pos, PickupKind.ore, 30, 3);
      if (_rng.nextDouble() < 0.35) {
        pickups.add(Pickup(PickupKind.gem, e.pos, 1, OffsetX.fromAngle(_rng.nextDouble() * 6, 80)));
      }
      return;
    }

    _count('kills');
    profile.addStat('kills');
    for (final m in activeMissions) {
      if (m.type == MissionType.kill) m.progress++;
      if (m.type == MissionType.bounty && e.missionId == m.id) m.progress = 1;
    }

    if (_rng.nextDouble() < (boss ? 1 : 0.08)) {
      final pk = PowerUpKind.values[_rng.nextInt(PowerUpKind.values.length)];
      pickups.add(Pickup(PickupKind.power, e.pos, 1,
          OffsetX.fromAngle(_rng.nextDouble() * 6, 60), power: pk));
    }

    if (boss) {
      profile.addStat('bosses');
      _dropPickups(e.pos, PickupKind.ore, (120 * sectorMul).round(), 6);
      _dropPickups(e.pos, PickupKind.gem, 5, 5);
      if (e.sectorBoss) {
        bossDefeated = true;
        say(Speaker.pirate, '으아악! 이 섹터는… 네 것이다…');
        say(Speaker.advisor, '섹터 두목 격파! 워프 게이트가 열렸어요! 🌀');
      } else {
        say(Speaker.pirate, '으아악! 기억해 두겠다, 선장!');
      }
    } else if (e.name != null) {
      say(Speaker.captain, '현상수배범 ${e.name} 체포 완료!');
    } else if (_rng.nextDouble() < 0.12) {
      say(Speaker.captain, ['한 놈 처리!', '어딜 도망가!', '이 구역은 내 거야!', '다음!'][_rng.nextInt(4)]);
    }
  }

  void _updateAsteroids(double dt) {
    for (final a in asteroids) {
      a.rotation += a.spin * dt;
      a.hitFlash = max(0, a.hitFlash - dt);
      if (a.drift != Offset.zero) a.pos += a.drift * dt;
    }
    final broken = asteroids.where((a) => a.hp <= 0).toList();
    for (final a in broken) {
      asteroids.remove(a);
      _count('asteroids');
      sfx.add(Sfx.hit);
      _burst(a.pos, a.crystal ? const Color(0xFF4DD0E1) : const Color(0xFFA1887F), 20);
      _dropPickups(a.pos, PickupKind.ore, (a.radius / 3 * (a.crystal ? 3 : 1) * sectorMul).round(), 3);
      if (_rng.nextDouble() < 0.3) {
        _dropPickups(a.pos, PickupKind.credits, (10 * sectorMul).round(), 1);
      }
    }
    while (asteroids.length < maxAsteroids) {
      _spawnAsteroid(awayFrom: player.pos);
    }
  }

  void _dropPickups(Offset pos, PickupKind kind, int total, int pieces) {
    final each = max(1, total ~/ pieces);
    for (var i = 0; i < pieces; i++) {
      pickups.add(Pickup(kind, pos, each,
          OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, randRange(_rng, 40, 140))));
    }
  }

  void _updatePickups(double dt) {
    final magnet = buffs.containsKey(PowerUpKind.magnet) ? 450.0 : 170.0;
    for (final k in pickups) {
      k.life -= dt;
      final to = player.pos - k.pos;
      final d = to.distance;
      if (player.alive && d < magnet) {
        k.vel += to.normalized() * 1400 * dt;
      }
      k.vel = k.vel * pow(0.2, dt).toDouble();
      k.pos += k.vel * dt;
      if (player.alive && d < 24) {
        k.life = 0;
        _collect(k);
      }
    }
    pickups.removeWhere((k) => k.life <= 0);
  }

  void _collect(Pickup k) {
    switch (k.kind) {
      case PickupKind.credits:
        final n = k.amount * (buffs.containsKey(PowerUpKind.doubleCredits) ? 2 : 1);
        credits += n;
        sfx.add(Sfx.coin);
        _float(k.pos, '+$n', const Color(0xFFFFD54F));
      case PickupKind.ore:
        final n = (k.amount * (1 + crewBonus(CrewRole.miner))).round();
        ore += n;
        profile.addStat('ore', n);
        for (final m in activeMissions) {
          if (m.type == MissionType.mine) m.progress += n;
        }
        sfx.add(Sfx.pickup);
        _float(k.pos, '+$n💎', const Color(0xFF4DD0E1));
      case PickupKind.gem:
        profile.gems += k.amount;
        profile.dirty = true;
        sfx.add(Sfx.gem);
        _float(k.pos, '+${k.amount}⭐', const Color(0xFFFF80AB), big: true);
      case PickupKind.power:
        final pk = k.power!;
        buffs[pk] = pk.duration;
        sfx.add(Sfx.upgrade);
        _float(k.pos, '${pk.icon} ${pk.label}!', const Color(0xFFB9F6CA), big: true);
    }
  }

  void _updateParticles(double dt) {
    for (final p in particles) {
      p.life -= dt;
      p.pos += p.vel * dt;
      p.vel = p.vel * pow(0.1, dt).toDouble();
    }
    particles.removeWhere((p) => p.life <= 0);
    if (particles.length > 600) particles.removeRange(0, particles.length - 600);
  }

  // ---------- 이벤트 ----------
  void _updateEvents(double dt) {
    eventTimer -= dt;
    if (eventTimer <= 0 && player.alive) {
      eventTimer = randRange(_rng, 90, 150);
      if (events.length < 2) _startRandomEvent();
    }
    for (final ev in events) {
      ev.timeLeft -= dt;
      switch (ev.kind) {
        case EventKind.raid:
          final attackers = pirates.where((e) => e.eventId == ev.id).toList();
          final planet = ev.planet!;
          planet.raided = attackers.any((e) => (e.pos - planet.pos).distance < planet.radius + 450);
          if (attackers.isEmpty) {
            ev.finished = true;
            planet.raided = false;
            final reward = (200 * sectorMul).round();
            credits += reward;
            profile.gems += 2;
            sfx.add(Sfx.coin);
            say(Speaker.advisor, '${planet.name} 방어 성공! 주민들이 감사의 뜻으로 💰$reward ⭐2를 보냈어요.');
          } else if (ev.timeLeft <= 0) {
            ev.finished = true;
            planet.raided = false;
            pirates.removeWhere((e) => e.eventId == ev.id);
            if (planet.colonyLevel > 1) {
              planet.colonyLevel--;
              say(Speaker.advisor, '${planet.name}이(가) 약탈당해 Lv.${planet.colonyLevel}로 떨어졌어요… 😢');
            } else {
              say(Speaker.advisor, '해적들이 ${planet.name}을(를) 약탈하고 떠났어요.');
            }
          }
        case EventKind.supply:
          if (_supplyCapsule == null || !pickups.contains(_supplyCapsule)) {
            ev.finished = true;
            if (_supplyCapsule != null && _supplyCapsule!.life <= 0 && ev.timeLeft > 0) {
              say(Speaker.advisor, '보급 캡슐 회수 완료!');
            }
            _supplyCapsule = null;
          } else if (ev.timeLeft <= 0) {
            ev.finished = true;
            pickups.remove(_supplyCapsule);
            _supplyCapsule = null;
          }
        case EventKind.meteor:
        case EventKind.merchant:
          if (ev.timeLeft <= 0) {
            ev.finished = true;
            if (ev.kind == EventKind.merchant) {
              merchantCrew = null;
              say(Speaker.merchant, '그럼 다음에 또 봐요~ 냥!');
            }
          }
      }
    }
    events.removeWhere((e) => e.finished);
  }

  void _startRandomEvent() {
    final colonies = planets.where((p) => p.colonyLevel > 0).toList();
    final options = <EventKind>[
      EventKind.meteor,
      EventKind.supply,
      if (!events.any((e) => e.kind == EventKind.merchant)) EventKind.merchant,
      if (colonies.isNotEmpty && !events.any((e) => e.kind == EventKind.raid)) ...[
        EventKind.raid,
        EventKind.raid,
      ],
    ];
    startEvent(options[_rng.nextInt(options.length)]);
  }

  /// 테스트/디버그용으로도 사용
  WorldEvent? startEvent(EventKind kind) {
    final id = _nextId++;
    final away = player.pos + OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, randRange(_rng, 900, 1300));
    final pos = _clampWorld(away, (_) {});
    sfx.add(Sfx.alarm);
    switch (kind) {
      case EventKind.raid:
        final colonies = planets.where((p) => p.colonyLevel > 0).toList();
        if (colonies.isEmpty) return null;
        final planet = colonies[_rng.nextInt(colonies.length)];
        final ev = WorldEvent(id, kind, planet.pos, 150, planet: planet);
        events.add(ev);
        final n = 3 + threat.floor().clamp(0, 6);
        for (var i = 0; i < n; i++) {
          final k = _rng.nextDouble() < 0.3
              ? PirateKind.bomber
              : (_rng.nextBool() ? PirateKind.raider : PirateKind.scout);
          final e = _makePirate(k,
              planet.pos + OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, planet.radius + 500));
          e.eventId = id;
          pirates.add(e);
        }
        say(Speaker.advisor, '긴급! 해적이 ${planet.name}을(를) 습격하고 있어요! 생산이 멈췄어요!');
        say(Speaker.pirate, '이 식민지는 이제 우리 거다! 크하하!');
        return ev;
      case EventKind.meteor:
        final ev = WorldEvent(id, kind, pos, 60);
        events.add(ev);
        final drift = OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, 50);
        for (var i = 0; i < 22; i++) {
          final a = Asteroid(pos + OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, randRange(_rng, 0, 420)),
              randRange(_rng, 14, 26), _rng.nextInt(99999), crystal: true)
            ..drift = drift;
          asteroids.add(a);
        }
        say(Speaker.advisor, '유성우 발견! 크리스탈이 잔뜩 섞여 있어요. 광석 대박 기회!');
        return ev;
      case EventKind.merchant:
        final ev = WorldEvent(id, kind, pos, 120);
        events.add(ev);
        merchantCrew = CrewMember.random(_rng, _nextId++, odds: const {2: 70, 3: 30});
        merchantGemTrades = 0;
        say(Speaker.merchant, '떠돌이 상인 냥냥이 왔어요~ 좋은 물건 많다냥!');
        return ev;
      case EventKind.supply:
        final ev = WorldEvent(id, kind, pos, 120);
        events.add(ev);
        _supplyCapsule = Pickup(PickupKind.gem, pos, 5 + _rng.nextInt(6), Offset.zero)..life = 120;
        pickups.add(_supplyCapsule!);
        for (var i = 0; i < 2 + sector; i++) {
          pirates.add(_makePirate(PirateKind.raider,
              pos + OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, 200)));
        }
        say(Speaker.advisor, '젬이 든 보급 캡슐 신호가 잡혔어요! 해적이 지키고 있으니 조심하세요.');
        return ev;
    }
  }

  // 상인 거래
  int get merchantCrewPrice => (1500 * sectorMul).round();
  int get merchantGemPrice => (1000 * sectorMul).round();
  static const merchantPowerPrice = 150;

  bool buyMerchantCrew() {
    final c = merchantCrew;
    if (c == null || roster.length >= maxRoster) return false;
    if (!_pay((merchantCrewPrice, 0))) return false;
    merchantCrew = null;
    _addCrew(c);
    return true;
  }

  bool buyGemsFromMerchant() {
    if (merchantGemTrades >= 3) return false;
    if (!_pay((merchantGemPrice, 0))) return false;
    merchantGemTrades++;
    profile.gems += 5;
    profile.dirty = true;
    sfx.add(Sfx.gem);
    return true;
  }

  bool buyPowerUp(PowerUpKind k) {
    if (!_pay((merchantPowerPrice, 0))) return false;
    buffs[k] = k.duration * 2;
    sfx.add(Sfx.upgrade);
    return true;
  }

  // ---------- 스폰 ----------
  void _updateSpawning(double dt) {
    spawnTimer -= dt;
    jellyTimer -= dt;
    final t = threat;
    final normal = pirates.where((e) => e.isPirate && e.eventId == null && e.name == null).length;
    final maxPirates = min(18, (2 + (t - sector) * 1.5 + sector).floor());

    // 섹터 두목: 스토리 단계이거나 위협도가 충분히 오르면 등장
    final storyWantsBoss = story.key == 'sectorBoss' && storyTimer > 12;
    if (!bossDefeated &&
        !sectorBossSpawned &&
        player.alive &&
        (storyWantsBoss || t >= 1 + sector + 3)) {
      sectorBossSpawned = true;
      final e = _makePirate(PirateKind.boss, _spawnPos(), hpMul: 1.6)..sectorBoss = true;
      pirates.add(e);
      sfx.add(Sfx.alarm);
      say(Speaker.pirate, '$sectorName의 주인은 나다! 덤벼라, 꼬마 선장!');
      say(Speaker.advisor, '경고! 섹터 두목 함선이 접근 중입니다!');
    }
    // 두목이 사라졌으면(예: 다른 곳으로 이동) 다시 등장할 수 있게
    if (sectorBossSpawned && !bossDefeated && !pirates.any((e) => e.sectorBoss)) {
      sectorBossSpawned = false;
    }

    // 일반 두목: 섹터 두목 격파 후 위협도 3마다
    if (bossDefeated && t >= 1 + sector + (bossesSpawned + 1) * 3 && player.alive) {
      bossesSpawned++;
      pirates.add(_makePirate(PirateKind.boss, _spawnPos()));
      sfx.add(Sfx.alarm);
      say(Speaker.pirate, '복수하러 왔다! 각오해라!');
    }

    if (spawnTimer <= 0 && normal < maxPirates && player.alive) {
      spawnTimer = max(3.0, 13 - (t - sector) * 1.2);
      final group = 1 + _rng.nextInt(min(4, max(1, t.floor())));
      for (var i = 0; i < group; i++) {
        pirates.add(_makePirate(_randomKind(t), _spawnPos()));
      }
      if (_rng.nextDouble() < 0.3) {
        say(Speaker.pirate, ['크하하! 짐 내려놔!', '여긴 우리 해적단 구역이다!',
            '그 반짝이는 크레딧 내놔!', '오늘 운이 나쁘구나, 꼬마!'][_rng.nextInt(4)]);
      }
    }

    if (jellyTimer <= 0) {
      jellyTimer = 40;
      if (pirates.where((e) => e.kind == PirateKind.jelly).length < 3) {
        pirates.add(_makePirate(PirateKind.jelly, _spawnPos())
          ..wanderAngle = _rng.nextDouble() * 2 * pi);
      }
    }
  }

  PirateKind _randomKind(double t) {
    final r = _rng.nextDouble();
    if (t >= 2.5 && r < 0.15) return PirateKind.bomber;
    if (t >= 3.5 && r < 0.27) return PirateKind.sniper;
    if (r < min(0.55, 0.1 * t)) return PirateKind.raider;
    return PirateKind.scout;
  }

  Offset _spawnPos() => _clampWorld(
      player.pos + OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, randRange(_rng, 900, 1200)),
      (_) {});

  Pirate _makePirate(PirateKind kind, Offset pos, {double hpMul = 1}) {
    final scale = (1 + (threat - 1 - sector) * 0.15) * sectorMul * hpMul;
    return Pirate(kind, pos, Pirate.baseHp(kind) * scale, dmgScale: 1 + sector * 0.3)
      ..wanderAngle = _rng.nextDouble() * 2 * pi;
  }

  void _updateMissions(double dt) {
    offerTimer -= dt;
    if (offerTimer <= 0 || missionOffers.isEmpty) _refreshOffers();
    for (final m in [...activeMissions]) {
      if (m.type == MissionType.deliver) {
        final idx = m.planetIndex;
        if (idx != null && idx < planets.length &&
            (planets[idx].pos - player.pos).distance < planets[idx].radius + 140 &&
            player.alive) {
          m.progress = 1;
        }
      }
      if (m.type == MissionType.bounty && m.bountySpawned &&
          !m.done && !pirates.any((e) => e.missionId == m.id)) {
        _spawnBounty(m);
      }
      if (m.done) _completeMission(m);
    }
  }

  void _spark(Offset pos, Color c) {
    for (var i = 0; i < 4; i++) {
      particles.add(Particle(pos,
          OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, randRange(_rng, 60, 160)), 0.25, c, 2));
    }
  }

  void _burst(Offset pos, Color c, int n) {
    for (var i = 0; i < n; i++) {
      particles.add(Particle(
          pos,
          OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, randRange(_rng, 40, 320)),
          randRange(_rng, 0.4, 1.0),
          i.isEven ? c : const Color(0xFFFFF176),
          randRange(_rng, 2, 5)));
    }
  }

  // ---------- 저장/불러오기 ----------
  static Map<String, dynamic> _stationToJson(Station s) => {
        'name': s.name,
        'x': s.pos.dx,
        'y': s.pos.dy,
        'hab': s.habitatLevel,
        'tur': s.turretLevel,
      };

  static Station _stationFromJson(Map<String, dynamic> s) {
    final st = Station(s['name'] as String,
        Offset((s['x'] as num).toDouble(), (s['y'] as num).toDouble()))
      ..habitatLevel = s['hab'] as int
      ..turretLevel = s['tur'] as int;
    st.hp = st.maxHp;
    return st;
  }

  Map<String, dynamic> toJson() => {
        'v': 2,
        'seed': seed,
        'credits': credits,
        'ore': ore,
        'levels': {for (final e in levels.entries) e.key.name: e.value},
        'counters': counters,
        'sector': sector,
        'current': _saveCurrentSector().toJson(),
        'sectors': {for (final e in sectors.entries) '${e.key}': e.value.toJson()},
        'roster': roster.map((c) => c.toJson()).toList(),
        'recruits': recruitCount,
        'nextId': _nextId,
        'missions': activeMissions.map((m) => m.toJson()).toList(),
        'story': storyIndex,
        'storyBase': storyBase,
        'total': totalTime,
        'px': player.pos.dx,
        'py': player.pos.dy,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };

  static GameWorld fromJson(Map<String, dynamic> j, Profile profile) {
    final w = GameWorld(seed: j['seed'] as int, profile: profile);
    w.dialogs.clear();
    w.credits = (j['credits'] as num).toDouble();
    w.ore = (j['ore'] as num).toDouble();
    (j['levels'] as Map).forEach((k, v) {
      final kind = UpgradeKind.values.where((u) => u.name == k).firstOrNull;
      if (kind != null) w.levels[kind] = v as int;
    });
    (j['counters'] as Map).forEach((k, v) => w.counters[k as String] = v as int);
    (j['sectors'] as Map).forEach((k, v) =>
        w.sectors[int.parse(k as String)] = SectorSave.fromJson(v as Map<String, dynamic>));
    w._loadSector(j['sector'] as int, SectorSave.fromJson(j['current'] as Map<String, dynamic>));
    for (final c in (j['roster'] as List).cast<Map<String, dynamic>>()) {
      w.roster.add(CrewMember.fromJson(c));
    }
    w.recruitCount = j['recruits'] as int;
    w._nextId = j['nextId'] as int;
    for (final m in (j['missions'] as List).cast<Map<String, dynamic>>()) {
      final mission = Mission.fromJson(m);
      w.activeMissions.add(mission);
      if (mission.type == MissionType.bounty) w._spawnBounty(mission);
    }
    w.storyIndex = j['story'] as int;
    w.storyBase = j['storyBase'] as int;
    w.totalTime = (j['total'] as num).toDouble();
    w.player.pos = Offset((j['px'] as num).toDouble(), (j['py'] as num).toDouble());
    w.player.hp = w.playerMaxHp;
    w.savedAt = DateTime.fromMillisecondsSinceEpoch(j['savedAt'] as int);
    w.say(Speaker.advisor, '다시 오신 걸 환영해요, 선장님! 현재 목표: ${w.story.title}');
    return w;
  }
}
