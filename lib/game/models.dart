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

class PlayerShip {
  Offset pos = Offset.zero;
  Offset vel = Offset.zero;
  double angle = -pi / 2;
  double hp = 100;
  double fireCooldown = 0;
  double invulnerable = 0;
  bool thrusting = false;
  bool alive = true;
  double respawnTimer = 0;
}

enum PirateKind { scout, raider, boss }

class Pirate {
  Pirate(this.kind, this.pos, this.hp)
      : maxHp = hp,
        wanderAngle = 0;

  final PirateKind kind;
  Offset pos;
  Offset vel = Offset.zero;
  double angle = 0;
  double hp;
  final double maxHp;
  double fireCooldown = 1.5;
  double wanderAngle;
  double hitFlash = 0;

  double get radius => switch (kind) {
        PirateKind.scout => 18,
        PirateKind.raider => 24,
        PirateKind.boss => 46,
      };

  double get speed => switch (kind) {
        PirateKind.scout => 290,
        PirateKind.raider => 210,
        PirateKind.boss => 150,
      };

  double get damage => switch (kind) {
        PirateKind.scout => 6,
        PirateKind.raider => 10,
        PirateKind.boss => 16,
      };

  double get fireInterval => switch (kind) {
        PirateKind.scout => 1.1,
        PirateKind.raider => 1.4,
        PirateKind.boss => 0.9,
      };

  int get bounty => switch (kind) {
        PirateKind.scout => 25,
        PirateKind.raider => 50,
        PirateKind.boss => 400,
      };
}

class Bullet {
  Bullet(this.pos, this.vel, this.damage, this.fromPlayer, {this.life = 1.2});
  Offset pos;
  final Offset vel;
  final double damage;
  final bool fromPlayer;
  double life;
}

class Asteroid {
  Asteroid(this.pos, this.radius, int seed)
      : hp = radius * 1.5,
        rotation = 0,
        spin = (Random(seed).nextDouble() - 0.5) * 0.8,
        shape = List.generate(
            9, (i) => 0.75 + Random(seed + i * 31).nextDouble() * 0.35);
  Offset pos;
  final double radius;
  double hp;
  double rotation;
  final double spin;
  final List<double> shape;
  double hitFlash = 0;
}

enum PickupKind { credits, ore }

class Pickup {
  Pickup(this.kind, this.pos, this.amount, this.vel);
  final PickupKind kind;
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

enum PlanetKind { garden, desert, ice, lava, gas }

class Planet {
  Planet(this.name, this.pos, this.radius, this.kind);
  final String name;
  final Offset pos;
  final double radius;
  final PlanetKind kind;
  int colonyLevel = 0;

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

  double get creditRate => ratePerLevel.$1 * colonyLevel;
  double get oreRate => ratePerLevel.$2 * colonyLevel;

  (int credits, int ore) get nextCost {
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
  double get creditRate => habitatLevel * 2.0;
  double get turretRange => 380 + turretLevel * 30;
  double get turretDamage => 6 + turretLevel * 4;
  double get turretInterval => 0.9 / (1 + turretLevel * 0.2);

  (int, int) get habitatCost =>
      ((250 * pow(1.7, habitatLevel - 1)).round(), 60 * habitatLevel);
  (int, int) get turretCost =>
      ((200 * pow(1.7, turretLevel)).round(), 80 * (turretLevel + 1));
}

enum Speaker { captain, pirate, advisor }

class DialogLine {
  DialogLine(this.speaker, this.text);
  final Speaker speaker;
  final String text;
  double time = 4;
}
