import 'dart:math';

import 'package:flutter/material.dart';

import '../game/cosmetics.dart';
import '../game/home.dart';
import '../game/models.dart';
import '../game/save.dart';
import '../game/world.dart';
import '../services/app_state.dart';
import 'chibi.dart';
import 'common.dart';

/// 내 행성 화면: 행성을 돌려 보며 둘레의 칸에 건물을 짓는다.
class HomePlanetScreen extends StatefulWidget {
  const HomePlanetScreen({super.key});

  @override
  State<HomePlanetScreen> createState() => _HomePlanetScreenState();
}

class _HomePlanetScreenState extends State<HomePlanetScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  double _rot = 0;

  /// 그림과 같은 회전각 (드래그 + 천천히 자동 회전)
  double get _spin => _rot + _anim.value * 60 * 0.03;

  GameWorld? get _w => AppState.world;
  HomePlanet get _home => AppState.profile.home;

  @override
  void dispose() {
    _anim.dispose();
    SaveService.saveProfile(AppState.profile);
    final w = _w;
    if (w != null) SaveService.save(w);
    super.dispose();
  }

  void _act(bool Function() f, {String fail = '자원이 부족해요'}) {
    if (f()) {
      AppState.haptic();
      for (final s in _w?.sfx ?? <Sfx>[]) {
        AppState.play(s);
      }
      _w?.sfx.clear();
      SaveService.saveProfile(AppState.profile);
    } else {
      toast(context, fail);
    }
    setState(() {});
  }

  /// 화면 좌표에서 행성 중심과 반지름
  (Offset, double) _geometry(Size size) {
    // 위(제목·보너스 약 110px)와 아래(버튼 약 130px)를 피해서 배치
    const top = 110.0, bottom = 130.0;
    // 둘레의 칸(반지름 + 26, 크기 ±20)까지 화면 안에 들어오게
    final r = max(80.0, min(size.width / 2 - 56, (size.height - top - bottom) / 2 - 40));
    return (Offset(size.width / 2, top + (size.height - top - bottom) / 2), r);
  }

  double _slotAngle(int i) => _spin + i * 2 * pi / _home.slots.length - pi / 2;

  void _onTap(Offset pos, Size size) {
    final (c, r) = _geometry(size);
    for (var i = 0; i < _home.slots.length; i++) {
      final p = c + OffsetX.fromAngle(_slotAngle(i), r + 26);
      if ((p - pos).distance < 38) {
        _openSlot(i);
        return;
      }
    }
  }

  Future<void> _openSlot(int i) async {
    final w = _w;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final s = _home.slots[i];
        void doAct(bool Function() f) {
          _act(f);
          setSheet(() {});
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                Text(s == null ? '빈 땅 #${i + 1} · 건물 짓기' : '${s.type.icon} ${s.type.label}  Lv.${s.level}',
                    style: titleStyle),
                if (w == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('건설은 게임 중(메뉴 → 내 행성)에 할 수 있어요. 크레딧과 광석은 현재 우주에서 써요.',
                        style: dimStyle),
                  ),
                if (w != null)
                  Text('보유 💰${compact(w.credits)}  💎${compact(w.ore)}  ⭐${AppState.profile.gems}',
                      style: dimStyle),
                const SizedBox(height: 8),
                if (s == null)
                  for (final t in BuildingType.values)
                    _buildRow(t, w, () => doAct(() => w!.buildHome(i, t)))
                else ...[
                  Text('현재 효과: ${s.type.effect(s.level)}', style: bodyStyle),
                  if (s.level < HomeSlot.maxLevel) ...[
                    Text('다음 레벨: ${s.type.effect(s.level + 1)}', style: dimStyle),
                    const SizedBox(height: 10),
                    actionBtn(
                      s.type.gemOnly
                          ? '업그레이드 ⭐${_home.statueGemCost(s.level)}'
                          : '업그레이드 ${costText(_home.upgradeCost(s))}',
                      w != null &&
                          (s.type.gemOnly
                              ? AppState.profile.gems >= _home.statueGemCost(s.level)
                              : w.canAfford(_home.upgradeCost(s))),
                      () => doAct(() => w!.upgradeHome(i)),
                      color: s.type.gemOnly ? const Color(0xFFAD1457) : const Color(0xFF5E35B1),
                    ),
                  ] else
                    const Text('🌟 최대 레벨', style: TextStyle(color: Color(0xFFFFD54F))),
                ],
              ],
            ),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }

  Widget _buildRow(BuildingType t, GameWorld? w, VoidCallback onBuild) {
    final cost = _home.buildCost(t);
    final gem = _home.statueGemCost(0);
    final can = w != null && (t.gemOnly ? AppState.profile.gems >= gem : w.canAfford(cost));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(t.icon, style: const TextStyle(fontSize: 26))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(t.effect(1), style: dimStyle),
              ],
            ),
          ),
          actionBtn(t.gemOnly ? '⭐$gem' : costText(cost), can, onBuild,
              color: t.gemOnly ? const Color(0xFFAD1457) : const Color(0xFF5E35B1), fontSize: 12),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _home.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('행성 이름'),
        content: TextField(controller: ctrl, maxLength: 12, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('확인')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => _home.name = name);
      SaveService.saveProfile(AppState.profile);
    }
  }

  Future<void> _decorate() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanelColor,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final p = AppState.profile;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎨 행성 꾸미기', style: titleStyle),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < homePalettes.length; i++)
                      GestureDetector(
                        onTap: () {
                          final (_, _, _, price) = homePalettes[i];
                          if (!_home.ownedPalettes.contains(i)) {
                            if (!p.spendGems(price)) {
                              toast(context, '젬이 부족해요');
                              return;
                            }
                            _home.ownedPalettes.add(i);
                            p.addStat('cosmetics');
                            AppState.play(Sfx.gem);
                          }
                          _home.palette = i;
                          SaveService.saveProfile(p);
                          setSheet(() {});
                          setState(() {});
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  center: const Alignment(-0.4, -0.4),
                                  colors: [Color(homePalettes[i].$2), Color(homePalettes[i].$3)],
                                ),
                                border: Border.all(
                                    color: _home.palette == i ? const Color(0xFF7CFFB2) : Colors.white24,
                                    width: 3),
                              ),
                            ),
                            Text(homePalettes[i].$1, style: dimStyle),
                            if (!_home.ownedPalettes.contains(i))
                              Text('⭐${homePalettes[i].$4}',
                                  style: const TextStyle(color: Color(0xFFFF80AB), fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('행성 고리'),
                  value: _home.ring,
                  onChanged: (v) {
                    _home.ring = v;
                    SaveService.saveProfile(p);
                    setSheet(() {});
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> _harvest() async {
    final w = _w;
    if (w == null) {
      toast(context, '선물은 게임 중에 받을 수 있어요');
      return;
    }
    final r = w.harvestHome(DateTime.now());
    if (r == null) return;
    for (final s in w.sfx) {
      AppState.play(s);
    }
    w.sfx.clear();
    SaveService.saveProfile(AppState.profile);
    setState(() {});
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('🎁 행성 선물', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChibiPortrait(style: ChibiStyle.advisor, size: 90),
            Text('주민 ${_home.residents}명이 모은 선물이에요!', style: bodyStyle),
            const SizedBox(height: 8),
            Text('💰${r.$1}  ⭐${r.$2}', style: const TextStyle(fontSize: 24, color: Color(0xFFFFD54F))),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('고마워!'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    final now = DateTime.now();
    final ready = _home.harvestReady(now);
    final wait = _home.harvestIn(now);
    return Scaffold(
      backgroundColor: const Color(0xFF070614),
      body: LayoutBuilder(builder: (context, cons) {
        final size = cons.biggest;
        return GestureDetector(
          onTapUp: (d) => _onTap(d.localPosition, size),
          onHorizontalDragUpdate: (d) {
            final (_, r) = _geometry(size);
            setState(() => _rot += d.delta.dx / r);
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) => CustomPaint(
                    painter: _HomePainter(_home, _rot, _anim.value * 60, _geometry(size)),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: _rename,
                            child: Column(
                              children: [
                                Text('🌍 ${_home.name} ✏', style: titleStyle),
                                Text('행성 Lv.${_home.level} · 주민 ${_home.residents}명 · 건물 ${_home.buildingCount}/${_home.slots.length}',
                                    style: dimStyle),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.palette, color: Colors.white),
                          onPressed: _decorate,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: glass(Text(
                        '영구 보너스 · 수입 +${((_home.incomeMul - 1) * 100).round()}%  '
                        '광석 +${((_home.oreMul - 1) * 100).round()}%  '
                        '공격 +${((_home.damageMul - 1) * 100).round()}%  '
                        '체력 +${((_home.hpMul - 1) * 100).round()}%  '
                        '쿨타임 -${((1 - _home.cooldownMul) * 100).round()}%  '
                        '오프라인 ${(_home.offlineEfficiency * 100).round()}%',
                        style: const TextStyle(color: Color(0xFF7CFFB2), fontSize: 12),
                        textAlign: TextAlign.center,
                      )),
                    ),
                    const Spacer(),
                    const Text('행성을 좌우로 밀어 돌리고, 칸을 눌러 건물을 지어요', style: dimStyle),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        actionBtn(ready ? '🎁 행성 선물 받기' : '🎁 ${wait.inHours}시간 ${wait.inMinutes % 60}분 후 선물',
                            ready && w != null, _harvest,
                            color: const Color(0xFF00897B)),
                        if (_home.level < HomePlanet.maxLevel)
                          actionBtn('🌍 행성 Lv.${_home.level + 1} (칸 +2) ${costText(_home.levelUpCost)}',
                              w != null && w.canAfford(_home.levelUpCost),
                              () => _act(() => w!.levelUpHome())),
                      ],
                    ),
                    if (w != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('보유 💰${compact(w.credits)}  💎${compact(w.ore)}', style: dimStyle),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _HomePainter extends CustomPainter {
  _HomePainter(this.home, this.rot, this.t, this.geo);
  final HomePlanet home;
  final double rot;
  final double t;
  final (Offset, double) geo;

  @override
  void paint(Canvas canvas, Size size) {
    final (c, r) = geo;
    final spin = rot + t * 0.03;
    // 하늘
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B0A2A), Color(0xFF241B5A)],
          ).createShader(Offset.zero & size));
    final rnd = Random(5);
    for (var i = 0; i < 120; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final tw = 0.5 + 0.5 * sin(t * 2 + i);
      canvas.drawCircle(p, rnd.nextDouble() * 1.6 + 0.4, Paint()..color = Colors.white.withValues(alpha: 0.3 + 0.5 * tw));
    }

    final (_, light, dark, _) = homePalettes[home.palette];
    // 대기
    canvas.drawCircle(
        c,
        r * 1.18,
        Paint()
          ..shader = RadialGradient(colors: [Color(light).withValues(alpha: 0.35), Color(light).withValues(alpha: 0)],
                  stops: const [0.8, 1])
              .createShader(Rect.fromCircle(center: c, radius: r * 1.18)));
    if (home.ring) _ring(canvas, c, r, back: true);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(center: const Alignment(-0.4, -0.5), colors: [Color(light), Color(dark)])
              .createShader(Rect.fromCircle(center: c, radius: r)));
    // 지형 무늬 (같이 회전)
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final mr = Random(home.palette * 31 + 7);
    for (var i = 0; i < 9; i++) {
      final a = spin + mr.nextDouble() * 2 * pi;
      final d = r * (0.2 + mr.nextDouble() * 0.6);
      canvas.drawCircle(c + OffsetX.fromAngle(a, d), r * (0.08 + mr.nextDouble() * 0.15),
          Paint()..color = Color(dark).withValues(alpha: 0.3));
    }
    canvas.restore();
    if (home.ring) _ring(canvas, c, r, back: false);

    // 칸과 건물
    final n = home.slots.length;
    for (var i = 0; i < n; i++) {
      final a = spin + i * 2 * pi / n - pi / 2;
      final base = c + OffsetX.fromAngle(a, r);
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(a + pi / 2);
      final s = home.slots[i];
      if (s == null) {
        _emptySlot(canvas);
      } else {
        _building(canvas, s);
      }
      canvas.restore();
    }

    // 주민 (행성 위를 걸어다님)
    for (var i = 0; i < min(home.residents, 30); i++) {
      final speed = 0.05 + (i % 5) * 0.02;
      final a = spin + i * 2.399 + t * speed * (i.isEven ? 1 : -1);
      final hop = (sin(t * 6 + i) * 1.5).abs();
      final p = c + OffsetX.fromAngle(a, r + 14 + hop);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a + pi / 2);
      paintChibi(canvas, const Offset(0, -6), 7, _residentStyle(i));
      canvas.restore();
    }
  }

  ChibiStyle _residentStyle(int i) {
    const hairs = [0xFF5D4037, 0xFFFFD54F, 0xFFEC407A, 0xFF42A5F5, 0xFF212121, 0xFF66BB6A];
    const suits = [0xFFFF7043, 0xFF26A69A, 0xFF7E57C2, 0xFFFFCA28, 0xFF29B6F6];
    const acc = [Accessory.none, Accessory.catEars, Accessory.none, Accessory.flower, Accessory.bunnyEars];
    return ChibiStyle(
      skin: const Color(0xFFFFE0C7),
      hair: Color(hairs[i % hairs.length]),
      suit: Color(suits[i % suits.length]),
      eye: const Color(0xFF263238),
      accessory: acc[i % acc.length],
    );
  }

  void _ring(Canvas canvas, Offset c, double r, {required bool back}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.3);
    final rect = Rect.fromCenter(center: Offset.zero, width: r * 2.9, height: r * 0.7);
    canvas.drawArc(rect, back ? pi : 0, pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06
          ..color = const Color(0xCCFFE082));
    canvas.restore();
  }

  void _emptySlot(Canvas canvas) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white54;
    canvas.drawCircle(const Offset(0, -26), 18, p);
    canvas.drawLine(const Offset(-7, -26), const Offset(7, -26), p);
    canvas.drawLine(const Offset(0, -33), const Offset(0, -19), p);
  }

  void _building(Canvas canvas, HomeSlot s) {
    final k = 1 + s.level * 0.1;
    canvas.save();
    canvas.scale(k);
    final fill = Paint();
    switch (s.type) {
      case BuildingType.house:
        fill.color = const Color(0xFFFFF3E0);
        canvas.drawRect(const Rect.fromLTWH(-14, -22, 28, 22), fill);
        fill.color = const Color(0xFFE53935);
        canvas.drawPath(Path()..moveTo(-18, -22)..lineTo(0, -38)..lineTo(18, -22)..close(), fill);
        fill.color = const Color(0xFF4FC3F7);
        canvas.drawRect(const Rect.fromLTWH(-9, -16, 7, 7), fill);
        fill.color = const Color(0xFF8D6E63);
        canvas.drawRect(const Rect.fromLTWH(3, -12, 7, 12), fill);
      case BuildingType.farm:
        fill.color = const Color(0xFF8D6E63);
        canvas.drawRect(const Rect.fromLTWH(-22, -8, 44, 8), fill);
        fill.color = const Color(0xFF9CCC65);
        for (var x = -18; x <= 18; x += 9) {
          canvas.drawOval(Rect.fromCenter(center: Offset(x.toDouble(), -14), width: 6, height: 14), fill);
        }
        fill.color = const Color(0x88B3E5FC);
        canvas.drawArc(const Rect.fromLTWH(-24, -34, 48, 52), pi, pi, true, fill);
      case BuildingType.mine:
        fill.color = const Color(0xFF616161);
        canvas.drawPath(Path()..moveTo(-16, 0)..lineTo(0, -40)..lineTo(16, 0)..close(), fill);
        fill.color = const Color(0xFFFFB300);
        canvas.drawCircle(const Offset(0, -20), 6, fill);
        fill.color = const Color(0xFF4DD0E1);
        canvas.drawCircle(const Offset(-10, -4), 4, fill);
        canvas.drawCircle(const Offset(10, -4), 3, fill);
      case BuildingType.lab:
        fill.color = const Color(0xFFECEFF1);
        canvas.drawArc(const Rect.fromLTWH(-18, -30, 36, 60), pi, pi, true, fill);
        fill.color = const Color(0xFF7E57C2);
        canvas.drawRect(const Rect.fromLTWH(-1.5, -44, 3, 16), fill);
        canvas.drawCircle(const Offset(0, -46), 4, fill..color = const Color(0xFF69F0AE));
        fill.color = const Color(0xFF4FC3F7);
        canvas.drawCircle(const Offset(-6, -12), 4, fill);
        canvas.drawCircle(const Offset(7, -16), 4, fill);
      case BuildingType.tower:
        fill.color = const Color(0xFF90A4AE);
        canvas.drawRect(const Rect.fromLTWH(-8, -42, 16, 42), fill);
        fill.color = const Color(0xFF455A64);
        canvas.drawCircle(const Offset(0, -44), 10, fill);
        fill.color = const Color(0xFFE53935);
        canvas.drawRect(const Rect.fromLTWH(-2, -60, 4, 16), fill);
      case BuildingType.shipyard:
        final line = Paint()
          ..color = const Color(0xFFFFB300)
          ..strokeWidth = 3;
        canvas.drawLine(const Offset(-16, 0), const Offset(-16, -44), line);
        canvas.drawLine(const Offset(-16, -44), const Offset(10, -44), line);
        canvas.drawLine(const Offset(6, -44), const Offset(6, -34), line..strokeWidth = 1.5);
        fill.color = const Color(0xFFECEFF1);
        canvas.drawRRect(
            RRect.fromRectAndRadius(const Rect.fromLTWH(0, -30, 12, 30), const Radius.circular(6)), fill);
        fill.color = const Color(0xFFE53935);
        canvas.drawPath(Path()..moveTo(0, -4)..lineTo(-5, 0)..lineTo(0, 0)..close(), fill);
      case BuildingType.park:
        final spokes = Paint()
          ..color = Colors.white70
          ..strokeWidth = 1.5;
        const cc = Offset(0, -26);
        canvas.drawLine(const Offset(-10, 0), cc, spokes);
        canvas.drawLine(const Offset(10, 0), cc, spokes);
        canvas.save();
        canvas.translate(cc.dx, cc.dy);
        canvas.rotate(t * 0.8);
        for (var i = 0; i < 8; i++) {
          final p = OffsetX.fromAngle(i * pi / 4, 20);
          canvas.drawLine(Offset.zero, p, spokes);
          canvas.drawCircle(p, 4, Paint()..color = HSVColor.fromAHSV(1, i * 45.0, 0.6, 1).toColor());
        }
        canvas.restore();
        canvas.drawCircle(cc, 20, Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white54);
      case BuildingType.statue:
        fill.color = const Color(0xFFBCAAA4);
        canvas.drawRect(const Rect.fromLTWH(-12, -10, 24, 10), fill);
        canvas.save();
        canvas.translate(0, -30);
        paintChibi(canvas, Offset.zero, 11,
            ChibiStyle.captain.copyWith(
                hair: const Color(0xFFFFC107), suit: const Color(0xFFFFB300), helmet: false, accessory: Accessory.crown));
        canvas.restore();
    }
    canvas.restore();
    // 레벨 별
    final tp = TextPainter(
      text: TextSpan(
          text: '★' * s.level,
          style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 9, fontFamily: 'Jua')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, 4));
  }

  @override
  bool shouldRepaint(_HomePainter old) => true;
}
