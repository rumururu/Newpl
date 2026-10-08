import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../game/models.dart';

/// 효과음/배경음악. 실패해도 게임은 계속되도록 모든 호출을 감싼다.
class AudioService {
  AudioService._();
  static final instance = AudioService._();

  final _pools = <Sfx, AudioPool>{};
  final _last = <Sfx, DateTime>{};
  AudioPlayer? _bgm;
  bool soundOn = true;
  bool musicOn = true;
  bool _ready = false;

  static String _file(Sfx s) => switch (s) {
        Sfx.shoot => 'shoot',
        Sfx.hit => 'hit',
        Sfx.explode => 'explode',
        Sfx.bigExplode => 'big_explode',
        Sfx.pickup => 'pickup',
        Sfx.coin => 'coin',
        Sfx.gem => 'gem',
        Sfx.upgrade => 'upgrade',
        Sfx.alarm => 'alarm',
        Sfx.warp => 'warp',
        Sfx.missile => 'missile',
        Sfx.shield => 'shield',
        Sfx.boost => 'boost',
        Sfx.hurt => 'hurt',
      };

  /// 같은 소리가 너무 자주 겹치지 않게 최소 간격(ms)
  static int _gap(Sfx s) => switch (s) {
        Sfx.shoot => 70,
        Sfx.hit || Sfx.pickup || Sfx.coin => 50,
        Sfx.explode => 60,
        _ => 120,
      };

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    for (final s in Sfx.values) {
      try {
        _pools[s] = await AudioPool.createFromAsset(
          path: 'audio/${_file(s)}.wav',
          maxPlayers: s == Sfx.shoot || s == Sfx.hit ? 4 : 2,
        );
      } catch (e) {
        debugPrint('sfx load failed: $s $e');
      }
    }
  }

  void play(Sfx s) {
    if (!soundOn) return;
    final now = DateTime.now();
    final last = _last[s];
    if (last != null && now.difference(last).inMilliseconds < _gap(s)) return;
    _last[s] = now;
    final pool = _pools[s];
    if (pool == null) return;
    pool.start(volume: s == Sfx.shoot ? 0.5 : 0.9).catchError((Object _) => () async {});
  }

  Future<void> startMusic() async {
    if (!musicOn) return;
    try {
      _bgm ??= AudioPlayer()..setReleaseMode(ReleaseMode.loop);
      if (_bgm!.state == PlayerState.playing) return;
      await _bgm!.play(AssetSource('audio/bgm.wav'), volume: 0.45);
    } catch (e) {
      debugPrint('bgm failed: $e');
    }
  }

  Future<void> stopMusic() async {
    try {
      await _bgm?.stop();
    } catch (_) {}
  }

  Future<void> setMusic(bool on) async {
    musicOn = on;
    on ? await startMusic() : await stopMusic();
  }
}
