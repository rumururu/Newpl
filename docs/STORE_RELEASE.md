# 스토어 출시 가이드

현재 코드에 이미 들어 있는 것과, 출시 전에 직접 해야 하는 일을 정리했습니다.

## 1. 지금 준비된 것
| 항목 | 위치 |
|---|---|
| 패키지 ID `com.newpl.star_settlers` | `android/app/build.gradle.kts` |
| 앱 이름 "우주 개척단" | AndroidManifest, iOS Info.plist, web |
| 앱 아이콘 (치비 선장) | `assets/icon/`, 생성 스크립트 `tool/gen_icon_test.dart`, `tool/gen_platform_icons.py` |
| 인앱결제 연동 코드 | `lib/services/monetization.dart` (`StoreMonetization`, `in_app_purchase`) |
| 상품 지급 로직 | `lib/services/app_state.dart` → `AppState.grant()` |
| 확률 공개 (승무원 영입) | 정거장 → 승무원 탭에 상시 표기 |
| 개인정보처리방침 초안 | `docs/PRIVACY_POLICY.md` (게임 설정 화면에도 요약 표시) |
| 스토어 등록 문구 | `docs/STORE_LISTING.md` |

디버그 빌드와 웹에서는 `DevMonetization`(테스트 확인창)으로 동작하고, **안드로이드/iOS 릴리즈 빌드에서는 자동으로 실제 결제(`StoreMonetization`)** 를 사용합니다.

## 2. 인앱 상품 등록 (Play Console / App Store Connect)
아래 ID를 **정확히 같게** 등록하세요.

| 상품 ID | 유형 | 권장 가격 |
|---|---|---|
| `gems_100` | 소모성 | ₩1,200 |
| `gems_550` | 소모성 | ₩5,900 |
| `gems_1200` | 소모성 | ₩12,000 |
| `starter_pack` | 비소모성 | ₩3,900 |
| `premium_pass` | 비소모성 | ₩6,500 |

> ⚠️ 출시 전에 **영수증 서버 검증**을 추가하는 것을 권장합니다 (`StoreMonetization._onPurchases`의 TODO 참고). Firebase Functions 등으로 구현할 수 있습니다.

## 3. 보상형 광고 (AdMob) 연동
현재 `StoreMonetization.showRewardedAd()`는 임시 확인창입니다. 출시 전에 다음 순서로 교체하세요.

1. AdMob에서 앱을 등록하고 **앱 ID**와 **보상형 광고 단위 ID**를 발급받습니다.
2. `flutter pub add google_mobile_ads`
3. Android `AndroidManifest.xml`의 `<application>` 안에 추가합니다.
   ```xml
   <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
              android:value="ca-app-pub-XXXXXXXX~YYYYYYYY"/>
   ```
4. iOS `Info.plist`에 `GADApplicationIdentifier`와 `SKAdNetworkItems`를 추가합니다.
5. `showRewardedAd()`를 아래처럼 교체합니다.
   ```dart
   @override
   Future<bool> showRewardedAd() async {
     final done = Completer<bool>();
     await RewardedAd.load(
       adUnitId: 'ca-app-pub-XXXX/YYYY',
       request: const AdRequest(),
       rewardedAdLoadCallback: RewardedAdLoadCallback(
         onAdLoaded: (ad) {
           var earned = false;
           ad.fullScreenContentCallback = FullScreenContentCallback(
             onAdDismissedFullScreenContent: (ad) { ad.dispose(); done.complete(earned); },
             onAdFailedToShowFullScreenContent: (ad, e) { ad.dispose(); done.complete(false); },
           );
           ad.show(onUserEarnedReward: (_, __) => earned = true);
         },
         onAdFailedToLoad: (e) => done.complete(false),
       ),
     );
     return done.future;
   }
   ```
6. `main()`에서 `MobileAds.instance.initialize()`를 호출합니다.
7. 아동 대상 설정, GDPR/UMP 동의 메시지를 AdMob 콘솔에서 구성합니다.

## 4. 안드로이드 릴리즈 빌드
```bash
# 1) 업로드 키 생성 (한 번만, 안전한 곳에 백업!)
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# 2) android/key.properties 작성 (git에 올리지 마세요)
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/절대경로/upload-keystore.jks
```
`android/app/build.gradle.kts`의 `buildTypes.release`에 `signingConfig`를 연결한 뒤 빌드합니다.
```bash
flutter build appbundle --release
# 결과물: build/app/outputs/bundle/release/app-release.aab → Play Console 업로드
```

## 5. iOS 릴리즈 빌드
1. Xcode에서 `ios/Runner.xcworkspace`를 열고 Team과 Bundle ID를 설정합니다.
2. Capabilities에 **In-App Purchase**를 추가합니다.
3. `flutter build ipa --release`로 빌드한 뒤 Transporter나 Xcode로 업로드합니다.

## 6. 스토어 심사 체크리스트
- [ ] 개인정보처리방침 URL (GitHub Pages 등에 `docs/PRIVACY_POLICY.md` 게시)
- [ ] 데이터 보안 양식(Play): 기기 내 저장만, 광고 ID(AdMob 사용 시)
- [ ] 콘텐츠 등급 설문: 만화풍 폭력(우주선 전투), 인앱 구매, 광고
- [ ] 확률형 아이템 표시: 승무원 영입 확률이 게임 안에 공개되어 있음
- [ ] 스크린샷: 휴대폰 최소 2장 (`screenshots/` 참고), 태블릿 권장
- [ ] 512x512 아이콘: `web/icons/Icon-512.png`, 1024 원본: `assets/icon/icon.png`
- [ ] 그래픽 이미지(Play) 1024x500
- [ ] 실기기 테스트: 저사양 안드로이드 프레임 확인, 결제 테스트 계정으로 구매·복원 확인

## 7. 출시 후 개선 아이디어
- 클라우드 저장(Google Play Games / Game Center)
- 리더보드: 제국 가치, 최고 섹터
- 시즌 이벤트와 시즌 패스
- 영어/일본어 현지화
