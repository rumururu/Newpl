import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/cosmetics.dart';
import '../game/missions.dart';
import '../game/models.dart';
import '../game/save.dart';
import '../game/world.dart';
import '../services/app_state.dart';
import '../services/audio.dart';
import '../services/notifications.dart';
import 'chibi.dart';
import 'common.dart';
import 'merchant_panel.dart';
import 'meta_screens.dart';
import 'shop_screen.dart';
import 'station_panel.dart';
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

enum _Overlay { none, station, merchant, pause }

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final _frame = _FrameNotifier();
  final _input = InputState();
  final _focus = FocusNode();
  Duration _last = Duration.zero;
  double _saveTimer = 0;
  double _profileTimer = 0;
  int _profileSaveCount = 0;
  final _notified = <String>{};

  Offset _stick = Offset.zero;
  bool _touchFire = false;
  bool _autoFire = false;
  _Overlay _overlay = _Overlay.none;
  bool _modal = false; // 다이얼로그/다른 화면이 떠 있음

  GameWorld get w => widget.world;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.world = w;
    AppState.deliverPending();
    _notified.addAll(w.profile.claimable.map((a) => a.id));
    _ticker = createTicker(_onTick)..start();
    NotificationService.instance.cancelAll();
    if (w.profile.notifications) NotificationService.instance.requestPermission();
    AudioService.instance.startMusic();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOffline());
  }

  /// 환생 등으로 이 월드를 버릴 때는 저장하지 않는다
  bool _discarded = false;

  @override
  void dispose() {
    if (!_discarded) SaveService.save(w);
    AppState.world = null;
    AudioService.instance.stopMusic();
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AudioService.instance.startMusic();
      NotificationService.instance.cancelAll();
      // 백그라운드에 있던 시간만큼 오프라인 수입 (1분 이상일 때)
      if (w.savedAt != null && !_modal) _showOffline();
    } else if (!_discarded &&
        (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)) {
      w.savedAt ??= DateTime.now();
      SaveService.save(w);
      if (w.profile.notifications) {
        NotificationService.instance.scheduleReturn(
          storageFullIn: Duration(hours: w.profile.premium ? 8 : 2),
          hasColonies: w.counter('colonies') > 0,
        );
      }
      AudioService.instance.stopMusic();
    }
  }

  // ---------------- 루프 ----------------
  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    bool k(LogicalKeyboardKey a, LogicalKeyboardKey b) => keys.contains(a) || keys.contains(b);
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
        (_autoFire && _targetInRange());
    _input.autoAim = _autoFire;

    w.paused = _overlay != _Overlay.none || _modal;
    w.update(dt, _input);

    for (final s in w.sfx) {
      AudioService.instance.play(s);
      if (s == Sfx.hurt || s == Sfx.bigExplode) AppState.haptic();
    }
    w.sfx.clear();

    _saveTimer += dt;
    if (_saveTimer > 20 && !_discarded) {
      _saveTimer = 0;
      SaveService.save(w);
    }
    _profileTimer += dt;
    if (_profileTimer > 1) {
      _profileTimer = 0;
      _profileSaveCount++;
      for (final a in w.profile.claimable) {
        if (_notified.add(a.id)) {
          w.say(Speaker.advisor, '🏆 업적 달성: ${a.title}! 메뉴의 업적에서 ⭐${a.gems}를 받으세요.');
          w.sfx.add(Sfx.gem);
        }
      }
      if (w.profile.dirty && _profileSaveCount % 5 == 0) SaveService.saveProfile(w.profile);
    }
    // 다른 오버레이가 사라졌으면 닫기
    if (_overlay == _Overlay.station && w.nearbyStation == null) _setOverlay(_Overlay.none);
    if (_overlay == _Overlay.merchant && w.nearbyMerchant == null) _setOverlay(_Overlay.none);
    _frame.tick();
  }

  bool _targetInRange() => w.pirates.any((e) => (e.pos - w.player.pos).distance < 520);

  void _setOverlay(_Overlay o) {
    if (_overlay == o) return;
    setState(() => _overlay = o);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.keyE) {
      _interact();
    } else if (key == LogicalKeyboardKey.keyB) {
      _act(w.buildStation);
    } else if (key == LogicalKeyboardKey.keyQ) {
      w.fireMissiles();
    } else if (key == LogicalKeyboardKey.keyF) {
      w.activateShield();
    } else if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      w.boost();
    } else if (key == LogicalKeyboardKey.escape) {
      _setOverlay(_overlay == _Overlay.none ? _Overlay.pause : _Overlay.none);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _interact() {
    if (_overlay != _Overlay.none) {
      _setOverlay(_Overlay.none);
      return;
    }
    if (w.nearbyMerchant != null) {
      _setOverlay(_Overlay.merchant);
    } else if (w.nearbyStation != null) {
      _setOverlay(_Overlay.station);
    } else if (w.nearbyGate != null) {
      _act(() => w.warp(w.nearbyGate!));
    } else if (w.nearbyPlanet != null) {
      _act(() => w.upgradePlanet(w.nearbyPlanet!));
    }
  }

  void _act(bool Function() f) {
    if (f()) {
      AppState.haptic();
      SaveService.save(w);
    } else {
      w.say(Speaker.advisor, '자원이 부족하거나 지금은 할 수 없어요.');
    }
    setState(() {});
  }

  Future<T?> _modalRoute<T>(Widget page) async {
    _modal = true;
    final r = await Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
    _modal = false;
    AppState.deliverPending();
    if (mounted) setState(() {});
    return r;
  }

  Future<void> _openShop([int tab = 0]) => _modalRoute(ShopScreen(initialTab: tab));

  // ---------------- 오프라인 수입 / 부활 ----------------
  Future<void> _showOffline() async {
    final (sec, c, o) = w.offlineEarnings(DateTime.now());
    w.savedAt = null;
    if (sec <= 0 || !mounted) return;
    _modal = true;
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final premium = w.profile.premium;
    final mult = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('어서 오세요, 선장님!', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChibiPortrait(style: ChibiStyle.advisor, size: 90),
            Text('자리를 비운 ${h > 0 ? '$h시간 ' : ''}$m분 동안\n식민지가 열심히 일했어요!',
                textAlign: TextAlign.center, style: bodyStyle),
            const SizedBox(height: 8),
            Text('💰${compact(c)}  💎${compact(o)}',
                style: const TextStyle(fontSize: 22, color: Color(0xFFFFD54F))),
            if (!premium)
              const Text('사령관 패스: 최대 8시간 + 자동 2배', style: dimStyle),
          ],
        ),
        actions: [
          if (!premium) TextButton(onPressed: () => Navigator.pop(ctx, 1), child: const Text('받기')),
          FilledButton(
            onPressed: () async {
              final ok = await AppState.watchAd();
              if (!ctx.mounted) return;
              if (ok) {
                Navigator.pop(ctx, 2);
              } else {
                toast(ctx, '광고를 불러오는 중이에요. 잠시 후 다시 시도해 주세요.');
              }
            },
            child: Text(premium ? '2배로 받기 👑' : '📺 광고 보고 2배'),
          ),
        ],
      ),
    );
    w.applyOffline(c * (mult ?? 1), o * (mult ?? 1));
    w.sfx.add(Sfx.coin);
    _modal = false;
    SaveService.save(w);
  }

  Future<void> _showAscend() async {
    final p = w.profile;
    final can = w.canAscend;
    final gain = w.honorGain;
    _modal = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('🌌 은하 명예', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('현재 명예 ${p.honor}점 (환생 ${p.ascensions}회)', style: bodyStyle),
            Text('수입 +${(p.honor * 5)}% · 공격력 +${(p.honor * 3)}%', style: dimStyle),
            const Divider(color: Colors.white24),
            const Text(
              '환생하면 지금 우주(섹터, 식민지, 정거장, 함선 강화, 승무원, 크레딧)가 초기화되고\n'
              '대신 영구 보너스인 명예 점수를 받아요.\n젬, 꾸미기, 함선, 업적은 유지돼요.',
              style: bodyStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            if (can)
              Text('지금 환생하면 명예 +$gain점!\n(제국 가치가 클수록 많이 받아요)',
                  style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 16),
                  textAlign: TextAlign.center)
            else
              const Text('섹터 4에 도달하면 환생할 수 있어요.',
                  style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('닫기')),
          if (can)
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('환생 (+$gain)')),
        ],
      ),
    );
    _modal = false;
    if (ok != true || !mounted) return;
    if (!await confirmDialog(context, '정말 환생할까요?', '현재 우주가 초기화돼요. 되돌릴 수 없어요.', ok: '환생')) {
      return;
    }
    _discarded = true;
    _ticker.stop();
    p.honor += gain;
    p.ascensions++;
    p.addStat('ascensions');
    await SaveService.clearWorld();
    await SaveService.saveProfile(p);
    if (!mounted) return;
    AudioService.instance.play(Sfx.warp);
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(world: GameWorld(profile: p))));
  }

  Future<void> _reviveWithAd() async {
    _modal = true;
    final ok = await AppState.watchAd();
    _modal = false;
    if (ok) {
      w.reviveHere();
    } else {
      w.say(Speaker.advisor, '광고를 불러오는 중이에요. 잠시 후 다시 눌러주세요.');
    }
  }

  void _reviveWithGems() {
    if (w.profile.spendGems(10)) {
      w.reviveHere();
      SaveService.saveProfile(w.profile);
    } else {
      _openShop();
    }
  }

  // ---------------- 빌드 ----------------
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
            Positioned.fill(child: CustomPaint(painter: WorldPainter(w, zoom, repaint: _frame))),
            Positioned.fill(
              child: ListenableBuilder(listenable: _frame, builder: (context, _) => _hud(context)),
            ),
            if (_overlay == _Overlay.station && w.nearbyStation != null)
              Positioned.fill(
                child: StationPanel(
                  world: w,
                  station: w.nearbyStation!,
                  frame: _frame,
                  act: _act,
                  onClose: () => _setOverlay(_Overlay.none),
                  onOpenShop: () => _openShop(),
                ),
              ),
            if (_overlay == _Overlay.merchant && w.nearbyMerchant != null)
              Positioned.fill(
                child: MerchantPanel(
                  world: w,
                  event: w.nearbyMerchant!,
                  frame: _frame,
                  act: _act,
                  onClose: () => _setOverlay(_Overlay.none),
                ),
              ),
            if (_overlay == _Overlay.pause) Positioned.fill(child: _pauseMenu()),
          ],
        ),
      ),
    );
  }

  Widget _hud(BuildContext context) {
    final p = w.player;
    final narrow = MediaQuery.sizeOf(context).width < 720;
    return SafeArea(
      child: Stack(
        children: [
          Positioned(left: 8, top: 8, child: _captainCard()),
          Positioned(right: 8, top: 8, child: _rightColumn()),
          if (w.dialogs.isNotEmpty)
            Positioned(
              top: narrow ? 230 : 70,
              left: narrow ? 8 : 240,
              right: narrow ? 8 : 150,
              child: Center(child: _dialog(w.dialogs.last)),
            ),
          if (!p.alive) Positioned.fill(child: _reviveOverlay()),
          if (p.alive) ...[
            Positioned(left: 20, bottom: 20, child: _joystick()),
            Positioned(right: 16, bottom: 16, child: _combatButtons()),
            Positioned(
              left: 8,
              right: 8,
              bottom: narrow ? 200 : 150,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: _contextActions(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _captainCard() {
    final p = w.player;
    final (sv, st) = w.storyProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        glass(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChibiPortrait(style: ChibiStyle.captainIn(outfitById(w.profile.outfit)), size: 54),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _hpBar(p.hp / w.playerMaxHp),
                const SizedBox(height: 3),
                _res('💰', w.credits, w.creditIncome),
                _res('💎', w.ore, w.oreIncome),
                GestureDetector(
                  onTap: () => _openShop(),
                  child: Text('⭐ ${w.profile.gems}  ＋',
                      style: const TextStyle(color: Color(0xFFFF80AB), fontSize: 13)),
                ),
              ],
            ),
          ],
        )),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: glass(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🎯 ${w.story.title}',
                  style: const TextStyle(color: Color(0xFF7CFFB2), fontSize: 12, fontWeight: FontWeight.bold)),
              if (st > 1) Text('$sv / $st', style: dimStyle),
              for (final m in w.activeMissions)
                Text('${m.icon} ${_missionShort(m)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              if (w.buffs.isNotEmpty)
                Text(w.buffs.entries.map((e) => '${e.key.icon}${e.value.ceil()}s').join('  '),
                    style: const TextStyle(color: Color(0xFFB9F6CA), fontSize: 12)),
            ],
          )),
        ),
      ],
    );
  }

  String _missionShort(Mission m) => switch (m.type) {
        MissionType.kill || MissionType.mine =>
          '${m.title(w.planets)} ${min(m.progress, m.target)}/${m.target}',
        _ => m.title(w.planets),
      };

  Widget _rightColumn() => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              glass(Text(
                '${w.sectorName}\n⚠ 위협 ${w.threat.toStringAsFixed(1)}  🏛 ${compact(w.empireValue)}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              )),
              const SizedBox(width: 6),
              Badge(
                isLabelVisible: w.profile.claimable.isNotEmpty || w.profile.dailyClaimable > 0,
                smallSize: 10,
                child: _iconBtn(Icons.menu, () => _setOverlay(_Overlay.pause)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(painter: MinimapPainter(w, repaint: _frame)),
          ),
          for (final ev in w.events)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: glass(
                Text('${ev.title} ${ev.timeLeft.ceil()}s',
                    style: const TextStyle(color: Color(0xFFFFD740), fontSize: 11)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
        ],
      );

  List<Widget> _contextActions() {
    final out = <Widget>[];
    final merchant = w.nearbyMerchant;
    final st = w.nearbyStation;
    final gate = w.nearbyGate;
    final pl = w.nearbyPlanet;
    if (merchant != null) {
      out.add(actionBtn('🛒 상인과 거래 (E)', true, () => _setOverlay(_Overlay.merchant),
          color: const Color(0xFF00897B)));
    }
    if (st != null) {
      out.add(actionBtn('🛠 ${st.name} (E)', true, () => _setOverlay(_Overlay.station)));
    }
    if (gate != null) {
      out.add(w.gateOpen(gate)
          ? actionBtn(gate.forward ? '🌀 다음 섹터로 워프 (E)' : '🌀 이전 섹터로 (E)', true,
              () => _act(() => w.warp(gate)),
              color: const Color(0xFF6A1B9A))
          : actionBtn('🔒 섹터 두목을 쓰러뜨려야 열려요', false, null));
    }
    if (pl != null) {
      if (pl.colonyLevel >= Planet.maxLevel) {
        out.add(actionBtn('🌟 ${pl.name} 최대 레벨', false, null));
      } else {
        final c = w.planetCost(pl);
        final label = pl.colonyLevel == 0
            ? '🚩 ${pl.name} 정착 ${costText(c)} (E)'
            : '⬆ ${pl.name} Lv.${pl.colonyLevel + 1} ${costText(c)} (E)';
        out.add(actionBtn(label, w.canAfford(c), () => _act(() => w.upgradePlanet(pl))));
      }
      final (cr, orr) = pl.ratePerLevel;
      out.add(glass(Text(
        '${pl.kindLabel} · 레벨당 💰${(cr * w.sectorMul).toStringAsFixed(1)}/s'
        '${orr > 0 ? ' 💎${(orr * w.sectorMul).toStringAsFixed(1)}/s' : ''}',
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      )));
    }
    if (w.canBuildStationHere && (w.counter('colonies') > 0 || w.credits >= w.stationBuildCost.$1)) {
      final c = w.stationBuildCost;
      out.add(actionBtn('🏗 정거장 건설 ${costText(c)} (B)', w.canAfford(c), () => _act(w.buildStation)));
    }
    return out;
  }

  Widget _joystick() {
    const radius = 62.0;
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
              width: 46,
              height: 46,
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

  Widget _combatButtons() {
    final p = w.player;
    return SizedBox(
      width: 190,
      height: 200,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Listener(
              onPointerDown: (_) => _touchFire = true,
              onPointerUp: (_) => _touchFire = false,
              onPointerCancel: (_) => _touchFire = false,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_touchFire ? const Color(0xFFFF5252) : const Color(0xFFE53935))
                      .withValues(alpha: 0.55),
                  border: Border.all(color: Colors.white38, width: 2),
                ),
                child: const Center(
                    child: Text('발사', style: TextStyle(color: Colors.white, fontSize: 18))),
              ),
            ),
          ),
          Positioned(
            right: 104,
            bottom: 0,
            child: _skillBtn('💨', p.boostCooldown, w.boostCooldownMax, true, w.boost),
          ),
          Positioned(
            right: 96,
            bottom: 66,
            child: _skillBtn('🚀', p.missileCooldown, w.missileCooldownMax,
                w.level(UpgradeKind.missile) > 0, w.fireMissiles),
          ),
          Positioned(
            right: 28,
            bottom: 104,
            child: _skillBtn('🛡', p.shieldCooldown, w.shieldCooldownMax,
                w.level(UpgradeKind.shield) > 0, w.activateShield),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: () => setState(() => _autoFire = !_autoFire),
              child: glass(
                Text(_autoFire ? '자동 ON' : '자동 OFF',
                    style: TextStyle(
                        color: _autoFire ? const Color(0xFF7CFFB2) : Colors.white60, fontSize: 11)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skillBtn(String icon, double cd, double cdMax, bool unlocked, bool Function() use) {
    final f = cdMax <= 0 ? 0.0 : (cd / cdMax).clamp(0.0, 1.0);
    return Listener(
      onPointerDown: (_) {
        if (!unlocked) {
          w.say(Speaker.advisor, '정거장 함선 개조에서 장착할 수 있어요!');
          return;
        }
        if (use()) AppState.haptic();
      },
      child: SizedBox(
        width: 56,
        height: 56,
        child: CustomPaint(
          painter: _CooldownPainter(f, unlocked),
          child: Center(
            child: Opacity(
              opacity: unlocked ? 1 : 0.35,
              child: Text(unlocked ? icon : '🔒', style: const TextStyle(fontSize: 22)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviveOverlay() {
    final p = w.player;
    if (!p.awaitingRevive) return const SizedBox();
    final premium = w.profile.premium;
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      child: glass(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChibiPortrait(style: ChibiStyle.pirate, size: 80),
            const Text('💥 격추당했습니다!', style: TextStyle(color: Colors.white, fontSize: 22)),
            Text('${max(0, 20 - p.deadTime).ceil()}초 뒤 기지에서 자동 재출격', style: dimStyle),
            const SizedBox(height: 12),
            actionBtn(premium ? '👑 이 자리에서 부활 (무료)' : '📺 광고 보고 이 자리에서 부활', true, _reviveWithAd,
                color: const Color(0xFF00897B)),
            const SizedBox(height: 8),
            actionBtn('⭐10 으로 이 자리에서 부활', true, _reviveWithGems, color: const Color(0xFFAD1457)),
            const SizedBox(height: 8),
            actionBtn('🏠 기지에서 재출격 (크레딧 25% 손실)', true, w.respawnAtBase,
                color: const Color(0xFF455A64)),
          ],
        ),
        padding: const EdgeInsets.all(20),
      ),
    );
  }

  Widget _dialog(DialogLine d) {
    final name = switch (d.speaker) {
      Speaker.captain => '선장',
      Speaker.pirate => '해적',
      Speaker.advisor => '부관 미나',
      Speaker.merchant => '상인 냥냥',
    };
    return Opacity(
      opacity: d.time.clamp(0.0, 0.5) * 2,
      child: glass(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChibiPortrait(
                  style: ChibiStyle.of(d.speaker,
                      captainStyle: ChibiStyle.captainIn(outfitById(w.profile.outfit))),
                  size: 48),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: TextStyle(
                            color: d.speaker == Speaker.pirate ? const Color(0xFFFF8A80) : kSky,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    Text(d.text, style: bodyStyle),
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
        '$icon ${compact(v)}${rate > 0 ? '  +${rate.toStringAsFixed(1)}/s' : ''}',
        style: const TextStyle(color: Colors.white, fontSize: 13),
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

  Widget _pauseMenu() => OverlayPanel(
        onClose: () => _setOverlay(_Overlay.none),
        maxWidth: 420,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            const Text('일시정지', style: titleStyle, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              '${w.sectorName} · 격추 ${w.counter('kills')} · 승무원 ${w.roster.length}\n'
              '정착 ${w.counter('colonies')} · 정거장 ${w.stations.length} · 임무 완료 ${w.counter('missions')}',
              style: dimStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            actionBtn('▶ 계속하기', true, () => _setOverlay(_Overlay.none)),
            const SizedBox(height: 8),
            actionBtn('⭐ 상점', true, () => _openShop(), color: const Color(0xFFAD1457)),
            const SizedBox(height: 8),
            Badge(
              isLabelVisible: w.profile.claimable.isNotEmpty,
              label: Text('${w.profile.claimable.length}'),
              child: SizedBox(
                width: double.infinity,
                child: actionBtn('🏆 업적', true, () => _modalRoute(const AchievementsScreen())),
              ),
            ),
            const SizedBox(height: 8),
            Badge(
              isLabelVisible: w.profile.dailyClaimable > 0,
              label: Text('${w.profile.dailyClaimable}'),
              child: SizedBox(
                width: double.infinity,
                child: actionBtn('📅 일일 퀘스트', true, () => _modalRoute(const DailyQuestScreen())),
              ),
            ),
            const SizedBox(height: 8),
            actionBtn('🌌 은하 명예 (환생)', true, _showAscend, color: const Color(0xFF4527A0)),
            const SizedBox(height: 8),
            actionBtn('⚙ 설정', true, () => _modalRoute(const SettingsScreen()),
                color: const Color(0xFF455A64)),
            const SizedBox(height: 8),
            actionBtn('💾 저장하고 타이틀로', true, () async {
              await SaveService.save(w);
              if (mounted) Navigator.of(context).pop();
            }, color: const Color(0xFF455A64)),
            const SizedBox(height: 16),
            const Text(
              '키보드: WASD 이동 · Space 사격 · Q 미사일 · F 실드 · Shift 부스트\nE 상호작용 · B 정거장 건설 · Esc 메뉴',
              style: dimStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _CooldownPainter extends CustomPainter {
  _CooldownPainter(this.fraction, this.unlocked);
  final double fraction;
  final bool unlocked;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0x881A237E));
    canvas.drawCircle(
        c,
        r - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = unlocked && fraction == 0 ? const Color(0xFF80D8FF) : Colors.white24);
    if (fraction > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2, 2 * pi * fraction, true,
          Paint()..color = const Color(0xAA000000));
    }
  }

  @override
  bool shouldRepaint(_CooldownPainter old) => old.fraction != fraction || old.unlocked != unlocked;
}
