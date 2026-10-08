import 'dart:math';

import 'package:flutter/material.dart';

import '../game/cosmetics.dart';
import '../game/crew.dart';
import '../game/models.dart';

/// 머리 큰 치비 캐릭터 스타일
class ChibiStyle {
  const ChibiStyle({
    required this.skin,
    required this.hair,
    required this.suit,
    required this.eye,
    this.eyePatch = false,
    this.bandana,
    this.helmet = false,
    this.glasses = false,
    this.accessory = Accessory.none,
  });

  final Color skin;
  final Color hair;
  final Color suit;
  final Color eye;
  final bool eyePatch;
  final Color? bandana;
  final bool helmet;
  final bool glasses;
  final Accessory accessory;

  ChibiStyle copyWith({Color? hair, Color? suit, bool? helmet, Accessory? accessory}) =>
      ChibiStyle(
        skin: skin,
        hair: hair ?? this.hair,
        suit: suit ?? this.suit,
        eye: eye,
        eyePatch: eyePatch,
        bandana: bandana,
        helmet: helmet ?? this.helmet,
        glasses: glasses,
        accessory: accessory ?? this.accessory,
      );

  /// 꾸미기 의상을 입은 선장
  static ChibiStyle captainIn(CaptainOutfit o) =>
      captain.copyWith(
          suit: o.suit, hair: o.hair, accessory: o.accessory, helmet: o.accessory == Accessory.none);

  static ChibiStyle forCrew(CrewMember c) => ChibiStyle(
        skin: Color(c.skinColor),
        hair: Color(c.hairColor),
        suit: Color(c.role.suitColor),
        eye: const Color(0xFF263238),
        glasses: c.glasses,
        accessory: c.accessory,
      );

  static const merchant = ChibiStyle(
    skin: Color(0xFFFFE0C7),
    hair: Color(0xFFFF9800),
    suit: Color(0xFF00897B),
    eye: Color(0xFF3E2723),
    accessory: Accessory.catEars,
  );

  static const captain = ChibiStyle(
    skin: Color(0xFFFFE0C7),
    hair: Color(0xFF5D4037),
    suit: Color(0xFF1E88E5),
    eye: Color(0xFF263238),
    helmet: true,
  );

  static const pirate = ChibiStyle(
    skin: Color(0xFFFFD3B0),
    hair: Color(0xFF212121),
    suit: Color(0xFF4E342E),
    eye: Color(0xFF263238),
    eyePatch: true,
    bandana: Color(0xFFE53935),
  );

  static const advisor = ChibiStyle(
    skin: Color(0xFFFFE6D5),
    hair: Color(0xFFEC407A),
    suit: Color(0xFF7E57C2),
    eye: Color(0xFF4A148C),
    glasses: true,
  );

  static ChibiStyle of(Speaker s, {ChibiStyle? captainStyle}) => switch (s) {
        Speaker.captain => captainStyle ?? captain,
        Speaker.pirate => pirate,
        Speaker.advisor => advisor,
        Speaker.merchant => merchant,
      };
}

/// [center]는 머리 중심, [r]은 머리 반지름. [withBody]가 false면 머리만.
void paintChibi(Canvas canvas, Offset center, double r, ChibiStyle st,
    {bool withBody = true, double blink = 1}) {
  final fill = Paint()..isAntiAlias = true;
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1, r * 0.06)
    ..color = const Color(0xFF3E2723).withValues(alpha: 0.85);

  // 몸통 (작게)
  if (withBody) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: center + Offset(0, r * 1.25), width: r * 1.1, height: r * 0.9),
      Radius.circular(r * 0.35),
    );
    fill.color = st.suit;
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, outline);
    // 팔
    for (final sx in [-1.0, 1.0]) {
      final arm = center + Offset(sx * r * 0.62, r * 1.2);
      fill.color = st.suit;
      canvas.drawCircle(arm, r * 0.2, fill);
      fill.color = st.skin;
      canvas.drawCircle(arm + Offset(sx * r * 0.05, r * 0.2), r * 0.13, fill);
    }
    // 배지
    fill.color = const Color(0xFFFFD54F);
    canvas.drawCircle(center + Offset(-r * 0.2, r * 1.1), r * 0.1, fill);
  }

  // 귀 장식 (머리 뒤)
  _paintEars(canvas, center, r, st);

  // 뒷머리
  fill.color = st.hair;
  canvas.drawCircle(center + Offset(0, -r * 0.05), r * 1.05, fill);

  // 얼굴
  fill.color = st.skin;
  canvas.drawOval(
      Rect.fromCenter(center: center + Offset(0, r * 0.08), width: r * 1.9, height: r * 1.8),
      fill);

  // 앞머리
  fill.color = st.hair;
  final bangs = Path()
    ..moveTo(center.dx - r * 1.02, center.dy)
    ..quadraticBezierTo(center.dx - r * 0.9, center.dy - r * 1.15,
        center.dx, center.dy - r * 1.08)
    ..quadraticBezierTo(center.dx + r * 0.9, center.dy - r * 1.15,
        center.dx + r * 1.02, center.dy)
    ..quadraticBezierTo(center.dx + r * 0.6, center.dy - r * 0.55,
        center.dx + r * 0.25, center.dy - r * 0.35)
    ..quadraticBezierTo(center.dx, center.dy - r * 0.7,
        center.dx - r * 0.3, center.dy - r * 0.3)
    ..quadraticBezierTo(center.dx - r * 0.65, center.dy - r * 0.55,
        center.dx - r * 1.02, center.dy)
    ..close();
  canvas.drawPath(bangs, fill);

  // 반다나
  if (st.bandana != null) {
    fill.color = st.bandana!;
    final band = Path()
      ..moveTo(center.dx - r * 1.05, center.dy - r * 0.35)
      ..quadraticBezierTo(
          center.dx, center.dy - r * 1.55, center.dx + r * 1.05, center.dy - r * 0.35)
      ..quadraticBezierTo(
          center.dx, center.dy - r * 0.85, center.dx - r * 1.05, center.dy - r * 0.35)
      ..close();
    canvas.drawPath(band, fill);
    // 매듭
    canvas.drawCircle(center + Offset(r * 1.05, -r * 0.4), r * 0.15, fill);
    fill.color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(center + Offset(-r * 0.3, -r * 0.85), r * 0.07, fill);
    canvas.drawCircle(center + Offset(r * 0.25, -r * 0.9), r * 0.07, fill);
  }

  // 눈 (크게)
  final eyeY = center.dy + r * 0.2;
  for (final sx in [-1.0, 1.0]) {
    final ec = Offset(center.dx + sx * r * 0.42, eyeY);
    if (st.eyePatch && sx > 0) {
      fill.color = const Color(0xFF212121);
      canvas.drawOval(Rect.fromCenter(center: ec, width: r * 0.5, height: r * 0.42), fill);
      final strap = Paint()
        ..color = const Color(0xFF212121)
        ..strokeWidth = r * 0.07
        ..style = PaintingStyle.stroke;
      canvas.drawLine(ec + Offset(-r * 0.2, -r * 0.12),
          center + Offset(-r * 0.9, -r * 0.5), strap);
      canvas.drawLine(ec + Offset(r * 0.2, -r * 0.1),
          center + Offset(r * 0.98, -r * 0.2), strap);
      continue;
    }
    final h = r * 0.48 * blink.clamp(0.08, 1);
    fill.color = st.eye;
    canvas.drawOval(Rect.fromCenter(center: ec, width: r * 0.36, height: h), fill);
    if (blink > 0.5) {
      fill.color = Colors.white;
      canvas.drawCircle(ec + Offset(-r * 0.06, -r * 0.1), r * 0.08, fill);
      canvas.drawCircle(ec + Offset(r * 0.07, r * 0.08), r * 0.04, fill);
    }
  }

  // 안경
  if (st.glasses) {
    final g = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..color = const Color(0xFF4A148C);
    for (final sx in [-1.0, 1.0]) {
      canvas.drawCircle(Offset(center.dx + sx * r * 0.42, eyeY), r * 0.3, g);
    }
    canvas.drawLine(Offset(center.dx - r * 0.12, eyeY),
        Offset(center.dx + r * 0.12, eyeY), g);
  }

  // 볼터치
  fill.color = const Color(0xFFFF8A80).withValues(alpha: 0.55);
  canvas.drawOval(
      Rect.fromCenter(
          center: Offset(center.dx - r * 0.65, eyeY + r * 0.32),
          width: r * 0.32, height: r * 0.18),
      fill);
  canvas.drawOval(
      Rect.fromCenter(
          center: Offset(center.dx + r * 0.65, eyeY + r * 0.32),
          width: r * 0.32, height: r * 0.18),
      fill);

  // 입
  final mouth = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1, r * 0.07)
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xFF6D4C41);
  if (st.eyePatch) {
    // 해적: 씨익 웃음
    canvas.drawArc(
        Rect.fromCenter(center: Offset(center.dx + r * 0.08, eyeY + r * 0.42),
            width: r * 0.5, height: r * 0.3),
        0.1, pi * 0.8, false, mouth);
  } else {
    canvas.drawArc(
        Rect.fromCenter(center: Offset(center.dx, eyeY + r * 0.4),
            width: r * 0.3, height: r * 0.22),
        0.2, pi - 0.4, false, mouth);
  }

  _paintTopAccessory(canvas, center, r, st);

  // 우주 헬멧 (유리)
  if (st.helmet) {
    final glass = Paint()
      ..color = const Color(0xFFB3E5FC).withValues(alpha: 0.18);
    canvas.drawCircle(center + Offset(0, r * 0.05), r * 1.3, glass);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08
      ..color = const Color(0xFFE1F5FE).withValues(alpha: 0.8);
    canvas.drawCircle(center + Offset(0, r * 0.05), r * 1.3, rim);
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.6);
    canvas.drawArc(
        Rect.fromCircle(center: center + Offset(0, r * 0.05), radius: r * 1.05),
        pi * 1.1, pi * 0.3, false, shine);
  }
}

void _paintEars(Canvas canvas, Offset c, double r, ChibiStyle st) {
  final p = Paint()..isAntiAlias = true;
  switch (st.accessory) {
    case Accessory.catEars:
      for (final sx in [-1.0, 1.0]) {
        final path = Path()
          ..moveTo(c.dx + sx * r * 0.95, c.dy - r * 0.35)
          ..lineTo(c.dx + sx * r * 0.85, c.dy - r * 1.45)
          ..lineTo(c.dx + sx * r * 0.25, c.dy - r * 0.95)
          ..close();
        p.color = st.hair;
        canvas.drawPath(path, p);
        final inner = Path()
          ..moveTo(c.dx + sx * r * 0.8, c.dy - r * 0.6)
          ..lineTo(c.dx + sx * r * 0.8, c.dy - r * 1.2)
          ..lineTo(c.dx + sx * r * 0.42, c.dy - r * 0.92)
          ..close();
        p.color = const Color(0xFFFFAB91);
        canvas.drawPath(inner, p);
      }
    case Accessory.bunnyEars:
      for (final sx in [-1.0, 1.0]) {
        final rect = Rect.fromCenter(
            center: Offset(c.dx + sx * r * 0.45, c.dy - r * 1.55),
            width: r * 0.45,
            height: r * 1.3);
        canvas.save();
        canvas.translate(rect.center.dx, rect.center.dy);
        canvas.rotate(sx * 0.2);
        canvas.translate(-rect.center.dx, -rect.center.dy);
        p.color = Colors.white;
        canvas.drawOval(rect, p);
        p.color = const Color(0xFFF8BBD0);
        canvas.drawOval(rect.deflate(r * 0.1), p);
        canvas.restore();
      }
    default:
      break;
  }
}

void _paintTopAccessory(Canvas canvas, Offset c, double r, ChibiStyle st) {
  final p = Paint()..isAntiAlias = true;
  switch (st.accessory) {
    case Accessory.crown:
      final path = Path()
        ..moveTo(c.dx - r * 0.55, c.dy - r * 0.85)
        ..lineTo(c.dx - r * 0.6, c.dy - r * 1.45)
        ..lineTo(c.dx - r * 0.3, c.dy - r * 1.15)
        ..lineTo(c.dx, c.dy - r * 1.55)
        ..lineTo(c.dx + r * 0.3, c.dy - r * 1.15)
        ..lineTo(c.dx + r * 0.6, c.dy - r * 1.45)
        ..lineTo(c.dx + r * 0.55, c.dy - r * 0.85)
        ..close();
      p.color = const Color(0xFFFFD54F);
      canvas.drawPath(path, p);
      p.color = const Color(0xFFE91E63);
      canvas.drawCircle(Offset(c.dx, c.dy - r * 1.08), r * 0.1, p);
      p.color = const Color(0xFF29B6F6);
      canvas.drawCircle(Offset(c.dx - r * 0.35, c.dy - r * 1.0), r * 0.07, p);
      canvas.drawCircle(Offset(c.dx + r * 0.35, c.dy - r * 1.0), r * 0.07, p);
    case Accessory.captainHat:
      p.color = const Color(0xFF263238);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(c.dx, c.dy - r * 0.85), width: r * 2.3, height: r * 0.5), p);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(c.dx, c.dy - r * 1.2), width: r * 1.5, height: r * 0.75),
              Radius.circular(r * 0.3)),
          p);
      p.color = const Color(0xFFFFD54F);
      canvas.drawRect(
          Rect.fromCenter(center: Offset(c.dx, c.dy - r * 0.95), width: r * 1.5, height: r * 0.12), p);
      canvas.drawCircle(Offset(c.dx, c.dy - r * 1.25), r * 0.16, p);
    case Accessory.antenna:
      final stroke = Paint()
        ..color = const Color(0xFF2E7D32)
        ..strokeWidth = r * 0.08
        ..style = PaintingStyle.stroke;
      for (final sx in [-1.0, 1.0]) {
        final tip = Offset(c.dx + sx * r * 0.6, c.dy - r * 1.7);
        canvas.drawLine(Offset(c.dx + sx * r * 0.3, c.dy - r * 0.95), tip, stroke);
        p.color = const Color(0xFFB2FF59);
        canvas.drawCircle(tip, r * 0.16, p);
      }
    case Accessory.flower:
      final fc = Offset(c.dx + r * 0.65, c.dy - r * 0.75);
      p.color = const Color(0xFFF48FB1);
      for (var i = 0; i < 5; i++) {
        final a = i * 2 * pi / 5;
        canvas.drawCircle(fc + Offset(cos(a), sin(a)) * r * 0.18, r * 0.14, p);
      }
      p.color = const Color(0xFFFFEB3B);
      canvas.drawCircle(fc, r * 0.1, p);
    default:
      break;
  }
}

/// 위젯으로 쓰는 치비 초상화
class ChibiPortrait extends StatelessWidget {
  const ChibiPortrait({super.key, required this.style, this.size = 64, this.blink = 1});
  final ChibiStyle style;
  final double size;
  final double blink;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ChibiPainter(style, blink)),
      );
}

class _ChibiPainter extends CustomPainter {
  _ChibiPainter(this.style, this.blink);
  final ChibiStyle style;
  final double blink;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.27;
    paintChibi(canvas, Offset(size.width / 2, size.height * 0.46), r, style,
        blink: blink);
  }

  @override
  bool shouldRepaint(_ChibiPainter old) => old.style != style || old.blink != blink;
}
