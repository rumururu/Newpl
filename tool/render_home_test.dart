// 내 행성 화면 미리보기 렌더링: flutter test tool/render_home_test.dart --update-goldens
// 모든 건물을 지은 상태를 그려 tool/out/home_preview.png 로 저장 (글자는 테스트 폰트라 네모로 보임)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_settlers/game/home.dart';
import 'package:star_settlers/services/app_state.dart';
import 'package:star_settlers/ui/home_screen.dart';

void main() {
  testWidgets('home preview', (tester) async {
    final h = AppState.profile.home
      ..level = 4
      ..ring = true
      ..palette = 5;
    h.slots
      ..clear()
      ..addAll([
        for (var i = 0; i < 10; i++)
          i == 9 ? null : HomeSlot(BuildingType.values[i % BuildingType.values.length], 1 + i % 5),
      ]);
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: HomePlanetScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(HomePlanetScreen), matchesGoldenFile('out/home_preview.png'));
  });
}
