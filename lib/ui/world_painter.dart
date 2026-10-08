import 'dart:math';

import 'package:flutter/material.dart';

import '../game/cosmetics.dart';
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

/// 자주 쓰는 라벨 TextPainter 캐시.
/// 웹에서는 한글 대체 폰트가 늦게 로드되므로, 폰트가 바뀌면 캐시를 비운다.
final _textCache = <String, TextPainter>{};
bool _fontListener = false;

TextPainter _text(String text, Color color, double size) {
  final key = '$text|${color.toARGB32()}|$size';
  if (!_fontListener) {
    _fontListener = true;
    PaintingBinding.instance.systemFonts.addListener(_textCache.clear);
  }
  final hit = _textCache[key];
  if (hit != null) return hit;
  if (_textCache.length > 400) _textCache.clear();
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(blurRadius: 3, color: Colors.black)])),
    textDirection: TextDirection.ltr,
  )..layout();
  return _textCache[key] = tp;
}

/// 섹터마다 배경 색감이 달라짐
const _sectorTints = [
  (Color(0xFF1A1440), Color(0xFF070614)),
  (Color(0xFF102A43), Color(0xFF050B14)),
  (Color(0xFF3A1430), Color(0xFF0E0510)),
  (Color(0xFF2B1A0A), Color(0xFF0D0703)),
  (Color(0xFF0D2B26), Color(0xFF03100D)),
];

class WorldPainter extends CustomPainter {
  WorldPainter(this.world, this.zoom, {required Listenable repaint})
      : super(repaint: repaint);
  final GameWorld world;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Random();
    final shake = world.shake;
    final cam = world.player.alive ? world.player.pos : world.player.deathPos;
    final shakeOff = shake > 0
        ? Offset((r.nextDouble() - 0.5) * shake, (r.nextDouble() - 0.5) * shake)
        : Offset.zero;
    final t = world.totalTime;

    final tint = _sectorTints[world.sector % _sectorTints.length];
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(colors: [tint.$1, tint.$2], radius: 1.2)
            .createShader(Offset.zero & size),
    );
    _paintNebula(canvas, size, cam);
    _paintStars(canvas, size, cam, t);

    canvas.save();
    canvas.translate(size.width / 2 + shakeOff.dx, size.height / 2 + shakeOff.dy);
    canvas.scale(zoom);
    canvas.translate(-cam.dx, -cam.dy);

    final view = Rect.fromCenter(
        center: cam, width: size.width / zoom + 600, height: size.height / zoom + 600);

    _paintBoundary(canvas);
    for (final g in world.gates) {
      if (view.inflate(200).contains(g.pos)) _paintGate(canvas, g, t);
    }
    for (final p in world.planets) {
      if (view.inflate(p.radius).contains(p.pos)) _paintPlanet(canvas, p, t);
    }
    for (final s in world.stations) {
      if (view.contains(s.pos)) _paintStation(canvas, s);
    }
    for (final ev in world.events) {
      if (ev.kind == EventKind.merchant && view.contains(ev.pos)) _paintMerchant(canvas, ev, t);
    }
    for (final a in world.asteroids) {
      if (view.contains(a.pos)) _paintAsteroid(canvas, a);
    }
    for (final k in world.pickups) {
      if (view.contains(k.pos)) _paintPickup(canvas, k, t);
    }
    final pp = Paint();
    for (final p in world.particles) {
      if (!view.contains(p.pos)) continue;
      final f = (p.life / p.maxLife).clamp(0.0, 1.0);
      pp.color = p.color.withValues(alpha: f);
      canvas.drawCircle(p.pos, p.size * (0.5 + f * 0.5), pp);
    }
    for (final b in world.bullets) {
      _paintBullet(canvas, b);
    }
    for (final m in world.missiles) {
      _paintMissile(canvas, m);
    }
    for (final e in world.pirates) {
      if (view.inflate(60).contains(e.pos)) _paintPirate(canvas, e, t);
    }
    if (world.player.alive) _paintPlayer(canvas, t);
    for (final f in world.floats) {
      // 알파를 4단계로 나눠 TextPainter 캐시 재사용
      final a = ((f.life.clamp(0.0, 1.0) * 4).ceil() / 4).clamp(0.25, 1.0);
      final tp = _text(f.text, f.color.withValues(alpha: a), f.big ? 20 : 15);
      tp.paint(canvas, f.pos - Offset(tp.width / 2, tp.height / 2));
    }

    canvas.restore();
    _paintOffscreenArrows(canvas, size, cam);
  }

  void _paintNebula(Canvas canvas, Size size, Offset cam) {
    const blobs = [
      (0.2, 0.3, Color(0x334A2C8F), 0.6),
      (0.8, 0.7, Color(0x2A1E5A8F), 0.7),
      (0.6, 0.15, Color(0x22C2185B), 0.5),
    ];
    for (final (bx, by, c, rr) in blobs) {
      final w = size.width * 2;
      final h = size.height * 2;
      final x = (bx * w - cam.dx * 0.03) % w - size.width * 0.5;
      final y = (by * h - cam.dy * 0.03) % h - size.height * 0.5;
      final radius = size.longestSide * rr;
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

  void _paintGate(Canvas canvas, WarpGate g, double t) {
    final open = world.gateOpen(g);
    final c = open ? const Color(0xFFB388FF) : const Color(0xFF616161);
    canvas.save();
    canvas.translate(g.pos.dx, g.pos.dy);
    // 회전하는 소용돌이
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.rotate(t * (open ? 1.5 : 0.3) + i * 2 * pi / 3);
      canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: 70 - i * 14), 0, pi * 1.2, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round
            ..color = c.withValues(alpha: 0.8 - i * 0.2));
      canvas.restore();
    }
    canvas.drawCircle(
        Offset.zero,
        40,
        Paint()
          ..shader = RadialGradient(colors: [
            open ? Colors.white : const Color(0xFF9E9E9E),
            c.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: Offset.zero, radius: 40)));
    // 프레임
    canvas.drawCircle(
        Offset.zero,
        86,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0xFF78909C));
    canvas.restore();
    final label = g.forward
        ? (open ? '🌀 다음 섹터로' : '🔒 두목을 쓰러뜨리면 열림')
        : '🌀 이전 섹터로';
    _label(canvas, g.pos + const Offset(0, 110), label, open ? const Color(0xFFD1C4E9) : Colors.white54);
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
          ..shader = RadialGradient(center: const Alignment(-0.4, -0.4), colors: [light, dark])
              .createShader(rect));

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final deco = Paint()..color = Colors.white.withValues(alpha: 0.12);
    if (p.kind == PlanetKind.gas) {
      for (var i = -3; i <= 3; i++) {
        canvas.drawRect(
            Rect.fromLTWH(p.pos.dx - p.radius, p.pos.dy + i * p.radius * 0.28, p.radius * 2,
                p.radius * 0.1),
            deco);
      }
    } else {
      final r = Random(p.name.hashCode);
      for (var i = 0; i < 6; i++) {
        final o = Offset(randRange(r, -0.7, 0.7), randRange(r, -0.7, 0.7)) * p.radius;
        canvas.drawCircle(
            p.pos + o,
            p.radius * randRange(r, 0.12, 0.3),
            Paint()
              ..color = (p.kind == PlanetKind.lava ? const Color(0xFFFFEB3B) : dark)
                  .withValues(alpha: 0.35));
      }
    }
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

    for (var i = 0; i < p.colonyLevel; i++) {
      final a = -pi / 2 + (i - (p.colonyLevel - 1) / 2) * 0.35;
      final base = p.pos + OffsetX.fromAngle(a, p.radius);
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(a + pi / 2);
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: 14), pi, pi, true,
          Paint()..color = const Color(0xCCB3E5FC));
      canvas.drawRect(const Rect.fromLTWH(-3, -22, 6, 10), Paint()..color = const Color(0xFFFFD54F));
      final on = sin(t * 3 + i) > 0;
      canvas.drawCircle(const Offset(0, -6), 3,
          Paint()..color = on ? const Color(0xFFFFF59D) : const Color(0xFF90A4AE));
      canvas.restore();
    }
    if (p.colonyLevel > 0) {
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
    if (p.raided) {
      final pulse = 0.5 + 0.5 * sin(t * 8);
      canvas.drawCircle(
          p.pos,
          p.radius + 30,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = const Color(0xFFFF1744).withValues(alpha: 0.4 + 0.5 * pulse));
      _label(canvas, p.pos + Offset(0, -p.radius - 70), '⚠ 습격 중!', const Color(0xFFFF5252));
    }

    _label(canvas, p.pos + Offset(0, p.radius + 22),
        p.colonyLevel > 0 ? '${p.name}  Lv.${p.colonyLevel}' : p.name,
        p.colonyLevel > 0 ? const Color(0xFF7CFFB2) : Colors.white70);
  }

  void _paintStation(Canvas canvas, Station s) {
    canvas.save();
    canvas.translate(s.pos.dx, s.pos.dy);
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
    if (s.habitatLevel >= 4) {
      canvas.drawCircle(Offset.zero, ringR + 22,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = const Color(0xFF607D8B));
    }
    final windows = 8 + s.habitatLevel * 2;
    for (var i = 0; i < windows; i++) {
      canvas.drawCircle(OffsetX.fromAngle(i * 2 * pi / windows, ringR), 2.5,
          Paint()..color = const Color(0xFFFFF59D));
    }
    for (final sx in [-1.0, 1.0]) {
      canvas.drawRect(
          Rect.fromCenter(center: Offset(sx * (ringR + 34), 0), width: 40, height: 18),
          Paint()..color = const Color(0xFF1E88E5));
      canvas.drawLine(Offset(sx * ringR, 0), Offset(sx * (ringR + 14), 0), metal..strokeWidth = 4);
    }
    canvas.drawCircle(Offset.zero, 22, metal);
    canvas.drawCircle(Offset.zero, 12, Paint()..color = const Color(0xFF4FC3F7));
    for (var i = 0; i < s.turretLevel; i++) {
      final a = i * 2 * pi / max(1, s.turretLevel) + pi / 4;
      canvas.drawCircle(OffsetX.fromAngle(a, ringR), 7, Paint()..color = const Color(0xFFE53935));
    }
    canvas.restore();

    _bar(canvas, s.pos + Offset(0, -ringR - 30), 80, s.hp / s.maxHp, const Color(0xFF42A5F5));
    _label(canvas, s.pos + Offset(0, ringR + 30), s.name, const Color(0xFF8AD8FF));
  }

  void _paintMerchant(Canvas canvas, WorldEvent ev, double t) {
    final bob = sin(t * 2) * 6;
    final c = ev.pos + Offset(0, bob);
    // 동글동글 상인선
    canvas.drawOval(Rect.fromCenter(center: c, width: 120, height: 60),
        Paint()..color = const Color(0xFF00897B));
    canvas.drawOval(Rect.fromCenter(center: c + const Offset(0, 8), width: 120, height: 30),
        Paint()..color = const Color(0xFF00695C));
    for (var i = -1; i <= 1; i++) {
      canvas.drawCircle(c + Offset(i * 30.0, 18), 6,
          Paint()..color = (sin(t * 6 + i) > 0 ? const Color(0xFFFFEB3B) : const Color(0xFFFF8A65)));
    }
    canvas.drawCircle(c + const Offset(0, -22), 24, Paint()..color = const Color(0x88B2EBF2));
    paintChibi(canvas, c + const Offset(0, -22), 14, ChibiStyle.merchant, withBody: false);
    _label(canvas, c + const Offset(0, 54), '🛒 떠돌이 상인 (${ev.timeLeft.ceil()}초)', const Color(0xFFA7FFEB));
  }

  void _paintAsteroid(Canvas canvas, Asteroid a) {
    final path = Path();
    for (var i = 0; i < a.shape.length; i++) {
      final ang = a.rotation + i * 2 * pi / a.shape.length;
      final pt = a.pos + OffsetX.fromAngle(ang, a.radius * a.shape[i]);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    final base = a.crystal ? const Color(0xFF4A6572) : const Color(0xFF6D5D55);
    canvas.drawPath(path, Paint()..color = a.hitFlash > 0 ? const Color(0xFFD7CCC8) : base);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF3E2F2A));
    final gem = Paint()..color = const Color(0xFF4DD0E1);
    canvas.drawCircle(a.pos + OffsetX.fromAngle(a.rotation, a.radius * 0.3), a.radius * 0.15, gem);
    if (a.crystal) {
      canvas.drawCircle(a.pos + OffsetX.fromAngle(a.rotation + 2, a.radius * 0.35), a.radius * 0.2, gem);
      canvas.drawCircle(a.pos, a.radius * 1.1,
          Paint()..color = const Color(0x2200E5FF));
    }
  }

  void _paintPickup(Canvas canvas, Pickup k, double t) {
    final bob = sin(t * 5 + k.pos.dx) * 2;
    final c = k.pos + Offset(0, bob);
    switch (k.kind) {
      case PickupKind.credits:
        canvas.drawCircle(c, 7, Paint()..color = const Color(0xFFFFC107));
        canvas.drawCircle(c, 4, Paint()..color = const Color(0xFFFFE082));
      case PickupKind.ore:
        final path = Path()
          ..moveTo(c.dx, c.dy - 8)
          ..lineTo(c.dx + 6, c.dy)
          ..lineTo(c.dx, c.dy + 8)
          ..lineTo(c.dx - 6, c.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFF4DD0E1));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = Colors.white70);
      case PickupKind.gem:
        final capsule = identical(k, world.supplyCapsule);
        final s = capsule ? 22.0 : 9.0;
        if (capsule) {
          canvas.drawCircle(c, 40 + sin(t * 4) * 6, Paint()..color = const Color(0x33FF80AB));
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 44, height: 34),
                  const Radius.circular(8)),
              Paint()..color = const Color(0xFF8D6E63));
          _label(canvas, c + const Offset(0, 36), '📦 보급 캡슐', const Color(0xFFFF80AB));
        }
        _star(canvas, c, s, const Color(0xFFFF80AB));
      case PickupKind.power:
        canvas.drawCircle(c, 14 + sin(t * 6) * 2, Paint()..color = const Color(0x66B9F6CA));
        canvas.drawCircle(c, 11, Paint()..color = const Color(0xFF1B5E20));
        final tp = _text(k.power!.icon, Colors.white, 13);
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = -pi / 2 + i * pi / 5;
      final pt = c + OffsetX.fromAngle(a, rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white);
  }

  void _paintBullet(Canvas canvas, Bullet b) {
    final dir = b.vel.normalized();
    final c = b.fromPlayer ? const Color(0xFF80D8FF) : const Color(0xFFFF5252);
    final w = b.big ? 12.0 : 8.0;
    canvas.drawLine(b.pos - dir * (b.big ? 18 : 12), b.pos,
        Paint()
          ..color = c.withValues(alpha: 0.4)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(b.pos - dir * 10, b.pos,
        Paint()
          ..color = Colors.white
          ..strokeWidth = w * 0.4
          ..strokeCap = StrokeCap.round);
  }

  void _paintMissile(Canvas canvas, Missile m) {
    final dir = m.vel.normalized();
    canvas.drawLine(m.pos - dir * 12, m.pos,
        Paint()
          ..color = const Color(0xFFECEFF1)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(m.pos, 3, Paint()..color = const Color(0xFFFF7043));
  }

  void _paintPlayer(Canvas canvas, double t) {
    final p = world.player;
    if (p.invulnerable > 0.4 && (t * 10).floor().isEven) return;
    final skin = skinById(world.profile.skin);
    final outfit = outfitById(world.profile.outfit);
    final hull = skin.rainbow
        ? HSVColor.fromAHSV(1, (t * 90) % 360, 0.35, 1).toColor()
        : skin.hull;
    final wingC = skin.rainbow
        ? HSVColor.fromAHSV(1, (t * 90 + 120) % 360, 0.8, 0.9).toColor()
        : skin.wing;

    if (world.buffs.containsKey(PowerUpKind.rapid)) {
      canvas.drawCircle(p.pos, 34, Paint()..color = const Color(0x33FFEB3B));
    }

    canvas.save();
    canvas.translate(p.pos.dx, p.pos.dy);
    canvas.rotate(p.angle + pi / 2);
    if (p.thrusting || world.boostTime > 0) {
      final flick = (world.boostTime > 0 ? 30 : 14) + sin(t * 40) * 4;
      canvas.drawPath(
          Path()
            ..moveTo(-7, 18)
            ..lineTo(0, 18 + flick)
            ..lineTo(7, 18)
            ..close(),
          Paint()..color = world.boostTime > 0 ? const Color(0xFF80D8FF) : const Color(0xFFFFB74D));
    }
    final wing = Paint()..color = wingC;
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
    // 무기 레벨에 따른 포신
    if (world.weaponLevel >= 3) {
      final gun = Paint()..color = const Color(0xFF546E7A);
      canvas.drawRect(const Rect.fromLTWH(-20, -2, 4, 12), gun);
      canvas.drawRect(const Rect.fromLTWH(16, -2, 4, 12), gun);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -26, 22, 46), const Radius.circular(11)),
        Paint()..color = hull);
    canvas.drawRect(const Rect.fromLTWH(-11, 8, 22, 4), Paint()..color = skin.stripe);
    canvas.drawCircle(const Offset(0, -8), 10, Paint()..color = const Color(0xFF263238));
    canvas.save();
    canvas.rotate(-(p.angle + pi / 2));
    paintChibi(canvas, _rot(const Offset(0, -8), p.angle + pi / 2), 6.5,
        ChibiStyle.captainIn(outfit).copyWith(helmet: false),
        withBody: false);
    canvas.restore();
    canvas.drawCircle(const Offset(0, -8), 10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xAAB3E5FC));
    canvas.restore();

    if (world.shielded) {
      final pulse = 0.5 + 0.5 * sin(t * 10);
      canvas.drawCircle(p.pos, 36,
          Paint()..color = const Color(0xFF40C4FF).withValues(alpha: 0.15 + 0.1 * pulse));
      canvas.drawCircle(
          p.pos,
          36,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFF80D8FF).withValues(alpha: 0.6 + 0.3 * pulse));
    }
  }

  Offset _rot(Offset o, double a) =>
      Offset(o.dx * cos(a) - o.dy * sin(a), o.dx * sin(a) + o.dy * cos(a));

  void _paintPirate(Canvas canvas, Pirate e, double t) {
    if (e.kind == PirateKind.jelly) {
      _paintJelly(canvas, e, t);
      return;
    }
    final scale = e.radius / 20;
    canvas.save();
    canvas.translate(e.pos.dx, e.pos.dy);
    canvas.rotate(e.angle + pi / 2);
    canvas.scale(scale);
    final flash = e.hitFlash > 0;
    final hullColor = flash
        ? Colors.white
        : switch (e.kind) {
            PirateKind.boss => const Color(0xFF6A1B9A),
            PirateKind.bomber => const Color(0xFF3E2723),
            PirateKind.sniper => const Color(0xFF263238),
            _ => e.name != null ? const Color(0xFF4E342E) : const Color(0xFF37474F),
          };
    final hull = Paint()..color = hullColor;
    switch (e.kind) {
      case PirateKind.bomber:
        canvas.drawCircle(Offset.zero, 18, hull);
        canvas.drawLine(const Offset(0, -18), const Offset(6, -28),
            Paint()
              ..color = const Color(0xFFBCAAA4)
              ..strokeWidth = 3);
        canvas.drawCircle(const Offset(6, -29), 4 + sin(t * 20) * 2,
            Paint()..color = const Color(0xFFFFAB40));
        canvas.drawPath(
            Path()
              ..moveTo(-12, 10)
              ..lineTo(0, 22)
              ..lineTo(12, 10)
              ..close(),
            Paint()..color = const Color(0xFFC62828));
      case PirateKind.sniper:
        canvas.drawPath(
            Path()
              ..moveTo(0, -30)
              ..lineTo(6, -6)
              ..lineTo(20, 14)
              ..lineTo(6, 10)
              ..lineTo(0, 20)
              ..lineTo(-6, 10)
              ..lineTo(-20, 14)
              ..lineTo(-6, -6)
              ..close(),
            hull);
        canvas.drawRect(const Rect.fromLTWH(-1.5, -40, 3, 14), Paint()..color = const Color(0xFF90A4AE));
        canvas.drawCircle(const Offset(0, -38), 2, Paint()..color = const Color(0xFFFF1744));
      default:
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
            Paint()..color = e.name != null ? const Color(0xFFFFB300) : const Color(0xFFC62828));
    }
    canvas.drawCircle(const Offset(0, -2), 9, Paint()..color = const Color(0xFF212121));
    canvas.save();
    canvas.rotate(-(e.angle + pi / 2));
    paintChibi(canvas, _rot(const Offset(0, -2), e.angle + pi / 2), 6,
        e.sectorBoss || e.name != null
            ? ChibiStyle.pirate.copyWith(accessory: Accessory.captainHat)
            : ChibiStyle.pirate,
        withBody: false);
    canvas.restore();
    canvas.restore();

    if (e.hp < e.maxHp) {
      _bar(canvas, e.pos + Offset(0, -e.radius - 14), e.radius * 2, e.hp / e.maxHp,
          const Color(0xFFFF5252));
    }
    if (e.sectorBoss) {
      _label(canvas, e.pos + Offset(0, e.radius + 18), '☠ ${world.sectorName} 두목', const Color(0xFFFF8A80));
    } else if (e.kind == PirateKind.boss) {
      _label(canvas, e.pos + Offset(0, e.radius + 18), '☠ 해적 두목', const Color(0xFFFF8A80));
    } else if (e.name != null) {
      _label(canvas, e.pos + Offset(0, e.radius + 16), '🎯 ${e.name}', const Color(0xFFFFD54F));
    }
  }

  void _paintJelly(Canvas canvas, Pirate e, double t) {
    final c = e.pos;
    final r = e.radius;
    final tent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xAAE040FB);
    for (var i = 0; i < 5; i++) {
      final x = c.dx + (i - 2) * r * 0.35;
      final path = Path()..moveTo(x, c.dy);
      for (var k = 1; k <= 4; k++) {
        path.lineTo(x + sin(t * 4 + i + k) * 6, c.dy + k * r * 0.3);
      }
      canvas.drawPath(path, tent);
    }
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), pi, pi, true,
        Paint()
          ..color = e.hitFlash > 0 ? Colors.white : const Color(0xCCCE93D8));
    canvas.drawArc(Rect.fromCircle(center: c + Offset(-r * 0.3, -r * 0.3), radius: r * 0.35), pi, pi * 0.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white54);
    // 귀여운 얼굴
    final eye = Paint()..color = const Color(0xFF4A148C);
    canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.35), r * 0.1, eye);
    canvas.drawCircle(c + Offset(r * 0.3, -r * 0.35), r * 0.1, eye);
    canvas.drawArc(Rect.fromCenter(center: c + Offset(0, -r * 0.2), width: r * 0.3, height: r * 0.2), 0.2,
        pi - 0.4, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF4A148C));
    if (e.hp < e.maxHp) {
      _bar(canvas, c + Offset(0, -r - 10), r * 2, e.hp / e.maxHp, const Color(0xFFE040FB));
    }
  }

  void _paintOffscreenArrows(Canvas canvas, Size size, Offset cam) {
    final center = size.center(Offset.zero);
    void arrow(Offset worldPos, Color color, double maxDist, {double scale = 1}) {
      final rel = (worldPos - cam) * zoom;
      if (rel.dx.abs() < size.width / 2 - 20 && rel.dy.abs() < size.height / 2 - 20) return;
      if (rel.distance > maxDist * zoom) return;
      final dir = rel.normalized();
      final sx = (size.width / 2 - 30) / max(0.001, dir.dx.abs());
      final sy = (size.height / 2 - 30) / max(0.001, dir.dy.abs());
      final pos = center + dir * min(sx, sy);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(atan2(dir.dy, dir.dx));
      canvas.scale(scale);
      canvas.drawPath(
          Path()
            ..moveTo(12, 0)
            ..lineTo(-7, -9)
            ..lineTo(-7, 9)
            ..close(),
          Paint()..color = color);
      canvas.restore();
    }

    for (final e in world.pirates) {
      if (!e.isPirate) continue;
      arrow(e.pos, const Color(0xCCFF5252), e.isBossLike ? 4000 : 1600,
          scale: e.isBossLike ? 1.6 : 1);
    }
    for (final ev in world.events) {
      arrow(ev.pos, const Color(0xEEFFD740), 9000, scale: 1.3);
    }
    for (final pos in world.missionTargets) {
      arrow(pos, const Color(0xEEFFAB00), 9000, scale: 1.2);
    }
    for (final g in world.gates) {
      if (g.forward && world.gateOpen(g)) arrow(g.pos, const Color(0xEEB388FF), 9000, scale: 1.3);
    }
  }

  void _bar(Canvas canvas, Offset center, double w, double f, Color c) {
    final r = Rect.fromCenter(center: center, width: w, height: 5);
    canvas.drawRect(r, Paint()..color = Colors.black54);
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, w * f.clamp(0, 1), r.height), Paint()..color = c);
  }

  void _label(Canvas canvas, Offset center, String text, Color color) {
    final tp = _text(text, color, 14);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(WorldPainter old) => true;
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
    Offset m(Offset p) =>
        Offset((p.dx + GameWorld.worldHalf) * s, (p.dy + GameWorld.worldHalf) * s);
    for (final g in world.gates) {
      canvas.drawCircle(m(g.pos), 4,
          Paint()..color = world.gateOpen(g) ? const Color(0xFFB388FF) : const Color(0xFF757575));
    }
    for (final p in world.planets) {
      final (light, _) = WorldPainter.planetColors(p.kind);
      canvas.drawCircle(m(p.pos), max(2.5, p.radius * s), Paint()..color = light);
      if (p.colonyLevel > 0) {
        canvas.drawCircle(
            m(p.pos),
            max(2.5, p.radius * s) + 2,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = p.raided ? const Color(0xFFFF1744) : const Color(0xFF7CFFB2));
      }
    }
    for (final st in world.stations) {
      canvas.drawRect(Rect.fromCenter(center: m(st.pos), width: 5, height: 5),
          Paint()..color = const Color(0xFF8AD8FF));
    }
    for (final e in world.pirates) {
      canvas.drawCircle(
          m(e.pos),
          e.isBossLike ? 3.2 : 1.6,
          Paint()
            ..color = e.kind == PirateKind.jelly
                ? const Color(0xFFE040FB)
                : (e.name != null ? const Color(0xFFFFAB00) : const Color(0xFFFF5252)));
    }
    for (final ev in world.events) {
      canvas.drawCircle(m(ev.pos), 4, Paint()..color = const Color(0xFFFFD740));
    }
    for (final pos in world.missionTargets) {
      canvas.drawCircle(
          m(pos),
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFFFFAB00));
    }
    canvas.drawCircle(m(world.player.pos), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(MinimapPainter old) => true;
}
