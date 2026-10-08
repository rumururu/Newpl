import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// 인앱 상품 정의 (스토어 콘솔에 같은 ID로 등록해야 함)
class ProductDef {
  const ProductDef(this.id, this.title, this.desc, this.fallbackPrice,
      {this.consumable = true});
  final String id;
  final String title;
  final String desc;
  final String fallbackPrice;
  final bool consumable;
}

const productDefs = [
  ProductDef('gems_100', '젬 한 줌', '⭐100', '₩1,200'),
  ProductDef('gems_550', '젬 주머니', '⭐550 (+10% 보너스)', '₩5,900'),
  ProductDef('gems_1200', '젬 상자', '⭐1200 (+20% 보너스)', '₩12,000'),
  ProductDef('starter_pack', '스타터 팩', '⭐300 + 전용 스킨 "갤럭시" + ★3 승무원 (1회 한정)', '₩3,900',
      consumable: false),
  ProductDef('premium_pass', '함대 사령관 패스', '크레딧 수입 +25%, 오프라인 수입 8시간, 광고 없이 보상, 전용 스킨 "골드 로열"',
      '₩6,500', consumable: false),
];

/// 결제/광고 추상화.
/// - 개발/웹: [DevMonetization] (테스트 확인창)
/// - 출시: [StoreMonetization] (in_app_purchase). 보상형 광고 SDK는 docs/STORE_RELEASE.md 참고
abstract class MonetizationService {
  /// 결제 성공 시 호출 (상품 지급은 앱에서 처리)
  void Function(String productId)? onGrant;

  /// 개발 모드 확인창 (UI가 주입)
  Future<bool> Function(String title, String body)? confirm;

  Future<void> init();
  String priceOf(String productId);
  Future<bool> buy(String productId);
  Future<void> restore();

  /// 보상형 광고. 끝까지 보면 true
  Future<bool> showRewardedAd();

  bool get isTestMode;

  static MonetizationService create() =>
      (!kIsWeb && kReleaseMode) ? StoreMonetization() : DevMonetization();
}

class DevMonetization extends MonetizationService {
  @override
  bool get isTestMode => true;

  @override
  Future<void> init() async {}

  @override
  String priceOf(String productId) =>
      productDefs.firstWhere((p) => p.id == productId).fallbackPrice;

  @override
  Future<bool> buy(String productId) async {
    final def = productDefs.firstWhere((p) => p.id == productId);
    final ok = await (confirm?.call('[테스트 결제] ${def.title}',
            '실제 결제는 일어나지 않아요.\n${def.desc}\n가격: ${def.fallbackPrice}') ??
        Future.value(false));
    if (ok) onGrant?.call(productId);
    return ok;
  }

  @override
  Future<void> restore() async {}

  @override
  Future<bool> showRewardedAd() async =>
      await (confirm?.call('[테스트 광고]', '광고를 끝까지 본 것으로 처리할까요?') ??
          Future.value(false));
}

class StoreMonetization extends MonetizationService {
  final _iap = InAppPurchase.instance;
  final _products = <String, ProductDetails>{};
  final _pending = <String, Completer<bool>>{};
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _available = false;

  @override
  bool get isTestMode => false;

  @override
  Future<void> init() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
        debugPrint('purchase stream error: $e');
      });
      final res = await _iap.queryProductDetails(productDefs.map((p) => p.id).toSet());
      for (final p in res.productDetails) {
        _products[p.id] = p;
      }
    } catch (e) {
      debugPrint('IAP init failed: $e');
      _available = false;
    }
  }

  @override
  String priceOf(String productId) =>
      _products[productId]?.price ??
      productDefs.firstWhere((p) => p.id == productId).fallbackPrice;

  @override
  Future<bool> buy(String productId) async {
    final details = _products[productId];
    if (!_available || details == null) return false;
    final def = productDefs.firstWhere((p) => p.id == productId);
    final c = Completer<bool>();
    _pending[productId] = c;
    final param = PurchaseParam(productDetails: details);
    final started = def.consumable
        ? await _iap.buyConsumable(purchaseParam: param)
        : await _iap.buyNonConsumable(purchaseParam: param);
    if (!started) {
      _pending.remove(productId);
      return false;
    }
    return c.future.timeout(const Duration(minutes: 5), onTimeout: () => false);
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // TODO(출시 전): 서버에서 영수증 검증 후 지급
          onGrant?.call(p.productID);
          _pending.remove(p.productID)?.complete(true);
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          _pending.remove(p.productID)?.complete(false);
        case PurchaseStatus.pending:
          break;
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  @override
  Future<void> restore() async {
    if (_available) await _iap.restorePurchases();
  }

  @override
  Future<bool> showRewardedAd() async {
    // TODO(출시 전): google_mobile_ads 의 RewardedAd 로 교체 (docs/STORE_RELEASE.md)
    return await (confirm?.call('광고', '보상형 광고 준비 중이에요. 보상을 받을까요?') ??
        Future.value(false));
  }

  void dispose() => _sub?.cancel();
}
