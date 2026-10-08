import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob 보상형 광고.
/// 기본값은 구글 공식 **테스트 광고 단위**이고, 출시 빌드에서는
/// `--dart-define=ADMOB_REWARDED_ANDROID=...` / `ADMOB_REWARDED_IOS=...` 로 실제 ID를 넣는다.
class AdService {
  AdService._();
  static final instance = AdService._();

  static const _androidUnit = String.fromEnvironment('ADMOB_REWARDED_ANDROID',
      defaultValue: 'ca-app-pub-3940256099942544/5224354917');
  static const _iosUnit = String.fromEnvironment('ADMOB_REWARDED_IOS',
      defaultValue: 'ca-app-pub-3940256099942544/1712485313');

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  RewardedAd? _ad;
  bool _loading = false;
  bool _initialized = false;

  String get _unitId => Platform.isAndroid ? _androidUnit : _iosUnit;

  Future<void> init() async {
    if (!supported || _initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      _preload();
    } catch (e) {
      debugPrint('AdMob init failed: $e');
    }
  }

  void _preload() {
    if (!_initialized || _loading || _ad != null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: _unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (e) {
          debugPrint('rewarded load failed: $e');
          _loading = false;
          // 잠시 후 재시도
          Future.delayed(const Duration(seconds: 30), _preload);
        },
      ),
    );
  }

  bool get ready => _ad != null;

  /// 광고를 끝까지 봐서 보상을 받으면 true
  Future<bool> showRewarded() async {
    if (!supported) return false;
    if (!_initialized) await init();
    final ad = _ad;
    if (ad == null) {
      _preload();
      return false;
    }
    _ad = null;
    final done = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete(earned);
        _preload();
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        ad.dispose();
        if (!done.isCompleted) done.complete(false);
        _preload();
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return done.future;
  }
}
