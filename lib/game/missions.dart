import 'models.dart';

enum MissionType { kill, mine, deliver, bounty }

class Mission {
  Mission({
    required this.id,
    required this.type,
    required this.target,
    required this.rewardCredits,
    this.rewardGems = 0,
    this.planetIndex,
    this.bountyName,
  });

  final int id;
  final MissionType type;
  final int target;
  final int rewardCredits;
  final int rewardGems;
  final int? planetIndex;
  final String? bountyName;
  int progress = 0;
  bool bountySpawned = false;

  bool get done => progress >= target;

  String title(List<Planet> planets) => switch (type) {
        MissionType.kill => '해적 $target척 소탕',
        MissionType.mine => '광석 $target개 수집',
        MissionType.deliver =>
          '${planetIndex != null && planetIndex! < planets.length ? planets[planetIndex!].name : '?'}(으)로 화물 운송',
        MissionType.bounty => '현상수배: $bountyName',
      };

  String get icon => switch (type) {
        MissionType.kill => '⚔',
        MissionType.mine => '⛏',
        MissionType.deliver => '📦',
        MissionType.bounty => '🎯',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'target': target,
        'rc': rewardCredits,
        'rg': rewardGems,
        'planet': planetIndex,
        'bounty': bountyName,
        'progress': progress,
      };

  static Mission fromJson(Map<String, dynamic> j) => Mission(
        id: j['id'] as int,
        type: MissionType.values[j['type'] as int],
        target: j['target'] as int,
        rewardCredits: j['rc'] as int,
        rewardGems: j['rg'] as int,
        planetIndex: j['planet'] as int?,
        bountyName: j['bounty'] as String?,
      )..progress = j['progress'] as int;
}

const bountyNames = [
  '외눈 잭', '번개 몰리', '고철왕 바르크', '붉은 수염 토토', '그림자 레나',
  '뚱보 포크', '쌍칼 지지', '미친 망치 버드', '은하 여우 루시', '해골 선장 본즈',
];

/// 스토리 진행 단계 (튜토리얼 겸용)
class StoryStep {
  const StoryStep(this.title, this.key, this.target, this.lines,
      {this.relative = false, this.credits = 100, this.gems = 5});
  final String title;

  /// GameWorld.storyValue(key) 로 진행도 측정
  final String key;
  final int target;
  final bool relative;
  final List<(Speaker, String)> lines;
  final int credits;
  final int gems;
}

const storySteps = [
  StoryStep('소행성 3개 부수기', 'asteroids', 3, [
    (Speaker.advisor, '선장님! 먼저 소행성을 부숴서 광석을 모아봐요.'),
    (Speaker.advisor, '조이스틱으로 이동하고, 발사 버튼으로 쏘면 돼요!'),
  ], relative: true, credits: 60),
  StoryStep('해적 3척 격추', 'kills', 3, [
    (Speaker.advisor, '레이더에 해적이 잡혀요! 빨간 화살표 방향이에요.'),
    (Speaker.captain, '해적 따위, 내 함선 앞에선 고철이지!'),
  ], relative: true, credits: 120),
  StoryStep('테라노바에 정착하기', 'colonies', 1, [
    (Speaker.advisor, '근처 초록 행성 테라노바에 정착해봐요. 가까이 가면 정착 버튼이 떠요.'),
    (Speaker.advisor, '식민지는 가만히 있어도 크레딧을 벌어줘요!'),
  ], credits: 150),
  StoryStep('정거장에서 함선 개조', 'shipLevels', 1, [
    (Speaker.advisor, '헤이븐 기지로 돌아가서 함선을 개조해봐요. 정거장 근처에선 수리도 돼요.'),
  ], credits: 100),
  StoryStep('승무원 1명 영입', 'crew', 1, [
    (Speaker.advisor, '혼자는 외롭잖아요? 정거장 메뉴의 승무원 탭에서 동료를 영입해봐요!'),
  ], credits: 200),
  StoryStep('임무 1개 완료', 'missions', 1, [
    (Speaker.advisor, '정거장 임무 게시판에서 의뢰를 받아보세요. 보상이 짭짤해요.'),
  ], relative: true, credits: 150),
  StoryStep('새 정거장 건설', 'stations', 2, [
    (Speaker.advisor, '이제 영역을 넓힐 때예요! 행성에서 떨어진 빈 우주에 정거장을 지어봐요.'),
  ], credits: 300, gems: 10),
  StoryStep('섹터 두목 격파', 'sectorBoss', 1, [
    (Speaker.pirate, '내 구역을 휘젓고 다니는 꼬마 선장이 있다며? 직접 상대해주지!'),
    (Speaker.advisor, '섹터 두목이 나타났어요! 무기를 강화하고 맞서세요!'),
  ], credits: 500, gems: 15),
  StoryStep('워프 게이트로 다음 섹터 이동', 'sector', 1, [
    (Speaker.advisor, '두목을 쓰러뜨려서 워프 게이트가 열렸어요! 미니맵의 보라색 게이트로 가봐요.'),
    (Speaker.captain, '새로운 우주가 기다리고 있어!'),
  ], credits: 300, gems: 10),
];

/// 무한 스토리: 기본 단계 이후 섹터마다 두목 → 워프 반복
StoryStep storyStepAt(int index) {
  if (index < storySteps.length) return storySteps[index];
  final k = index - storySteps.length;
  final sector = k ~/ 2 + 1;
  if (k.isEven) {
    return StoryStep('섹터 ${sector + 1} 두목 격파', 'sectorBoss', 1, [
      (Speaker.advisor, '이 섹터의 두목을 찾아 쓰러뜨려요! 위협도가 오르면 나타나요.'),
    ], credits: 500 * (sector + 1), gems: 15);
  }
  return StoryStep('섹터 ${sector + 2}(으)로 워프', 'sector', sector + 1, [
    (Speaker.advisor, '게이트가 열렸어요. 더 깊은 우주로 가볼까요?'),
  ], credits: 300 * (sector + 1), gems: 10);
}
