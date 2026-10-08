# 🚀 STAR SETTLERS · 우주 개척단

머리 큰 치비 선장이 되어 우주를 누비며 해적과 싸우고, 행성을 개척하고, 우주정거장을 키우는 Flutter 모바일 게임입니다.
그래픽은 전부 코드(`CustomPainter`)로 그리고 사운드도 직접 합성해서, 외부 에셋 없이 동작합니다.

- 📄 기획서: [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)
- 🏪 출시 가이드: [docs/STORE_RELEASE.md](docs/STORE_RELEASE.md) · 등록 문구: [docs/STORE_LISTING.md](docs/STORE_LISTING.md) · [개인정보처리방침](docs/PRIVACY_POLICY.md)

## 주요 기능
| 분류 | 내용 |
|---|---|
| 전투 | 조준 보정 사격, 유도 미사일, 에너지 실드, 부스트, 화면 흔들림, 데미지 숫자 |
| 적 | 정찰선, 습격선, 자폭선, 저격선, 해적 두목, 섹터 두목, 현상수배범, 우주 해파리 |
| 개척 | 행성 5종 정착(Lv.1~5), 정거장 건설(거주구역/방어포탑), 광석 시장 |
| 섹터 | 워프 게이트로 무한 섹터 탐험, 섹터별 난이도·보상 상승, 다른 섹터 수입 합산 |
| 승무원 | 6개 직업, ★1~3 희귀도, 레벨업, 배치 슬롯, 랜덤 치비 외형, 확률 공개 |
| 임무 | 튜토리얼 겸 스토리 챕터, 임무 게시판(소탕/채굴/운송/현상수배) |
| 이벤트 | 식민지 습격, 유성우, 떠돌이 상인, 보급 캡슐 |
| 성장/리텐션 | 오프라인 수입, 출석 보상, 일일 퀘스트, 업적 20종, 파워업, 은하 명예(환생), 복귀 알림 |
| 함선 | 격납고 5종(스카우트/인터셉터/포트리스/프로스펙터/팬텀), 전투 드론 |
| 수익화 | 스타젬, 인앱 상품 5종, 보상형 광고 3곳, 함선 스킨 8종, 선장 의상 7종 |
| 기타 | 효과음 14종 + BGM, 주아 폰트, 튜토리얼 안내 화살표, 두목 2페이즈, 설정, 자동 저장, 키보드/터치 동시 지원 |
| 출시 | AdMob 보상형 광고, 인앱결제, 릴리즈 서명 설정, CI(테스트 + APK 빌드) |

## 조작
| 동작 | 모바일 | 키보드 |
|---|---|---|
| 이동 | 왼쪽 조이스틱 | WASD / 방향키 |
| 사격 | 발사 버튼 (자동 모드: 360° 자동 조준) | Space |
| 미사일 / 실드 / 부스트 | 🚀 / 🛡 / 💨 버튼 | Q / F / Shift |
| 상호작용 (정착, 정거장, 상인, 워프) | 화면 버튼 | E |
| 정거장 건설 | 화면 버튼 | B |
| 메뉴 | ☰ | Esc |

## 실행
```bash
flutter pub get
flutter run            # 연결된 기기
flutter run -d chrome  # 웹
flutter test           # 단위 테스트 + 밸런스 봇 시뮬레이션
```
디버그/웹에서는 결제와 광고가 **테스트 모드**(확인창)로 동작합니다.

## 에셋 재생성
```bash
python3 tool/gen_sounds.py               # 효과음/BGM 합성 → assets/audio
flutter test tool/gen_icon_test.dart     # 앱 아이콘 렌더링 → assets/icon
python3 tool/gen_platform_icons.py       # 안드로이드/iOS/웹 아이콘 크기별 생성
```

## 구조
```
lib/
  main.dart                  타이틀, 출석 보상
  game/                      순수 Dart 게임 로직 (UI와 분리, 테스트 가능)
    world.dart               월드 시뮬레이션: 전투, 섹터, 이벤트, 임무, 저장
    models.dart              엔티티
    crew.dart                승무원
    missions.dart            임무, 스토리 챕터
    profile.dart             계정 데이터: 젬, 업적, 출석, 설정
    cosmetics.dart           스킨, 의상
    save.dart                저장/불러오기
  services/
    app_state.dart           전역 상태, 결제 상품 지급
    monetization.dart        결제/광고 추상화 (Dev / in_app_purchase)
    audio.dart               효과음/BGM
  ui/
    game_screen.dart         게임 루프, HUD, 스킬 버튼, 부활, 오프라인 수입
    world_painter.dart       우주 렌더링, 미니맵
    chibi.dart               치비 캐릭터 페인터 (액세서리 포함)
    station_panel.dart       정거장 메뉴 (함선/정거장/승무원/임무/시장)
    merchant_panel.dart      떠돌이 상인
    shop_screen.dart         상점
    meta_screens.dart        업적, 설정
```
