// 앱 아이콘 생성기: flutter test tool/gen_icon_test.dart
// 게임과 같은 치비 페인터로 1024x1024 아이콘을 그려 assets/icon/ 에 저장한다.
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_settlers/ui/chibi.dart';

void paintIcon(Canvas canvas, double s, {bool foregroundOnly = false}) {
  if (!foregroundOnly) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s, s),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.9,
          colors: [Color(0xFF3C2A8C), Color(0xFF0B0820)],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );
    final r = Random(3);
    for (var i = 0; i < 70; i++) {
      canvas.drawCircle(Offset(r.nextDouble() * s, r.nextDouble() * s), r.nextDouble() * s * 0.006 + 1,
          Paint()..color = Colors.white.withValues(alpha: 0.4 + r.nextDouble() * 0.5));
    }
    // 행성 고리
    canvas.save();
    canvas.translate(s * 0.5, s * 0.62);
    canvas.rotate(-0.25);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 0.95, height: s * 0.22),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.03
          ..color = const Color(0xFFFFD54F));
    canvas.restore();
  }
  paintChibi(canvas, Offset(s * 0.5, s * 0.43), s * 0.25, ChibiStyle.captain);
}

Future<void> render(String path, double size, {bool fg = false}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  if (fg) {
    // 안드로이드 적응형 아이콘 전경: 안전 영역(66%) 안에 맞춘다
    canvas.translate(size * 0.17, size * 0.17);
    canvas.scale(0.66);
  }
  paintIcon(canvas, size, foregroundOnly: fg);
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  testWidgets('generate icon', (tester) async {
    await tester.runAsync(() async {
      await render('assets/icon/icon.png', 1024);
      await render('assets/icon/icon_fg.png', 1024, fg: true);
    });
  });
}
