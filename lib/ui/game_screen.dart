import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/models.dart';
import '../game/save.dart';
import '../game/world.dart';
import 'chibi.dart';
import 'world_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.world});
  final GameWorld world;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _FrameNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final _frame = _FrameNotifier();
  final _input = InputState();
  final _focus = FocusNode();
  Duration _last = Duration.zero;
  double _saveTimer = 0;

  Offset _stick = Offset.zero;
  bool _touchFire = false;
  bool _autoFire = false;
  bool _panelOpen = false;
  bool _menuOpen = false;

  GameWorld get w => widget.world;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    SaveService.save(w);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) SaveService.save(w);
  }

  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    bool k(LogicalKeyboardKey a, LogicalKeyboardKey b) =>
        keys.contains(a) || keys.contains(b);
    var kb = Offset(
      (k(LogicalKeyboardKey.keyD, LogicalKeyboardKey.arrowRight) ? 1 : 0) -
          (k(LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft) ? 1.0 : 0),
      (k(LogicalKeyboardKey.keyS, LogicalKeyboardKey.arrowDown) ? 1 : 0) -
          (k(LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp) ? 1.0 : 0),
    );
    if (kb != Offset.zero) kb = kb.normalized();
    _input.move = kb != Offset.zero ? kb : _stick;
    _input.fire = _touchFire ||
        keys.contains(LogicalKeyboardKey.space) ||
        (_autoFire && _pirateInRange());

    w.paused = _panelOpen || _menuOpen;
    w.update(dt, _input);

    _saveTimer += dt;
    if (_saveTimer > 20) {
      _saveTimer = 0;
      SaveService.save(w);
    }
    _frame.tick();
  }

  bool _pirateInRange() =>
      w.pirates.any((e) => (e.pos - w.player.pos).distance < 520);

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent) {
      if (e.logicalKey == LogicalKeyboardKey.keyE) {
        _interact();
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.keyB) {
        _act(w.buildStation);
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          if (_panelOpen) {
            _panelOpen = false;
          } else {
            _menuOpen = !_menuOpen;
          }
        });
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _interact() {
    if (w.nearbyStation != null) {
      setState(() => _panelOpen = !_panelOpen);
    } else if (w.nearbyPlanet != null) {
      _act(() => w.upgradePlanet(w.nearbyPlanet!));
    }
  }

  void _act(bool Function() f) {
    if (f()) {
      HapticFeedback.lightImpact();
      SaveService.save(w);
    } else {
      w.say(Speaker.advisor, '자원이 부족하거나 지금은 할 수 없어요.');
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final zoom = (size.shortestSide / 750).clamp(0.55, 1.1);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: WorldPainter(w, zoom, repaint: _frame)),
            ),
            Positioned.fill(
              child: ListenableBuilder(
                listenable: _frame,
                builder: (context, _) => _hud(context),
              ),
            ),
            if (_panelOpen && w.nearbyStation != null)
              Positioned.fill(child: _stationPanel(w.nearbyStation!)),
            if (_menuOpen) Positioned.fill(child: _pauseMenu()),
          ],
        ),
      ),
    );
  }

  // ---------------- HUD ----------------
  Widget _hud(BuildContext context) {
    final p = w.player;
    return SafeArea(
      child: Stack(
        children: [
          // 상단 좌측: 선장 정보
          Positioned(
            left: 8,
            top: 8,
            child: _glass(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ChibiPortrait(style: ChibiStyle.captain, size: 54),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _hpBar(p.hp / w.playerMaxHp),
                      const SizedBox(height: 4),
                      _res('💰', w.credits, w.creditIncome),
                      _res('💎', w.ore, w.oreIncome),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 상단 우측: 미니맵
          Positioned(
            right: 8,
            top: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _glass(Text(
                      '⚠ 위협 ${w.threat.toStringAsFixed(1)}  🏛 ${w.empireValue}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    )),
                    const SizedBox(width: 6),
                    _iconBtn(Icons.pause, () => setState(() => _menuOpen = true)),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(painter: MinimapPainter(w, repaint: _frame)),
                ),
              ],
            ),
          ),
          // 대사
          if (w.dialogs.isNotEmpty)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(child: _dialog(w.dialogs.last)),
            ),
          if (!p.alive)
            Center(
              child: _glass(Text(
                '💥 격추당했습니다!\n${max(0, p.respawnTimer).toStringAsFixed(1)}초 후 재출격',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              )),
            ),
          // 하단 좌측: 조이스틱
          Positioned(left: 20, bottom: 20, child: _joystick()),
          // 하단 우측: 사격
          Positioned(right: 20, bottom: 20, child: _fireButton()),
          // 하단 중앙: 상황별 행동
          Positioned(
            left: 8,
            right: 8,
            bottom: 160,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _contextActions(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _contextActions() {
    final out = <Widget>[];
    final st = w.nearbyStation;
    final pl = w.nearbyPlanet;
    if (st != null) {
      out.add(_actionBtn('🛠 ${st.name} 메뉴 (E)', true,
          () => setState(() => _panelOpen = true)));
    }
    if (pl != null) {
      if (pl.colonyLevel >= Planet.maxLevel) {
        out.add(_actionBtn('🌟 ${pl.name} 최대 레벨', false, null));
      } else {
        final c = pl.nextCost;
        final label = pl.colonyLevel == 0
            ? '🚩 ${pl.name} 정착 ${_cost(c)} (E)'
            : '⬆ ${pl.name} Lv.${pl.colonyLevel + 1} ${_cost(c)} (E)';
        out.add(_actionBtn(label, w.canAfford(c), () => _act(() => w.upgradePlanet(pl))));
      }
      out.add(_glass(Text(
        '${pl.kindLabel} · 레벨당 💰${pl.ratePerLevel.$1}/s'
        '${pl.ratePerLevel.$2 > 0 ? ' 💎${pl.ratePerLevel.$2}/s' : ''}',
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      )));
    }
    if (w.canBuildStationHere) {
      final c = w.stationBuildCost;
      out.add(_actionBtn('🏗 정거장 건설 ${_cost(c)} (B)', w.canAfford(c),
          () => _act(w.buildStation)));
    }
    return out;
  }

  String _cost((int, int) c) => c.$2 > 0 ? '💰${c.$1} 💎${c.$2}' : '💰${c.$1}';

  Widget _joystick() {
    const radius = 60.0;
    return Listener(
      onPointerDown: (e) => _updateStick(e.localPosition, radius),
      onPointerMove: (e) => _updateStick(e.localPosition, radius),
      onPointerUp: (_) => _stick = Offset.zero,
      onPointerCancel: (_) => _stick = Offset.zero,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Center(
          child: Transform.translate(
            offset: _stick * (radius - 20),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF42A5F5).withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateStick(Offset local, double radius) {
    _stick = ((local - Offset(radius, radius)) / (radius - 20)).clampLength(1);
  }

  Widget _fireButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _autoFire = !_autoFire),
          child: _glass(Text(_autoFire ? '자동사격 ON' : '자동사격 OFF',
              style: TextStyle(
                  color: _autoFire ? const Color(0xFF7CFFB2) : Colors.white60,
                  fontSize: 12))),
        ),
        const SizedBox(height: 10),
        Listener(
          onPointerDown: (_) => _touchFire = true,
          onPointerUp: (_) => _touchFire = false,
          onPointerCancel: (_) => _touchFire = false,
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (_touchFire ? const Color(0xFFFF5252) : const Color(0xFFE53935))
                  .withValues(alpha: 0.55),
              border: Border.all(color: Colors.white38, width: 2),
            ),
            child: const Center(
              child: Text('발사', style: TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dialog(DialogLine d) {
    final name = switch (d.speaker) {
      Speaker.captain => '선장',
      Speaker.pirate => '해적',
      Speaker.advisor => '부관 미나',
    };
    return Opacity(
      opacity: d.time.clamp(0.0, 0.5) * 2,
      child: _glass(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChibiPortrait(style: ChibiStyle.of(d.speaker), size: 48),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: TextStyle(
                            color: d.speaker == Speaker.pirate
                                ? const Color(0xFFFF8A80)
                                : const Color(0xFF8AD8FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    Text(d.text,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hpBar(double f) => SizedBox(
        width: 120,
        height: 10,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: f.clamp(0, 1),
            backgroundColor: Colors.black45,
            color: f > 0.35 ? const Color(0xFF66BB6A) : const Color(0xFFFF5252),
          ),
        ),
      );

  Widget _res(String icon, double v, double rate) => Text(
        '$icon ${v.floor()}${rate > 0 ? '  (+${rate.toStringAsFixed(1)}/s)' : ''}',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      );

  Widget _glass(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCC0D0B26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x557E57C2)),
        ),
        child: child,
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => Material(
        color: const Color(0xCC0D0B26),
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, color: Colors.white),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _actionBtn(String label, bool enabled, VoidCallback? onTap) => ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5E35B1),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF37305A),
          disabledForegroundColor: Colors.white54,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: enabled ? onTap : null,
        child: Text(label, style: const TextStyle(fontSize: 13)),
      );

  // ---------------- 정거장 메뉴 ----------------
  Widget _stationPanel(Station s) {
    Widget row(String title, String desc, int level, int maxLv, (int, int) cost,
        bool Function() buy) {
      final maxed = level >= maxLv;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$title  Lv.$level',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(desc,
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
            ),
            _actionBtn(maxed ? 'MAX' : _cost(cost), !maxed && w.canAfford(cost),
                () => _act(buy)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _panelOpen = false),
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: ListenableBuilder(
            listenable: _frame,
            builder: (context, _) => Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
              decoration: BoxDecoration(
                color: const Color(0xF0151236),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF7E57C2)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const ChibiPortrait(style: ChibiStyle.advisor, size: 60),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  '보유 💰${w.credits.floor()}  💎${w.ore.floor()}\n'
                                  '총 수입 💰${w.creditIncome.toStringAsFixed(1)}/s  '
                                  '💎${w.oreIncome.toStringAsFixed(1)}/s',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => setState(() => _panelOpen = false),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    const Text('🚀 함선 개조',
                        style: TextStyle(color: Color(0xFF8AD8FF), fontSize: 16)),
                    row('무기', '공격력 ${w.playerDamage.toInt()} · 3/6레벨에 다연발',
                        w.weaponLevel, GameWorld.upgradeMax,
                        w.upgradeCost(UpgradeKind.weapon),
                        () => w.upgradeShip(UpgradeKind.weapon)),
                    row('장갑', '최대 체력 ${w.playerMaxHp.toInt()}', w.hullLevel,
                        GameWorld.upgradeMax, w.upgradeCost(UpgradeKind.hull),
                        () => w.upgradeShip(UpgradeKind.hull)),
                    row('엔진', '최고 속도 ${w.playerSpeed.toInt()}', w.engineLevel,
                        GameWorld.upgradeMax, w.upgradeCost(UpgradeKind.engine),
                        () => w.upgradeShip(UpgradeKind.engine)),
                    const Divider(color: Colors.white24),
                    const Text('🛰 정거장 확장',
                        style: TextStyle(color: Color(0xFF8AD8FF), fontSize: 16)),
                    row('거주구역', '수입 💰${s.creditRate.toStringAsFixed(0)}/s · 내구도 ${s.maxHp.toInt()}',
                        s.habitatLevel, Station.maxLevel, s.habitatCost,
                        () => w.upgradeHabitat(s)),
                    row('방어포탑',
                        s.turretLevel == 0
                            ? '해적을 자동으로 요격해요'
                            : '피해 ${s.turretDamage.toInt()} · 사거리 ${s.turretRange.toInt()}',
                        s.turretLevel, Station.maxLevel, s.turretCost,
                        () => w.upgradeTurret(s)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pauseMenu() => Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('일시정지',
                style: TextStyle(color: Colors.white, fontSize: 28)),
            const SizedBox(height: 8),
            Text('격추 ${w.kills} · 식민지 ${w.colonyCount} · 정거장 ${w.stations.length}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            const Text(
              '조작: WASD/방향키 이동 · Space 사격 · E 상호작용 · B 정거장 건설',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _actionBtn('계속하기', true, () => setState(() => _menuOpen = false)),
            const SizedBox(height: 8),
            _actionBtn('저장하고 타이틀로', true, () async {
              await SaveService.save(w);
              if (mounted) Navigator.of(context).pop();
            }),
          ],
        ),
      );
}
