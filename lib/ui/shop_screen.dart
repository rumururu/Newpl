import '../game/josa.dart';
import 'package:flutter/material.dart';

import '../game/cosmetics.dart';
import '../game/models.dart';
import '../game/profile.dart';
import '../game/save.dart';
import '../services/app_state.dart';
import '../services/monetization.dart';
import 'chibi.dart';
import 'common.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  bool _busy = false;

  Profile get _p => AppState.profile;

  Future<void> _buy(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await AppState.money.buy(id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) toast(context, '구매 완료! 감사합니다 💜');
  }

  Future<void> _freeGems() async {
    final now = DateTime.now();
    if (AppState.profile.adGemsLeft(now) <= 0) return;
    final ok = await AppState.watchAd();
    if (!mounted) return;
    if (!ok) {
      toast(context, '광고를 불러오는 중이에요. 잠시 후 다시 시도해 주세요.');
      return;
    }
    AppState.profile.claimAdGems(now);
    AppState.play(Sfx.gem);
    await SaveService.saveProfile(AppState.profile);
    if (mounted) setState(() {});
  }

  void _buyCosmetic(int price, VoidCallback give) async {
    final p = AppState.profile;
    if (p.gems < price) {
      toast(context, '젬이 부족해요');
      return;
    }
    if (!await confirmDialog(context, '구매 확인', '${eul("⭐$price")} 사용할까요?')) return;
    p.spendGems(price);
    give();
    p.addStat('cosmetics');
    AppState.play(Sfx.gem);
    await SaveService.saveProfile(p);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = AppState.profile;
    return DefaultTabController(
      length: 5,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0B26),
        appBar: AppBar(
          backgroundColor: const Color(0xFF151236),
          title: const Text('⭐ 상점'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('⭐ ${p.gems}',
                    style: const TextStyle(fontSize: 18, color: Color(0xFFFF80AB))),
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '젬 충전'),
              Tab(text: '패키지'),
              Tab(text: '함선 스킨'),
              Tab(text: '선장 의상'),
              Tab(text: '무료 젬'),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(children: [_gems(), _packs(), _skins(), _outfits(), _free()]),
            if (AppState.money.isTestMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: const Color(0xCC4A148C),
                  padding: const EdgeInsets.all(6),
                  child: const Text('🧪 테스트 모드: 실제 결제/광고가 일어나지 않아요',
                      textAlign: TextAlign.center, style: dimStyle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _productCard(ProductDef d, {Widget? leading, bool owned = false}) => Card(
        color: const Color(0xFF1E1A4A),
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: leading,
          title: Text(d.title, style: titleStyle),
          subtitle: Text(d.desc, style: dimStyle),
          trailing: owned
              ? const Text('보유 중', style: TextStyle(color: Color(0xFF7CFFB2)))
              : actionBtn(AppState.money.priceOf(d.id), !_busy, () => _buy(d.id),
                  color: const Color(0xFFAD1457)),
        ),
      );

  Widget _gems() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final d in productDefs.where((d) => d.id.startsWith('gems_')))
            _productCard(d,
                leading: Text(
                    d.id == 'gems_100' ? '⭐' : (d.id == 'gems_550' ? '💰' : '🎁'),
                    style: const TextStyle(fontSize: 32))),
          const SizedBox(height: 8),
          const Text('젬은 꾸미기, 고급 영입, 즉시 부활, 크레딧 교환에 쓸 수 있어요.\n'
              '게임 플레이(업적·출석·두목·보급 캡슐)로도 모을 수 있어요.', style: dimStyle),
        ],
      );

  Widget _packs() {
    final starter = productDefs.firstWhere((d) => d.id == 'starter_pack');
    final premium = productDefs.firstWhere((d) => d.id == 'premium_pass');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _productCard(starter,
            owned: _p.starterBought,
            leading: _skinPreview(skinById('galaxy'))),
        _productCard(premium,
            owned: _p.premium,
            leading: _skinPreview(skinById('gold'))),
        const SizedBox(height: 12),
        actionBtn('구매 복원', true, () async {
          await AppState.money.restore();
          if (mounted) toast(context, '구매 내역을 확인했어요');
        }, color: const Color(0xFF455A64)),
      ],
    );
  }

  Widget _skinPreview(ShipSkin s, {double size = 48}) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ShipPreviewPainter(s)),
      );

  Widget _skins() {
    final p = AppState.profile;
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
      childAspectRatio: 0.85,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final s in shipSkins)
          _cosmeticCard(
            preview: _skinPreview(s, size: 80),
            name: s.name,
            owned: p.ownedSkins.contains(s.id),
            equipped: p.skin == s.id,
            price: s.price,
            exclusive: s.exclusive,
            onBuy: () => _buyCosmetic(s.price, () => p.ownedSkins.add(s.id)),
            onEquip: () async {
              p.skin = s.id;
              await SaveService.saveProfile(p);
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _outfits() {
    final p = AppState.profile;
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
      childAspectRatio: 0.85,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final o in captainOutfits)
          _cosmeticCard(
            preview: ChibiPortrait(style: ChibiStyle.captainIn(o), size: 90),
            name: o.name,
            owned: p.ownedOutfits.contains(o.id),
            equipped: p.outfit == o.id,
            price: o.price,
            onBuy: () => _buyCosmetic(o.price, () => p.ownedOutfits.add(o.id)),
            onEquip: () async {
              p.outfit = o.id;
              await SaveService.saveProfile(p);
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _cosmeticCard({
    required Widget preview,
    required String name,
    required bool owned,
    required bool equipped,
    required int price,
    String? exclusive,
    required VoidCallback onBuy,
    required VoidCallback onEquip,
  }) {
    Widget button;
    if (equipped) {
      button = const Text('장착 중', style: TextStyle(color: Color(0xFF7CFFB2)));
    } else if (owned) {
      button = actionBtn('장착', true, onEquip, fontSize: 12);
    } else if (exclusive != null) {
      button = Text(exclusive == 'premium_pass' ? '사령관 패스 전용' : '스타터 팩 전용',
          style: dimStyle, textAlign: TextAlign.center);
    } else {
      button = actionBtn('⭐$price', true, onBuy, color: const Color(0xFFAD1457), fontSize: 12);
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A4A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: equipped ? const Color(0xFF7CFFB2) : Colors.white12),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          preview,
          Text(name, style: bodyStyle, textAlign: TextAlign.center),
          button,
        ],
      ),
    );
  }

  Widget _free() {
    final p = AppState.profile;
    final left = p.adGemsLeft(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('📺 광고 보고 무료 젬', style: sectionStyle),
        const SizedBox(height: 6),
        Text('하루 ${3}회, 1회에 ⭐5 · 오늘 $left회 남음', style: bodyStyle),
        const SizedBox(height: 8),
        actionBtn(p.premium ? '⭐5 받기 (사령관 패스: 광고 없음)' : '광고 보고 ⭐5 받기', left > 0, _freeGems,
            color: const Color(0xFF00897B)),
        const Divider(color: Colors.white24, height: 32),
        const Text('📅 출석 보상', style: sectionStyle),
        const SizedBox(height: 6),
        Text('연속 출석 ${p.loginStreak}일째', style: bodyStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < 7; i++)
              Container(
                width: 64,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: i < ((p.loginStreak - 1) % 7 + 1) && p.loginStreak > 0
                      ? const Color(0xFF4527A0)
                      : const Color(0xFF1E1A4A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  Text('${i + 1}일', style: dimStyle),
                  Text('⭐${[5, 5, 10, 10, 15, 20, 50][i]}', style: bodyStyle),
                ]),
              ),
          ],
        ),
      ],
    );
  }
}

class _ShipPreviewPainter extends CustomPainter {
  _ShipPreviewPainter(this.skin);
  final ShipSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final s = size.shortestSide / 60;
    canvas.scale(s);
    final wing = Paint()
      ..shader = skin.rainbow
          ? const SweepGradient(colors: [
              Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.red
            ]).createShader(const Rect.fromLTWH(-26, -26, 52, 52))
          : null
      ..color = skin.wing;
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
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -26, 22, 46), const Radius.circular(11)),
        Paint()..color = skin.hull);
    canvas.drawRect(const Rect.fromLTWH(-11, 8, 22, 4), Paint()..color = skin.stripe);
    canvas.drawCircle(const Offset(0, -8), 9, Paint()..color = const Color(0xFF263238));
    canvas.drawCircle(const Offset(0, -8), 9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xAAB3E5FC));
  }

  @override
  bool shouldRepaint(_ShipPreviewPainter old) => old.skin != skin;
}
