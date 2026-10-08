import 'dart:math';

import 'package:flutter/material.dart';

import 'game/cosmetics.dart';
import 'game/models.dart';
import 'game/save.dart';
import 'game/world.dart';
import 'services/app_state.dart';
import 'ui/chibi.dart';
import 'ui/common.dart';
import 'ui/game_screen.dart';
import 'ui/meta_screens.dart';
import 'ui/shop_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.init();
  AppState.money.confirm = (title, body) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return false;
    return confirmDialog(ctx, title, body, ok: '확인');
  };
  runApp(const StarSettlersApp());
}

class StarSettlersApp extends StatelessWidget {
  const StarSettlersApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '우주 개척단',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: kAccent,
          fontFamily: 'Jua',
          useMaterial3: true,
        ),
        home: const TitleScreen(),
      );
}

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  bool _hasSave = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _dailyLogin());
  }

  Future<void> _refresh() async {
    final has = await SaveService.hasSave();
    if (mounted) setState(() => _hasSave = has);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _dailyLogin() async {
    final now = DateTime.now();
    final p = AppState.profile;
    final reward = p.pendingLogin(now);
    if (reward == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('📅 출석 보상', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChibiPortrait(style: ChibiStyle.advisor, size: 90),
            const Text('오늘도 와주셨네요, 선장님!', style: bodyStyle),
            const SizedBox(height: 8),
            Text('⭐ $reward', style: const TextStyle(fontSize: 28, color: Color(0xFFFF80AB))),
            const Text('7일 연속 출석하면 ⭐50!', style: dimStyle),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('받기'),
          ),
        ],
      ),
    );
    p.claimLogin(now);
    AppState.play(Sfx.gem);
    await SaveService.saveProfile(p);
    if (mounted) setState(() {});
  }

  Future<void> _start(GameWorld world) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(world: world)));
    _refresh();
  }

  Future<void> _newGame() async {
    if (_hasSave) {
      final ok = await confirmDialog(context, '새 게임',
          '기존 진행 상황이 지워져요.\n(젬, 꾸미기, 업적, 구매 상품은 유지돼요) 계속할까요?',
          ok: '시작');
      if (!ok) return;
      await SaveService.clearWorld();
    }
    await _start(GameWorld(profile: AppState.profile));
  }

  Future<void> _continue() async {
    final w = await SaveService.load(AppState.profile);
    if (w == null) {
      if (mounted) toast(context, '저장 데이터를 불러오지 못했어요.');
      return;
    }
    await _start(w);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = AppState.profile;
    final captain = ChibiStyle.captainIn(outfitById(p.outfit));
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(colors: [Color(0xFF2A1F66), Color(0xFF070614)], radius: 1.1),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 12,
                child: GestureDetector(
                  onTap: () => _open(const ShopScreen()),
                  child: glass(Text('⭐ ${p.gems}  ＋',
                      style: const TextStyle(color: Color(0xFFFF80AB), fontSize: 16))),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _anim,
                        builder: (context, _) {
                          final t = _anim.value * 2 * pi;
                          final blink = _anim.value > 0.93 ? 0.1 : 1.0;
                          return Transform.translate(
                            offset: Offset(0, sin(t) * 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                ChibiPortrait(style: ChibiStyle.advisor, size: 110, blink: blink),
                                ChibiPortrait(style: captain, size: 170, blink: blink),
                                Transform.translate(
                                  offset: Offset(0, -sin(t) * 12),
                                  child: const ChibiPortrait(style: ChibiStyle.pirate, size: 110),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text('STAR SETTLERS',
                          style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: Color(0xFFFFD54F))),
                      const Text('우주 개척단', style: TextStyle(fontSize: 22, color: Colors.white)),
                      const SizedBox(height: 6),
                      const Text('해적과 싸우고, 행성에 정착하고, 정거장을 키워라!',
                          style: TextStyle(color: Colors.white70)),
                      if (p.honor > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('🌌 은하 명예 ${p.honor}점 · 수입 +${p.honor * 5}% · 공격 +${p.honor * 3}%',
                              style: const TextStyle(color: Color(0xFFB388FF))),
                        ),
                      const SizedBox(height: 24),
                      _menuButton('▶ 이어하기', _hasSave ? _continue : null, primary: _hasSave),
                      const SizedBox(height: 10),
                      _menuButton('✨ 새 게임', _newGame, primary: !_hasSave),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _iconMenu('⭐', '상점', () => _open(const ShopScreen())),
                          _iconMenu('📅', '퀘스트', () => _open(const DailyQuestScreen()),
                              badge: p.dailyClaimable > 0),
                          _iconMenu('🏆', '업적', () => _open(const AchievementsScreen()),
                              badge: p.claimable.isNotEmpty),
                          _iconMenu('⚙', '설정', () => _open(const SettingsScreen())),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton(String label, VoidCallback? onTap, {bool primary = false}) => SizedBox(
        width: 230,
        child: primary
            ? FilledButton(
                onPressed: onTap,
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(label, style: const TextStyle(fontSize: 18))),
              )
            : OutlinedButton(
                onPressed: onTap,
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(label, style: const TextStyle(fontSize: 18))),
              ),
      );

  Widget _iconMenu(String icon, String label, VoidCallback onTap, {bool badge = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Badge(
            isLabelVisible: badge,
            smallSize: 10,
            child: Container(
              width: 72,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x331E1A4A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x557E57C2)),
              ),
              child: Column(children: [
                Text(icon, style: const TextStyle(fontSize: 26)),
                Text(label, style: dimStyle),
              ]),
            ),
          ),
        ),
      );
}
