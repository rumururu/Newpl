import 'dart:math';
import 'dart:ui';

extension OffsetX on Offset {
  Offset normalized() {
    final d = distance;
    return d == 0 ? Offset.zero : this / d;
  }

  Offset clampLength(double max) {
    final d = distance;
    return d > max ? this * (max / d) : this;
  }

  static Offset fromAngle(double a, [double len = 1]) =>
      Offset(cos(a) * len, sin(a) * len);
}

double randRange(Random r, double a, double b) => a + r.nextDouble() * (b - a);

/// 각도 차이를 -pi..pi 로 정규화
double angleDiff(double a, double b) {
  var d = (b - a) % (2 * pi);
  if (d > pi) d -= 2 * pi;
  if (d < -pi) d += 2 * pi;
  return d;
}

typedef Cost = (int credits, int ore);

class PlayerShip {
  Offset pos = Offset.zero;
  Offset vel = Offset.zero;
  double angle = -pi / 2;
  double hp = 100;
  double fireCooldown = 0;
  double invulnerable = 0;
  bool thrusting = false;
  bool alive = true;

  /// 격추 후 부활 방식 선택 대기 중
  bool awaitingRevive = false;
  double deadTime = 0;
  Offset deathPos = Offset.zero;

  double missileCooldown = 0;
  double shieldCooldown = 0;
  double boostCooldown = 0;
  double shieldTime = 0;
}

enum PirateKind { scout, raider, bomber, sniper, boss, jelly }

class Pirate {
  Pirate(this.kind, this.pos, this.hp, {this.name, this.dmgScale = 1})
      : maxHp = hp;

  final PirateKind kind;
  Offset pos;
  Offset vel = Offset.zero;
  double angle = 0;
  double hp;
  final double maxHp;
  final double dmgScale;
  double fireCooldown = 1.5;
  double wanderAngle = 0;
  double hitFlash = 0;
  double contactCooldown = 0;

  /// 현상수배범 / 섹터 두목 이름
  final String? name;
  bool sectorBoss = false;

  /// 두목 패턴: 체력 절반 이하 2페이즈, 특수 공격 타이머
  bool enraged = false;
  double specialTimer = 5;
  int? missionId;
  int? eventId;

  bool get isPirate => kind != PirateKind.jelly;
  bool get isBossLike => kind == PirateKind.boss;

  double get radius => switch (kind) {
        PirateKind.scout => 18,
        PirateKind.raider => 24,
        PirateKind.bomber => 20,
        PirateKind.sniper => 20,
        PirateKind.boss => 46,
        PirateKind.jelly => 34,
      } *
      (name != null && kind != PirateKind.boss ? 1.3 : 1);

  double get speed => switch (kind) {
        PirateKind.scout => 290,
        PirateKind.raider => 210,
        PirateKind.bomber => 330,
        PirateKind.sniper => 190,
        PirateKind.boss => 150,
        PirateKind.jelly => 60,
      };

  double get damage =>
      dmgScale *
      switch (kind) {
        PirateKind.scout => 6,
        PirateKind.raider => 10,
        PirateKind.bomber => 34,
        PirateKind.sniper => 22,
        PirateKind.boss => 16,
        PirateKind.jelly => 9,
      };

  double get fireInterval => switch (kind) {
        PirateKind.scout => 1.1,
        PirateKind.raider => 1.4,
        PirateKind.bomber => 99,
        PirateKind.sniper => 2.6,
        PirateKind.boss => 0.9,
        PirateKind.jelly => 99,
      };

  int get bounty => switch (kind) {
        PirateKind.scout => 25,
        PirateKind.raider => 50,
        PirateKind.bomber => 40,
        PirateKind.sniper => 60,
        PirateKind.boss => 400,
        PirateKind.jelly => 30,
      };

  static double baseHp(PirateKind k) => switch (k) {
        PirateKind.scout => 30,
        PirateKind.raider => 70,
        PirateKind.bomber => 35,
        PirateKind.sniper => 45,
        PirateKind.boss => 450,
        PirateKind.jelly => 120,
      };
}

class Bullet {
  Bullet(this.pos, this.vel, this.damage, this.fromPlayer,
      {this.life = 1.2, this.big = false});
  Offset pos;
  final Offset vel;
  final double damage;
  final bool fromPlayer;
  final bool big;
  double life;
}

class Missile {
  Missile(this.pos, this.vel, this.damage);
  Offset pos;
  Offset vel;
  final double damage;
  double life = 3.5;
  Pirate? target;
}

class Asteroid {
  Asteroid(this.pos, this.radius, int seed, {this.crystal = false})
      : hp = radius * 1.5,
        rotation = 0,
        spin = (Random(seed).nextDouble() - 0.5) * 0.8,
        shape = List.generate(
            9, (i) => 0.75 + Random(seed + i * 31).nextDouble() * 0.35);
  Offset pos;
  Offset drift = Offset.zero;
  final double radius;
  final bool crystal;
  double hp;
  double rotation;
  final double spin;
  final List<double> shape;
  double hitFlash = 0;
}

enum PickupKind { credits, ore, gem, power }

enum PowerUpKind { rapid, shield, magnet, doubleCredits }

extension PowerUpInfo on PowerUpKind {
  String get icon => switch (this) {
        PowerUpKind.rapid => '⚡',
        PowerUpKind.shield => '🛡',
        PowerUpKind.magnet => '🧲',
        PowerUpKind.doubleCredits => '💰',
      };
  String get label => switch (this) {
        PowerUpKind.rapid => '연사',
        PowerUpKind.shield => '실드',
        PowerUpKind.magnet => '자석',
        PowerUpKind.doubleCredits => '크레딧 2배',
      };
  double get duration => switch (this) {
        PowerUpKind.rapid => 8,
        PowerUpKind.shield => 6,
        PowerUpKind.magnet => 15,
        PowerUpKind.doubleCredits => 20,
      };
}

class Pickup {
  Pickup(this.kind, this.pos, this.amount, this.vel, {this.power});
  final PickupKind kind;
  final PowerUpKind? power;
  Offset pos;
  Offset vel;
  final int amount;
  double life = 25;
}

class Particle {
  Particle(this.pos, this.vel, this.life, this.color, this.size)
      : maxLife = life;
  Offset pos;
  Offset vel;
  double life;
  final double maxLife;
  final Color color;
  final double size;
}

class FloatText {
  FloatText(this.pos, this.text, this.color, {this.big = false});
  Offset pos;
  final String text;
  final Color color;
  final bool big;
  double life = 1.0;
}

enum PlanetKind { garden, desert, ice, lava, gas }

class Planet {
  Planet(this.name, this.pos, this.radius, this.kind);
  final String name;
  final Offset pos;
  final double radius;
  final PlanetKind kind;
  int colonyLevel = 0;

  /// 해적 습격 중이면 생산 중단
  bool raided = false;

  static const maxLevel = 5;

  String get kindLabel => switch (kind) {
        PlanetKind.garden => '정원 행성',
        PlanetKind.desert => '사막 행성',
        PlanetKind.ice => '얼음 행성',
        PlanetKind.lava => '용암 행성',
        PlanetKind.gas => '가스 행성',
      };

  /// 레벨당 초당 생산량
  (double credits, double ore) get ratePerLevel => switch (kind) {
        PlanetKind.garden => (3.0, 0.0),
        PlanetKind.desert => (2.0, 0.6),
        PlanetKind.ice => (1.5, 1.0),
        PlanetKind.lava => (0.5, 2.0),
        PlanetKind.gas => (4.0, 0.0),
      };

  Cost baseCost() {
    final base = kind == PlanetKind.gas ? 220 : 150;
    return (
      (base * pow(1.8, colonyLevel)).round(),
      colonyLevel == 0 ? 0 : 40 * colonyLevel,
    );
  }
}

class Station {
  Station(this.name, this.pos);
  final String name;
  final Offset pos;
  int habitatLevel = 1;
  int turretLevel = 0;
  double hp = 300;
  double turretCooldown = 0;
  double spin = 0;

  static const maxLevel = 6;
  double get maxHp => 200 + habitatLevel * 100;
  double get baseCreditRate => habitatLevel * 2.0;
  double get turretRange => 380 + turretLevel * 30;
  double get turretDamage => 6 + turretLevel * 4;
  double get turretInterval => 0.9 / (1 + turretLevel * 0.2);

  Cost get habitatCost =>
      ((250 * pow(1.7, habitatLevel - 1)).round(), 60 * habitatLevel);
  Cost get turretCost =>
      ((200 * pow(1.7, turretLevel)).round(), 80 * (turretLevel + 1));
}

class WarpGate {
  WarpGate(this.pos, this.forward);
  final Offset pos;
  final bool forward;
}

enum EventKind { raid, meteor, merchant, supply }

class WorldEvent {
  WorldEvent(this.id, this.kind, this.pos, this.timeLeft, {this.planet});
  final int id;
  final EventKind kind;
  Offset pos;
  double timeLeft;
  final Planet? planet;
  bool finished = false;

  String get title => switch (kind) {
        EventKind.raid => '🏴‍☠️ ${planet?.name ?? ''} 습격',
        EventKind.meteor => '☄ 유성우',
        EventKind.merchant => '🛒 떠돌이 상인',
        EventKind.supply => '📦 보급 캡슐',
      };
}

enum Speaker { captain, pirate, advisor, merchant }

class DialogLine {
  DialogLine(this.speaker, this.text);
  final Speaker speaker;
  final String text;
  double time = 4;
}

enum Sfx { shoot, hit, explode, bigExplode, pickup, coin, gem, upgrade, alarm, warp, missile, shield, boost, hurt }
