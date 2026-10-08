import 'dart:math';

import 'package:flutter/material.dart';

import '../game/models.dart';
import '../game/world.dart';
import 'chibi.dart';

class _Star {
  _Star(this.x, this.y, this.depth, this.size, this.twinkle);
  final double x, y, depth, size, twinkle;
}

final List<_Star> _stars = () {
  final r = Random(7);
  return List.generate(260, (_) {
    final depth = 0.05 + r.nextDouble() * 0.45;
    return _Star(r.nextDouble(), r.nextDouble(), depth,
        0.6 + depth * 3 * r.nextDouble(), r.nextDouble() * 6);
  });
}();

class WorldPainter extends CustomPainter {
  WorldPainter(this.world, this.zoom, {required Listenable repaint})
      : super(repaint: repaint);
  final GameWorld world;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = world.player.pos;
    final t = world.elapsed;

    // 배경
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1A1440), Color(0xFF070614)],
          radius: 1.2,
        ).createShader(Offset.zero & size),
    );
    _paintNebula(canvas, size, cam);
    _paintStars(canvas, size, cam, t);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(zoom);
    canvas.translate(-cam.dx, -cam.dy);

    final view = Rect.fromCenter(
        center: cam,
        width: size.width / zoom + 600,
        height: size.height / zoom + 600);

    _paintBoundary(canvas);
    for (final p in world.planets) {
      if (view.inflate(p.radius).contains(p.pos)) _paintPlanet(canvas, p, t);
    }
    for (final s in world.stations) {
      if (view.contains(s.pos)) _paintStation(canvas, s);
    }
    for (final a in world.asteroids) {
      if (view.contains(a.pos)) _paintAsteroid(canvas, a);
    }
    for (final k in world.pickups) {
      if (view.contains(k.pos)) _paintPickup(canvas, k, t);
    }
    final pp = Paint();
    for (final p in world.particles) {
      final f = (p.life / p.maxLife).clamp(0.0, 1.0);
      pp.color = p.color.withValues(alpha: f);
      canvas.drawCircle(p.pos, p.size * (0.5 + f * 0.5), pp);
    }
    for (final b in world.bullets) {
      _paintBullet(canvas, b);
    }
    for (final e in world.pirates) {
      if (view.contains(e.pos)) _paintPirate(canvas, e, t);
    }
    if (world.player.alive) _paintPlayer(canvas, t);

    canvas.restore();

    _paintOffscreenArrows(canvas, size, cam);
  }

  void _paintNebula(Canvas canvas, Size size, Offset cam) {
    const blobs = [
      (0.2, 0.3, Color(0x334A2C8F), 0.6),
      (0.8, 0.7, Color(0x2A1E5A8F), 0.7),
      (0.6, 0.15, Color(0x22C2185B), 0.5),
    ];
    for (final (bx, by, c, r) in blobs) {
      final w = size.width * 2;
      final h = size.height * 2;
      final x = (bx * w - cam.dx * 0.03) % w - size.width * 0.5;
      final y = (by * h - cam.dy * 0.03) % h - size.height * 0.5;
      final radius = size.longestSide * r;
      canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()
            ..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: Offset(x, y), radius: radius)));
    }
  }

  void _paintStars(Canvas canvas, Size size, Offset cam, double t) {
    final p = Paint();
    for (final s in _stars) {
      final x = (s.x * size.width - cam.dx * s.depth) % size.width;
      final y = (s.y * size.height - cam.dy * s.depth) % size.height;
      final tw = 0.6 + 0.4 * sin(t * 2 + s.twinkle);
      p.color = Colors.white.withValues(alpha: (0.3 + s.depth) * tw);
      canvas.drawCircle(Offset(x, y), s.size, p);
    }
  }

  void _paintBoundary(Canvas canvas) {
    const h = GameWorld.worldHalf;
    canvas.drawRect(
        const Rect.fromLTRB(-h, -h, h, h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = const Color(0x44FF5252));
  }

  static (Color, Color) planetColors(PlanetKind k) => switch (k) {
        PlanetKind.garden => (const Color(0xFF66BB6A), const Color(0xFF1565C0)),
        PlanetKind.desert => (const Color(0xFFFFCC80), const Color(0xFFBF6F2C)),
        PlanetKind.ice => (const Color(0xFFE1F5FE), const Color(0xFF4FC3F7)),
        PlanetKind.lava => (const Color(0xFFFF7043), const Color(0xFF3E2723)),
        PlanetKind.gas => (const Color(0xFFCE93D8), const Color(0xFF5E35B1)),
      };

  void _paintPlanet(Canvas canvas, Planet p, double t) {
    final (light, dark) = planetColors(p.kind);
    final rect = Rect.fromCircle(center: p.pos, radius: p.radius);
    // 대기광
    canvas.drawCircle(
        p.pos,
        p.radius * 1.25,
        Paint()
          ..shader = RadialGradient(
            colors: [light.withValues(alpha: 0.35), light.withValues(alpha: 0)],
            stops: const [0.75, 1],
          ).createShader(Rect.fromCircle(center: p.pos, radius: p.radius * 1.25)));
    canvas.drawCircle(
        p.pos,
        p.radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.4),
            colors: [light, dark],
          ).createShader(rect));

    // 표면 무늬
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final deco = Paint()..color = Colors.white.withValues(alpha: 0.12);
    if (p.kind == PlanetKind.gas) {
      for (var i = -3; i <= 3; i++) {
        canvas.drawRect(
            Rect.fromLTWH(p.pos.dx - p.radius, p.pos.dy + i * p.radius * 0.28,
                p.radius * 2, p.radius * 0.1),
            deco);
      }
    } else {
      final r = Random(p.name.hashCode);
      for (var i = 0; i < 6; i++) {
        final o = Offset(randRange(r, -0.7, 0.7), randRange(r, -0.7, 0.7)) * p.radius;
        canvas.drawCircle(p.pos + o, p.radius * randRange(r, 0.12, 0.3),
            Paint()..color = (p.kind == PlanetKind.lava
                    ? const Color(0xFFFFEB3B)
                    : dark)
                .withValues(alpha: 0.35));
      }
    }
    // 그림자
    canvas.drawCircle(
        p.pos,
        p.radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.45, -0.45),
            radius: 1.3,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
            stops: const [0.45, 1],
          ).createShader(rect));
    canvas.restore();

    if (p.kind == PlanetKind.gas) {
      canvas.drawOval(
          Rect.fromCenter(center: p.pos, width: p.radius * 3, height: p.radius * 0.6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = const Color(0x99E1BEE7));
    }

    // 식민지 건물 (돔)
    for (var i = 0; i < p.colonyLevel; i++) {
      final a = -pi / 2 + (i - (p.colonyLevel - 1) / 2) * 0.35;
      final base = p.pos + OffsetX.fromAngle(a, p.radius);
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(a + pi / 2);
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: 14), pi, pi, true,
          Paint()..color = const Color(0xCCB3E5FC));
      canvas.drawRect(const Rect.fromLTWH(-3, -22, 6, 10),
          Paint()..color = const Color(0xFFFFD54F));
      // 반짝이는 창문
      final on = sin(t * 3 + i) > 0;
      canvas.drawCircle(const Offset(0, -6), 3,
          Paint()..color = on ? const Color(0xFFFFF59D) : const Color(0xFF90A4AE));
      canvas.restore();
    }
    if (p.colonyLevel > 0) {
      // 깃발
      final top = p.pos + Offset(0, -p.radius - 26);
      canvas.drawLine(top, top + const Offset(0, -26),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2);
      canvas.drawPath(
          Path()
            ..moveTo(top.dx, top.dy - 26)
            ..lineTo(top.dx + 18, top.dy - 20)
            ..lineTo(top.dx, top.dy - 14)
            ..close(),
          Paint()..color = const Color(0xFF42A5F5));
    }

    _label(canvas, p.pos + Offset(0, p.radius + 22),
        p.colonyLevel > 0 ? '${p.name}  Lv.${p.colonyLevel}' : p.name,
        p.colonyLevel > 0 ? const Color(0xFF7CFFB2) : Colors.white70);
  }

  void _paintStation(Canvas canvas, Station s) {
    canvas.save();
    canvas.translate(s.pos.dx, s.pos.dy);
    // 범위 표시
    if (s.turretLevel > 0) {
      canvas.drawCircle(Offset.zero, s.turretRange,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0x2242A5F5));
    }
    canvas.rotate(s.spin);
    final ringR = 44.0 + s.habitatLevel * 4;
    final metal = Paint()..color = const Color(0xFF90A4AE);
    final dark = Paint()..color = const Color(0xFF455A64);
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.rotate(i * pi / 2);
      canvas.drawRect(Rect.fromLTWH(-4, 0, 8, ringR), dark);
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = const Color(0xFF78909C));
    // 창문
    for (var i = 0; i < 8 + s.habitatLevel * 2; i++) {
      final a = i * 2 * pi / (8 + s.habitatLevel * 2);
      canvas.drawCircle(OffsetX.fromAngle(a, ringR), 2.5,
          Paint()..color = const Color(0xFFFFF59D));
    }
    // 태양광 패널
    for (final sx in [-1.0, 1.0]) {
      canvas.drawRect(
          Rect.fromCenter(center: Offset(sx * (ringR + 34), 0), width: 40, height: 18),
          Paint()..color = const Color(0xFF1E88E5));
      canvas.drawLine(Offset(sx * ringR, 0), Offset(sx * (ringR + 14), 0),
          metal..strokeWidth = 4);
    }
    canvas.drawCircle(Offset.zero, 22, metal);
    canvas.drawCircle(Offset.zero, 12, Paint()..color = const Color(0xFF4FC3F7));
    // 포탑
    for (var i = 0; i < s.turretLevel; i++) {
      final a = i * 2 * pi / max(1, s.turretLevel) + pi / 4;
      canvas.drawCircle(OffsetX.fromAngle(a, ringR), 7,
          Paint()..color = const Color(0xFFE53935));
    }
    canvas.restore();

    _bar(canvas, s.pos + Offset(0, -ringR - 30), 80, s.hp / s.maxHp,
        const Color(0xFF42A5F5));
    _label(canvas, s.pos + Offset(0, ringR + 30), s.name, const Color(0xFF8AD8FF));
  }

  void _paintAsteroid(Canvas canvas, Asteroid a) {
    final path = Path();
    for (var i = 0; i < a.shape.length; i++) {
      final ang = a.rotation + i * 2 * pi / a.shape.length;
      final pt = a.pos + OffsetX.fromAngle(ang, a.radius * a.shape[i]);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path,
        Paint()..color = a.hitFlash > 0 ? const Color(0xFFD7CCC8) : const Color(0xFF6D5D55));
    canvas.drawPath(path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF3E2F2A));
    // 광맥
    canvas.drawCircle(a.pos + OffsetX.fromAngle(a.rotation, a.radius * 0.3),
        a.radius * 0.15, Paint()..color = const Color(0xFF4DD0E1));
  }

  void _paintPickup(Canvas canvas, Pickup k, double t) {
    final bob = sin(t * 5 + k.pos.dx) * 2;
    final c = k.pos + Offset(0, bob);
    if (k.kind == PickupKind.credits) {
      canvas.drawCircle(c, 7, Paint()..color = const Color(0xFFFFC107));
      canvas.drawCircle(c, 4, Paint()..color = const Color(0xFFFFE082));
    } else {
      final path = Path()
        ..moveTo(c.dx, c.dy - 8)
        ..lineTo(c.dx + 6, c.dy)
        ..lineTo(c.dx, c.dy + 8)
        ..lineTo(c.dx - 6, c.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF4DD0E1));
      canvas.drawPath(path,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white70);
    }
  }

  void _paintBullet(Canvas canvas, Bullet b) {
    final dir = b.vel.normalized();
    final c = b.fromPlayer ? const Color(0xFF80D8FF) : const Color(0xFFFF5252);
    canvas.drawLine(b.pos - dir * 12, b.pos,
        Paint()
          ..color = c.withValues(alpha: 0.4)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(b.pos - dir * 10, b.pos,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
  }

  void _paintPlayer(Canvas canvas, double t) {
    final p = world.player;
    if (p.invulnerable > 0 && (t * 10).floor().isEven) return;
    canvas.save();
    canvas.translate(p.pos.dx, p.pos.dy);
    canvas.rotate(p.angle + pi / 2); // 위쪽이 앞
    if (p.thrusting) {
      final flick = 14 + sin(t * 40) * 4;
      canvas.drawPath(
          Path()
            ..moveTo(-7, 18)
            ..lineTo(0, 18 + flick)
            ..lineTo(7, 18)
            ..close(),
          Paint()..color = const Color(0xFFFFB74D));
    }
    // 날개
    final wing = Paint()..color = const Color(0xFF1565C0);
    canvas.drawPath(
        Path()
          ..moveTo(-8, -4)
          ..lineTo(-26, 16)
          ..lineTo(-8, 14)
          ..close(),
        wing);
    canvas.drawPath(
        Path()
          ..moveTo(8, -4)
          ..lineTo(26, 16)
          ..lineTo(8, 14)
          ..close(),
        wing);
    // 동체
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-11, -26, 22, 46), const Radius.circular(11)),
        Paint()..color = const Color(0xFFECEFF1));
    canvas.drawRect(const Rect.fromLTWH(-11, 8, 22, 4),
        Paint()..color = const Color(0xFFE53935));
    // 조종석 돔 + 치비 선장 머리
    canvas.drawCircle(const Offset(0, -8), 10, Paint()..color = const Color(0xFF263238));
    canvas.save();
    canvas.rotate(-(p.angle + pi / 2)); // 캐릭터는 항상 똑바로
    paintChibi(canvas, _rot(const Offset(0, -8), p.angle + pi / 2), 6.5,
        ChibiStyle.captain.copyNoHelmet, withBody: false);
    canvas.restore();
    canvas.drawCircle(const Offset(0, -8), 10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xAAB3E5FC));
    canvas.restore();
  }

  Offset _rot(Offset o, double a) =>
      Offset(o.dx * cos(a) - o.dy * sin(a), o.dx * sin(a) + o.dy * cos(a));

  void _paintPirate(Canvas canvas, Pirate e, double t) {
    final scale = e.radius / 20;
    canvas.save();
    canvas.translate(e.pos.dx, e.pos.dy);
    canvas.rotate(e.angle + pi / 2);
    canvas.scale(scale);
    final hull = Paint()
      ..color = e.hitFlash > 0
          ? Colors.white
          : (e.kind == PirateKind.boss
              ? const Color(0xFF6A1B9A)
              : const Color(0xFF37474F));
    // 톱니 날개
    canvas.drawPath(
        Path()
          ..moveTo(0, -24)
          ..lineTo(10, -6)
          ..lineTo(24, -10)
          ..lineTo(18, 8)
          ..lineTo(26, 18)
          ..lineTo(8, 14)
          ..lineTo(0, 22)
          ..lineTo(-8, 14)
          ..lineTo(-26, 18)
          ..lineTo(-18, 8)
          ..lineTo(-24, -10)
          ..lineTo(-10, -6)
          ..close(),
        hull);
    canvas.drawPath(
        Path()
          ..moveTo(-18, 8)
          ..lineTo(18, 8)
          ..lineTo(0, 22)
          ..close(),
        Paint()..color = const Color(0xFFC62828));
    canvas.drawCircle(const Offset(0, -2), 9, Paint()..color = const Color(0xFF212121));
    canvas.save();
    canvas.rotate(-(e.angle + pi / 2));
    paintChibi(canvas, _rot(const Offset(0, -2), e.angle + pi / 2), 6,
        ChibiStyle.pirate, withBody: false);
    canvas.restore();
    canvas.restore();

    if (e.hp < e.maxHp) {
      _bar(canvas, e.pos + Offset(0, -e.radius - 12), e.radius * 2, e.hp / e.maxHp,
          const Color(0xFFFF5252));
    }
    if (e.kind == PirateKind.boss) {
      _label(canvas, e.pos + Offset(0, e.radius + 18), '☠ 해적 두목', const Color(0xFFFF8A80));
    }
  }

  void _paintOffscreenArrows(Canvas canvas, Size size, Offset cam) {
    final center = size.center(Offset.zero);
    final paint = Paint()..color = const Color(0xCCFF5252);
    for (final e in world.pirates) {
      final rel = (e.pos - cam) * zoom;
      if (rel.dx.abs() < size.width / 2 && rel.dy.abs() < size.height / 2) continue;
      if (rel.distance > 1600 * zoom) continue;
      final dir = rel.normalized();
      final edge = Offset(
          (dir.dx * size.width / 2 * 0.9),
          (dir.dy * size.height / 2 * 0.85));
      final pos = center + edge;
      final a = atan2(dir.dy, dir.dx);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(a);
      canvas.drawPath(
          Path()
            ..moveTo(10, 0)
            ..lineTo(-6, -7)
            ..lineTo(-6, 7)
            ..close(),
          paint);
      canvas.restore();
    }
  }

  void _bar(Canvas canvas, Offset center, double w, double f, Color c) {
    final r = Rect.fromCenter(center: center, width: w, height: 5);
    canvas.drawRect(r, Paint()..color = Colors.black54);
    canvas.drawRect(
        Rect.fromLTWH(r.left, r.top, w * f.clamp(0, 1), r.height), Paint()..color = c);
  }

  void _label(Canvas canvas, Offset center, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(blurRadius: 3, color: Colors.black)])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(WorldPainter old) => true;
}

extension on ChibiStyle {
  ChibiStyle get copyNoHelmet => ChibiStyle(
        skin: skin,
        hair: hair,
        suit: suit,
        eye: eye,
        eyePatch: eyePatch,
        bandana: bandana,
        glasses: glasses,
      );
}

/// 미니맵
class MinimapPainter extends CustomPainter {
  MinimapPainter(this.world, {required Listenable repaint}) : super(repaint: repaint);
  final GameWorld world;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(rr, Paint()..color = const Color(0xAA0D0B26));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x667E57C2));
    final s = size.width / (GameWorld.worldHalf * 2);
    Offset m(Offset p) => Offset(
        (p.dx + GameWorld.worldHalf) * s, (p.dy + GameWorld.worldHalf) * s);
    for (final p in world.planets) {
      final (light, _) = WorldPainter.planetColors(p.kind);
      canvas.drawCircle(m(p.pos), max(2.5, p.radius * s), Paint()..color = light);
      if (p.colonyLevel > 0) {
        canvas.drawCircle(
            m(p.pos),
            max(2.5, p.radius * s) + 2,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = const Color(0xFF7CFFB2));
      }
    }
    for (final st in world.stations) {
      canvas.drawRect(Rect.fromCenter(center: m(st.pos), width: 5, height: 5),
          Paint()..color = const Color(0xFF8AD8FF));
    }
    for (final e in world.pirates) {
      canvas.drawCircle(m(e.pos), e.kind == PirateKind.boss ? 3 : 1.6,
          Paint()..color = const Color(0xFFFF5252));
    }
    canvas.drawCircle(m(world.player.pos), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(MinimapPainter old) => true;
}
