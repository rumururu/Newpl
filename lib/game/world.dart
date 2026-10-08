import 'dart:math';
import 'dart:ui';

import 'models.dart';

class InputState {
  Offset move = Offset.zero; // 길이 0..1
  bool fire = false;
}

enum UpgradeKind { weapon, hull, engine }

/// 게임 전체 상태와 규칙. 렌더링/위젯과 분리되어 있어 테스트 가능.
class GameWorld {
  GameWorld({int? seed}) : seed = seed ?? Random().nextInt(1 << 30) {
    _rng = Random(this.seed);
    _generate();
  }

  static const double worldHalf = 4000;
  static const int maxAsteroids = 110;

  final int seed;
  late Random _rng;

  final player = PlayerShip();
  final pirates = <Pirate>[];
  final bullets = <Bullet>[];
  final asteroids = <Asteroid>[];
  final pickups = <Pickup>[];
  final particles = <Particle>[];
  final planets = <Planet>[];
  final stations = <Station>[];
  final dialogs = <DialogLine>[];

  double credits = 120;
  double ore = 20;
  int weaponLevel = 0;
  int hullLevel = 0;
  int engineLevel = 0;
  int kills = 0;
  double elapsed = 0;
  double spawnTimer = 8;
  int bossesSpawned = 0;
  bool paused = false;

  // ---------- 파생 스탯 ----------
  double get playerMaxHp => 100 + hullLevel * 40.0;
  double get playerSpeed => 260 + engineLevel * 40.0;
  double get playerDamage => 10 + weaponLevel * 5.0;
  double get playerFireInterval => 0.25 * pow(0.9, weaponLevel);
  int get playerShots => weaponLevel >= 6 ? 3 : (weaponLevel >= 3 ? 2 : 1);

  int get colonyCount => planets.where((p) => p.colonyLevel > 0).length;

  double get threat =>
      1 +
      elapsed / 90 +
      colonyCount * 0.3 +
      stations.fold<int>(0, (s, st) => s + st.habitatLevel - 1) * 0.15;

  double get creditIncome =>
      planets.fold(0.0, (s, p) => s + p.creditRate) +
      stations.fold(0.0, (s, st) => s + st.creditRate);
  double get oreIncome => planets.fold(0.0, (s, p) => s + p.oreRate);

  /// 제국 가치 (진행도 점수)
  int get empireValue =>
      planets.fold<int>(0, (s, p) => s + p.colonyLevel * 100) +
      stations.fold<int>(
          0, (s, st) => s + (st.habitatLevel + st.turretLevel) * 120) +
      (weaponLevel + hullLevel + engineLevel) * 80 +
      kills * 5;

  static int upgradeMax = 8;

  int levelOf(UpgradeKind k) => switch (k) {
        UpgradeKind.weapon => weaponLevel,
        UpgradeKind.hull => hullLevel,
        UpgradeKind.engine => engineLevel,
      };

  (int, int) upgradeCost(UpgradeKind k) {
    final lv = levelOf(k);
    return ((100 * pow(1.6, lv)).round(), 30 * lv);
  }

  (int, int) get stationBuildCost => (400 + stations.length * 200, 150);

  // ---------- 월드 생성 ----------
  static const _planetNames = [
    '테라노바', '아쿠아리스', '루비아', '프로스타', '볼카노',
    '젤리오', '솔라리스', '모모별', '네뷸라', '카시오페',
    '오로라', '두리안',
  ];

  void _generate() {
    final kinds = PlanetKind.values;
    // 첫 행성은 시작 지점 근처의 정원 행성
    planets.add(Planet(_planetNames[0], const Offset(900, -350), 110,
        PlanetKind.garden));
    var tries = 0;
    while (planets.length < 11 && tries < 2000) {
      tries++;
      final pos = Offset(randRange(_rng, -worldHalf + 400, worldHalf - 400),
          randRange(_rng, -worldHalf + 400, worldHalf - 400));
      if (pos.distance < 700) continue;
      if (planets.any((p) => (p.pos - pos).distance < 1100)) continue;
      final kind = kinds[_rng.nextInt(kinds.length)];
      final radius = kind == PlanetKind.gas
          ? randRange(_rng, 150, 200)
          : randRange(_rng, 90, 140);
      planets.add(Planet(_planetNames[planets.length], pos, radius, kind));
    }
    stations.add(Station('헤이븐 기지', Offset.zero)..hp = 300);
    player.pos = const Offset(0, 160);
    player.hp = playerMaxHp;
    for (var i = 0; i < maxAsteroids; i++) {
      _spawnAsteroid(awayFrom: Offset.zero, minDist: 500);
    }
    say(Speaker.advisor, '선장님, 환영합니다! 헤이븐 기지에서 출발하세요.');
    say(Speaker.captain, '좋아, 우주를 개척해 보자고!');
  }

  void _spawnAsteroid({required Offset awayFrom, double minDist = 900}) {
    for (var t = 0; t < 50; t++) {
      final pos = Offset(randRange(_rng, -worldHalf, worldHalf),
          randRange(_rng, -worldHalf, worldHalf));
      if ((pos - awayFrom).distance < minDist) continue;
      if (planets.any((p) => (p.pos - pos).distance < p.radius + 120)) continue;
      if (stations.any((s) => (s.pos - pos).distance < 250)) continue;
      asteroids.add(Asteroid(pos, randRange(_rng, 18, 55), _rng.nextInt(99999)));
      return;
    }
  }

  void say(Speaker s, String text) {
    // 같은 대사가 연속으로 쌓이지 않게
    if (dialogs.isNotEmpty && dialogs.last.text == text) return;
    dialogs.add(DialogLine(s, text));
    if (dialogs.length > 4) dialogs.removeAt(0);
  }

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

  bool get canBuildStationHere =>
      player.alive &&
      nearbyStation == null &&
      planets.every((p) => (p.pos - player.pos).distance > p.radius + 300) &&
      stations.every((s) => (s.pos - player.pos).distance > 900);

  bool canAfford((int, int) cost) => credits >= cost.$1 && ore >= cost.$2;

  bool _pay((int, int) cost) {
    if (!canAfford(cost)) return false;
    credits -= cost.$1;
    ore -= cost.$2;
    return true;
  }

  bool upgradePlanet(Planet p) {
    if (p.colonyLevel >= Planet.maxLevel) return false;
    if (!_pay(p.nextCost)) return false;
    p.colonyLevel++;
    if (p.colonyLevel == 1) {
      say(Speaker.captain, '${p.name}에 깃발을 꽂았다! 정착 완료!');
    } else {
      say(Speaker.advisor, '${p.name} 식민지가 Lv.${p.colonyLevel}로 성장했어요.');
    }
    _burst(p.pos + Offset(0, -p.radius), const Color(0xFF7CFFB2), 30);
    return true;
  }

  bool buildStation() {
    if (!canBuildStationHere) return false;
    if (!_pay(stationBuildCost)) return false;
    final st = Station('정거장 ${stations.length + 1}호', player.pos + const Offset(0, -140));
    st.hp = st.maxHp;
    stations.add(st);
    say(Speaker.advisor, '${st.name} 건설 완료! 수입이 늘어납니다.');
    _burst(st.pos, const Color(0xFF8AD8FF), 40);
    return true;
  }

  bool upgradeHabitat(Station s) {
    if (s.habitatLevel >= Station.maxLevel) return false;
    if (!_pay(s.habitatCost)) return false;
    s.habitatLevel++;
    s.hp = s.maxHp;
    say(Speaker.advisor, '${s.name} 거주구역 Lv.${s.habitatLevel}!');
    return true;
  }

  bool upgradeTurret(Station s) {
    if (s.turretLevel >= Station.maxLevel) return false;
    if (!_pay(s.turretCost)) return false;
    s.turretLevel++;
    say(Speaker.advisor, '${s.name} 방어포탑 Lv.${s.turretLevel}!');
    return true;
  }

  bool upgradeShip(UpgradeKind k) {
    if (levelOf(k) >= upgradeMax) return false;
    if (!_pay(upgradeCost(k))) return false;
    switch (k) {
      case UpgradeKind.weapon:
        weaponLevel++;
        say(Speaker.captain, '무기 강화! 해적들 각오해라!');
      case UpgradeKind.hull:
        hullLevel++;
        player.hp = playerMaxHp;
        say(Speaker.captain, '장갑 강화! 이제 좀 든든하군.');
      case UpgradeKind.engine:
        engineLevel++;
        say(Speaker.captain, '엔진 강화! 더 빠르게!');
    }
    return true;
  }

  // ---------- 업데이트 ----------
  void update(double dt, InputState input) {
    if (paused) return;
    dt = dt.clamp(0, 0.05);
    elapsed += dt;

    credits += creditIncome * dt;
    ore += oreIncome * dt;

    _updatePlayer(dt, input);
    _updatePirates(dt);
    _updateStations(dt);
    _updateBullets(dt);
    _updateAsteroids(dt);
    _updatePickups(dt);
    _updateParticles(dt);
    _updateSpawning(dt);

    for (final d in dialogs) {
      d.time -= dt;
    }
    dialogs.removeWhere((d) => d.time <= 0);
  }

  void _updatePlayer(double dt, InputState input) {
    final p = player;
    if (!p.alive) {
      p.respawnTimer -= dt;
      if (p.respawnTimer <= 0) _respawn();
      return;
    }
    p.invulnerable = max(0, p.invulnerable - dt);
    final move = input.move.clampLength(1);
    p.thrusting = move.distance > 0.1;
    if (p.thrusting) {
      final target = atan2(move.dy, move.dx);
      p.angle += angleDiff(p.angle, target).clamp(-8 * dt, 8 * dt);
      final accel = OffsetX.fromAngle(p.angle, 900 * move.distance);
      p.vel += accel * dt;
    }
    p.vel = (p.vel * pow(0.35, dt).toDouble()).clampLength(playerSpeed);
    p.pos += p.vel * dt;
    p.pos = _clampWorld(p.pos, (v) => p.vel = v);

    if (p.thrusting && _rng.nextDouble() < 0.7) {
      final back = p.pos - OffsetX.fromAngle(p.angle, 20);
      particles.add(Particle(
        back,
        -OffsetX.fromAngle(p.angle + randRange(_rng, -0.3, 0.3), 120) + p.vel * 0.3,
        0.35,
        const Color(0xFFFFB347),
        randRange(_rng, 2, 4),
      ));
    }

    // 소행성 충돌: 밀어내기
    for (final a in asteroids) {
      final d = p.pos - a.pos;
      final minD = a.radius + 16;
      if (d.distance < minD && d.distance > 0) {
        final n = d.normalized();
        p.pos = a.pos + n * minD;
        p.vel = p.vel - n * (2 * (p.vel.dx * n.dx + p.vel.dy * n.dy)) * 0.6;
      }
    }

    // 정거장 근처: 수리
    if (nearbyStation != null && p.hp < playerMaxHp) {
      p.hp = min(playerMaxHp, p.hp + 20 * dt);
    }

    p.fireCooldown -= dt;
    if (input.fire && p.fireCooldown <= 0) {
      p.fireCooldown = playerFireInterval;
      final shots = playerShots;
      for (var i = 0; i < shots; i++) {
        final spread = shots == 1 ? 0.0 : (i - (shots - 1) / 2) * 0.12;
        final dir = OffsetX.fromAngle(p.angle + spread);
        bullets.add(Bullet(p.pos + dir * 22, dir * 760 + p.vel * 0.5,
            playerDamage, true));
      }
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

  void _respawn() {
    final p = player;
    final home = stations.isEmpty
        ? Offset.zero
        : stations
            .reduce((a, b) =>
                (a.pos - p.pos).distance < (b.pos - p.pos).distance ? a : b)
            .pos;
    p
      ..alive = true
      ..pos = home + const Offset(0, 160)
      ..vel = Offset.zero
      ..hp = playerMaxHp
      ..invulnerable = 3;
    say(Speaker.advisor, '선장님 무사하시군요! 새 함선을 준비했어요.');
  }

  void _damagePlayer(double dmg) {
    final p = player;
    if (!p.alive || p.invulnerable > 0) return;
    p.hp -= dmg;
    if (p.hp <= 0) {
      p.alive = false;
      p.respawnTimer = 3;
      final lost = (credits * 0.25).floor();
      credits -= lost;
      _burst(p.pos, const Color(0xFFFF7043), 60);
      say(Speaker.pirate, '크하하! 크레딧 $lost 잘 받아간다!');
    }
  }

  void _updatePirates(double dt) {
    for (final e in pirates) {
      e.hitFlash = max(0, e.hitFlash - dt);
      // 목표 선택: 플레이어 또는 가까운 정거장
      Offset? target;
      double targetDist = double.infinity;
      if (player.alive) {
        target = player.pos;
        targetDist = (player.pos - e.pos).distance;
      }
      for (final s in stations) {
        final d = (s.pos - e.pos).distance;
        if (d < 900 && d < targetDist) {
          target = s.pos;
          targetDist = d;
        }
      }

      Offset desired;
      if (target == null || targetDist > 1600) {
        e.wanderAngle += randRange(_rng, -1, 1) * dt;
        desired = OffsetX.fromAngle(e.wanderAngle, e.speed * 0.4);
      } else {
        final to = (target - e.pos).normalized();
        if (targetDist > 260) {
          desired = to * e.speed;
        } else {
          // 근접 시 선회
          desired = Offset(-to.dy, to.dx) * e.speed * 0.8 + to * -40;
        }
      }
      e.vel += (desired - e.vel) * min(1, 2.5 * dt);
      e.pos += e.vel * dt;
      e.pos = _clampWorld(e.pos, (v) => e.vel = v);

      if (target != null) {
        final aim = atan2(target.dy - e.pos.dy, target.dx - e.pos.dx);
        e.angle += angleDiff(e.angle, aim).clamp(-4 * dt, 4 * dt);
        e.fireCooldown -= dt;
        if (targetDist < 560 &&
            e.fireCooldown <= 0 &&
            angleDiff(e.angle, aim).abs() < 0.35) {
          e.fireCooldown = e.fireInterval * randRange(_rng, 0.8, 1.3);
          final shots = e.kind == PirateKind.boss ? 3 : 1;
          for (var i = 0; i < shots; i++) {
            final dir = OffsetX.fromAngle(e.angle + (i - (shots - 1) / 2) * 0.2);
            bullets.add(Bullet(e.pos + dir * e.radius, dir * 430, e.damage, false,
                life: 1.6));
          }
        }
      }
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
        final d = (e.pos - s.pos).distance;
        if (d < bestD) {
          bestD = d;
          best = e;
        }
      }
      if (best != null) {
        s.turretCooldown = s.turretInterval;
        final dir = (best.pos - s.pos).normalized();
        bullets.add(Bullet(s.pos + dir * 50, dir * 700, s.turretDamage, true));
      }
    }
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
            e.hp -= b.damage;
            e.hitFlash = 0.1;
            dead.add(b);
            _spark(b.pos, const Color(0xFFFFF59D));
            break;
          }
        }
      } else {
        if (player.alive && (player.pos - b.pos).distance < 18) {
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

    // 해적 격추
    final killed = pirates.where((e) => e.hp <= 0).toList();
    for (final e in killed) {
      pirates.remove(e);
      kills++;
      _burst(e.pos, const Color(0xFFFF7043), e.kind == PirateKind.boss ? 90 : 35);
      final bounty = (e.bounty * (1 + (threat - 1) * 0.1)).round();
      _dropPickups(e.pos, PickupKind.credits, bounty, e.kind == PirateKind.boss ? 10 : 3);
      if (e.kind == PirateKind.boss) {
        _dropPickups(e.pos, PickupKind.ore, 120, 6);
        say(Speaker.pirate, '으아악! 기억해 두겠다, 선장!');
        say(Speaker.captain, '두목을 해치웠다! 은하계가 조금 더 평화로워졌어.');
      } else if (_rng.nextDouble() < 0.15) {
        say(Speaker.captain, ['한 놈 처리!', '어딜 도망가!', '이 구역은 내 거야!'][_rng.nextInt(3)]);
      }
    }

    // 정거장 파괴 (기지 하나는 남김)
    final destroyed = stations.where((s) => s.hp <= 0).toList();
    for (final s in destroyed) {
      if (stations.length == 1) {
        s.hp = 1;
        continue;
      }
      stations.remove(s);
      _burst(s.pos, const Color(0xFFFF5252), 100);
      say(Speaker.advisor, '${s.name}이(가) 파괴됐어요! 방어포탑이 필요해요!');
    }
  }

  void _updateAsteroids(double dt) {
    for (final a in asteroids) {
      a.rotation += a.spin * dt;
      a.hitFlash = max(0, a.hitFlash - dt);
    }
    final broken = asteroids.where((a) => a.hp <= 0).toList();
    for (final a in broken) {
      asteroids.remove(a);
      _burst(a.pos, const Color(0xFFA1887F), 20);
      _dropPickups(a.pos, PickupKind.ore, (a.radius / 3).round(), 3);
      if (_rng.nextDouble() < 0.3) {
        _dropPickups(a.pos, PickupKind.credits, 10, 1);
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
    for (final k in pickups) {
      k.life -= dt;
      final to = player.pos - k.pos;
      final d = to.distance;
      if (player.alive && d < 170) {
        k.vel += to.normalized() * 1400 * dt;
      }
      k.vel = k.vel * pow(0.2, dt).toDouble();
      k.pos += k.vel * dt;
      if (player.alive && d < 22) {
        k.life = 0;
        if (k.kind == PickupKind.credits) {
          credits += k.amount;
        } else {
          ore += k.amount;
        }
      }
    }
    pickups.removeWhere((k) => k.life <= 0);
  }

  void _updateParticles(double dt) {
    for (final p in particles) {
      p.life -= dt;
      p.pos += p.vel * dt;
      p.vel = p.vel * pow(0.1, dt).toDouble();
    }
    particles.removeWhere((p) => p.life <= 0);
    if (particles.length > 500) particles.removeRange(0, particles.length - 500);
  }

  void _updateSpawning(double dt) {
    spawnTimer -= dt;
    final t = threat;
    final maxPirates = min(18, (2 + t * 1.5).floor());

    // 위협도 3, 6, 9... 마다 두목 등장
    if (t >= (bossesSpawned + 1) * 3 && player.alive) {
      bossesSpawned++;
      _spawnPirate(PirateKind.boss);
      say(Speaker.pirate, '내 구역에서 장사를 해? 각오해라, 꼬마 선장!');
      say(Speaker.advisor, '경고! 해적 두목 함선이 접근 중입니다!');
    }

    if (spawnTimer <= 0 && pirates.length < maxPirates && player.alive) {
      spawnTimer = max(3.0, 13 - t * 1.2);
      final group = 1 + _rng.nextInt(min(4, t.floor()));
      for (var i = 0; i < group; i++) {
        _spawnPirate(_rng.nextDouble() < min(0.5, 0.1 * t)
            ? PirateKind.raider
            : PirateKind.scout);
      }
      if (_rng.nextDouble() < 0.35) {
        say(Speaker.pirate, ['크하하! 짐 내려놔!', '여긴 우리 해적단 구역이다!',
            '그 반짝이는 크레딧 내놔!'][_rng.nextInt(3)]);
      }
    }
  }

  void _spawnPirate(PirateKind kind) {
    final a = _rng.nextDouble() * 2 * pi;
    final pos = _clampWorld(
        player.pos + OffsetX.fromAngle(a, randRange(_rng, 900, 1200)), (_) {});
    final scale = 1 + (threat - 1) * 0.15;
    final baseHp = switch (kind) {
      PirateKind.scout => 30.0,
      PirateKind.raider => 70.0,
      PirateKind.boss => 450.0,
    };
    pirates.add(Pirate(kind, pos, baseHp * scale)..wanderAngle = a + pi);
  }

  void _spark(Offset pos, Color c) {
    for (var i = 0; i < 4; i++) {
      particles.add(Particle(pos,
          OffsetX.fromAngle(_rng.nextDouble() * 2 * pi, randRange(_rng, 60, 160)),
          0.25, c, 2));
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
  Map<String, dynamic> toJson() => {
        'v': 1,
        'seed': seed,
        'credits': credits,
        'ore': ore,
        'weapon': weaponLevel,
        'hull': hullLevel,
        'engine': engineLevel,
        'kills': kills,
        'elapsed': elapsed,
        'bosses': bossesSpawned,
        'px': player.pos.dx,
        'py': player.pos.dy,
        'planets': planets.map((p) => p.colonyLevel).toList(),
        'stations': stations
            .map((s) => {
                  'name': s.name,
                  'x': s.pos.dx,
                  'y': s.pos.dy,
                  'hab': s.habitatLevel,
                  'tur': s.turretLevel,
                })
            .toList(),
      };

  static GameWorld fromJson(Map<String, dynamic> j) {
    final w = GameWorld(seed: j['seed'] as int);
    w.dialogs.clear();
    w.credits = (j['credits'] as num).toDouble();
    w.ore = (j['ore'] as num).toDouble();
    w.weaponLevel = j['weapon'] as int;
    w.hullLevel = j['hull'] as int;
    w.engineLevel = j['engine'] as int;
    w.kills = j['kills'] as int;
    w.elapsed = (j['elapsed'] as num).toDouble();
    w.bossesSpawned = j['bosses'] as int;
    w.player.pos = Offset((j['px'] as num).toDouble(), (j['py'] as num).toDouble());
    w.player.hp = w.playerMaxHp;
    final levels = (j['planets'] as List).cast<int>();
    for (var i = 0; i < levels.length && i < w.planets.length; i++) {
      w.planets[i].colonyLevel = levels[i];
    }
    w.stations.clear();
    for (final s in (j['stations'] as List).cast<Map<String, dynamic>>()) {
      final st = Station(s['name'] as String,
          Offset((s['x'] as num).toDouble(), (s['y'] as num).toDouble()))
        ..habitatLevel = s['hab'] as int
        ..turretLevel = s['tur'] as int;
      st.hp = st.maxHp;
      w.stations.add(st);
    }
    w.say(Speaker.advisor, '다시 오신 걸 환영해요, 선장님!');
    return w;
  }
}
