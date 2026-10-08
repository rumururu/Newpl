import 'dart:math';

import 'package:flutter/material.dart';

import 'game/save.dart';
import 'game/world.dart';
import 'ui/chibi.dart';
import 'ui/game_screen.dart';

void main() => runApp(const StarSettlersApp());

class StarSettlersApp extends StatelessWidget {
  const StarSettlersApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '우주 개척단',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF7E57C2),
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

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();
  bool _hasSave = false;

  @override
  void initState() {
    super.initState();
    _refresh();
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

  Future<void> _start(GameWorld world) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GameScreen(world: world)));
    _refresh();
  }

  Future<void> _newGame() async {
    if (_hasSave) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('새 게임'),
          content: const Text('기존 저장 데이터가 지워져요. 계속할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('시작')),
          ],
        ),
      );
      if (ok != true) return;
      await SaveService.clear();
    }
    await _start(GameWorld());
  }

  Future<void> _continue() async {
    final w = await SaveService.load();
    if (w == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('저장 데이터를 불러오지 못했어요.')));
      }
      return;
    }
    await _start(w);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF2A1F66), Color(0xFF070614)],
            radius: 1.1,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _anim,
                    builder: (context, _) {
                      final t = _anim.value * 2 * pi;
                      // 깜빡임: 주기 끝에 잠깐 눈 감기
                      final blink = _anim.value > 0.93 ? 0.1 : 1.0;
                      return Transform.translate(
                        offset: Offset(0, sin(t) * 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            ChibiPortrait(
                                style: ChibiStyle.advisor, size: 110, blink: blink),
                            ChibiPortrait(
                                style: ChibiStyle.captain, size: 170, blink: blink),
                            Transform.translate(
                              offset: Offset(0, -sin(t) * 12),
                              child: const ChibiPortrait(
                                  style: ChibiStyle.pirate, size: 110),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('STAR SETTLERS',
                      style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          color: Color(0xFFFFD54F))),
                  const Text('우주 개척단',
                      style: TextStyle(fontSize: 22, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('해적과 싸우고, 행성에 정착하고, 정거장을 키워라!',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 220,
                    child: FilledButton(
                      onPressed: _newGame,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('새 게임', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 220,
                    child: OutlinedButton(
                      onPressed: _hasSave ? _continue : null,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('이어하기', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
