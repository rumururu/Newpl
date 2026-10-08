import 'dart:math';

import 'ships.dart';

/// 새 게임을 시작해도 유지되는 계정 단위 데이터
/// (젬, 구매 내역, 꾸미기, 업적, 출석, 일일 퀘스트, 함선, 은하 명예, 설정)
class Achievement {
  const Achievement(this.id, this.title, this.desc, this.stat, this.target, this.gems);
  final String id;
  final String title;
  final String desc;
  final String stat;
  final int target;
  final int gems;
}

const achievements = [
  Achievement('first_blood', '첫 격추', '해적 1척 격추', 'kills', 1, 5),
  Achievement('hunter', '해적 사냥꾼', '해적 100척 격추', 'kills', 100, 20),
  Achievement('legend', '전설의 선장', '해적 1000척 격추', 'kills', 1000, 50),
  Achievement('miner', '광산왕', '광석 1000개 수집', 'ore', 1000, 10),
  Achievement('miner2', '광석 부자', '광석 10000개 수집', 'ore', 10000, 30),
  Achievement('colonist', '개척자', '행성 5곳 정착', 'colonies', 5, 15),
  Achievement('metropolis', '메트로폴리스', '식민지 Lv.5 달성', 'maxColony', 1, 15),
  Achievement('builder', '건축가', '정거장 3개 건설', 'stations', 3, 15),
  Achievement('boss1', '두목 사냥', '해적 두목 격파', 'bosses', 1, 10),
  Achievement('boss10', '두목 킬러', '해적 두목 10회 격파', 'bosses', 10, 30),
  Achievement('explorer', '탐험가', '섹터 3 도달', 'sector', 3, 20),
  Achievement('voyager', '항해자', '섹터 6 도달', 'sector', 6, 40),
  Achievement('rich', '부자 선장', '크레딧 10000 보유', 'credits', 10000, 15),
  Achievement('crew6', '든든한 동료', '승무원 6명 영입', 'crew', 6, 15),
  Achievement('crew3star', '전설의 동료', '★3 승무원 영입', 'crew3', 1, 20),
  Achievement('missions', '해결사', '임무 20개 완료', 'missions', 20, 20),
  Achievement('jelly', '해파리 박사', '우주 해파리 10마리 처치', 'jelly', 10, 10),
  Achievement('fashion', '패셔니스타', '꾸미기 아이템 구매', 'cosmetics', 1, 5),
  Achievement('ascend', '새로운 시작', '은하 명예로 환생', 'ascensions', 1, 30),
  Achievement('drone', '든든한 드론', '전투 드론 장착', 'drone', 1, 5),
];

const loginRewards = [5, 5, 10, 10, 15, 20, 50];

class DailyQuestDef {
  const DailyQuestDef(this.id, this.title, this.stat, this.target, this.gems);
  final String id;
  final String title;
  final String stat;
  final int target;
  final int gems;
}

const dailyPool = [
  DailyQuestDef('kill', '해적 30척 격추', 'kills', 30, 5),
  DailyQuestDef('ore', '광석 300개 수집', 'ore', 300, 5),
  DailyQuestDef('mission', '임무 2개 완료', 'missions', 2, 10),
  DailyQuestDef('colony', '식민지 2번 성장', 'colonyUps', 2, 5),
  DailyQuestDef('boss', '해적 두목 격파', 'bosses', 1, 10),
  DailyQuestDef('power', '파워업 3개 획득', 'powerups', 3, 5),
  DailyQuestDef('play', '10분 플레이', 'playMin', 10, 5),
  DailyQuestDef('jelly', '우주 해파리 3마리 처치', 'jelly', 3, 5),
];

const dailyBonusGems = 10;

class Profile {
  int gems = 0;
  bool premium = false;
  bool starterBought = false;
  bool extraCrewSlot = false;
  final ownedSkins = <String>{'default'};
  final ownedOutfits = <String>{'default'};
  String skin = 'default';
  String outfit = 'default';
  final claimed = <String>{};
  final stats = <String, int>{};

  int lastLoginDay = 0; // yyyymmdd
  int loginStreak = 0;
  int adGemDay = 0;
  int adGemsToday = 0;

  bool sound = true;
  bool music = true;
  bool haptics = true;
  bool tutorialDone = false;

  /// 결제로 받았지만 아직 월드에 지급하지 않은 ★3 승무원 수
  int pendingStarCrew = 0;

  // 격납고
  String shipType = 'scout';
  final ownedShips = <String>{};

  // 은하 명예 (환생)
  int honor = 0;
  int ascensions = 0;

  // 일일 퀘스트
  int dailyDay = 0;
  final dailyIds = <String>[];
  final dailyBase = <String, int>{};
  final dailyClaimed = <String>{};

  bool notifications = true;

  /// 저장 필요 표시
  bool dirty = false;

  static const adGemsPerDay = 3;
  static const adGemAmount = 5;

  int stat(String k) => stats[k] ?? 0;

  void addStat(String k, [int n = 1]) {
    stats[k] = stat(k) + n;
    dirty = true;
  }

  void maxStat(String k, int v) {
    if (v > stat(k)) {
      stats[k] = v;
      dirty = true;
    }
  }

  bool isComplete(Achievement a) => stat(a.stat) >= a.target;

  Iterable<Achievement> get claimable =>
      achievements.where((a) => isComplete(a) && !claimed.contains(a.id));

  bool claim(Achievement a) {
    if (!isComplete(a) || claimed.contains(a.id)) return false;
    claimed.add(a.id);
    gems += a.gems;
    dirty = true;
    return true;
  }

  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// 오늘 출석 보상을 받을 수 있으면 보상량, 아니면 null
  int? pendingLogin(DateTime now) {
    // 시계를 되돌려 같은 날/과거 날짜로 다시 받는 것 방지
    if (dayKey(now) <= lastLoginDay) return null;
    return loginRewards[(_nextStreak(now) - 1) % 7];
  }

  int _nextStreak(DateTime now) {
    final y = now.subtract(const Duration(days: 1));
    return dayKey(y) == lastLoginDay ? loginStreak + 1 : 1;
  }

  /// 출석 보상 수령, 받은 젬 반환
  int claimLogin(DateTime now) {
    final r = pendingLogin(now);
    if (r == null) return 0;
    loginStreak = _nextStreak(now);
    lastLoginDay = dayKey(now);
    gems += r;
    dirty = true;
    return r;
  }

  int adGemsLeft(DateTime now) {
    final key = dayKey(now);
    if (key < adGemDay) return 0; // 시계 되돌리기 방지
    return key == adGemDay ? adGemsPerDay - adGemsToday : adGemsPerDay;
  }

  bool claimAdGems(DateTime now) {
    if (adGemsLeft(now) <= 0) return false;
    if (dayKey(now) != adGemDay) {
      adGemDay = dayKey(now);
      adGemsToday = 0;
    }
    adGemsToday++;
    gems += adGemAmount;
    dirty = true;
    return true;
  }

  // ---------- 격납고 ----------
  bool shipUnlocked(ShipType t) =>
      t.unlockStat == null || ownedShips.contains(t.id) || stat(t.unlockStat!) >= t.unlockTarget;

  bool buyShip(ShipType t) {
    if (shipUnlocked(t) || !spendGems(t.gemPrice)) return false;
    ownedShips.add(t.id);
    return true;
  }

  // ---------- 은하 명예 ----------
  /// 명예 1점당 수입 +5%, 공격력 +3%
  double get honorIncomeMul => 1 + honor * 0.05;
  double get honorDamageMul => 1 + honor * 0.03;

  // ---------- 일일 퀘스트 ----------
  /// 날짜가 바뀌었으면 오늘의 퀘스트 3개를 새로 뽑는다
  void refreshDaily(DateTime now) {
    final key = dayKey(now);
    if (key == dailyDay && dailyIds.isNotEmpty) return;
    dailyDay = key;
    dailyIds
      ..clear()
      ..addAll(([...dailyPool]..shuffle(Random(key))).take(3).map((q) => q.id));
    dailyBase.clear();
    for (final q in dailyQuests) {
      dailyBase[q.stat] = stat(q.stat);
    }
    dailyClaimed.clear();
    dirty = true;
  }

  List<DailyQuestDef> get dailyQuests =>
      [for (final id in dailyIds) dailyPool.firstWhere((q) => q.id == id)];

  int dailyProgress(DailyQuestDef q) =>
      min(q.target, stat(q.stat) - (dailyBase[q.stat] ?? stat(q.stat)));

  bool dailyDone(DailyQuestDef q) => dailyProgress(q) >= q.target;

  bool get dailyBonusReady =>
      dailyIds.isNotEmpty &&
      dailyIds.every(dailyClaimed.contains) &&
      !dailyClaimed.contains('bonus');

  int get dailyClaimable =>
      dailyQuests.where((q) => dailyDone(q) && !dailyClaimed.contains(q.id)).length +
      (dailyBonusReady ? 1 : 0);

  bool claimDaily(String id) {
    if (dailyClaimed.contains(id)) return false;
    if (id == 'bonus') {
      if (!dailyBonusReady) return false;
      gems += dailyBonusGems;
    } else {
      final q = dailyQuests.where((q) => q.id == id).firstOrNull;
      if (q == null || !dailyDone(q)) return false;
      gems += q.gems;
    }
    dailyClaimed.add(id);
    dirty = true;
    return true;
  }

  bool spendGems(int n) {
    if (gems < n) return false;
    gems -= n;
    dirty = true;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'gems': gems,
        'premium': premium,
        'starter': starterBought,
        'slot': extraCrewSlot,
        'skins': ownedSkins.toList(),
        'outfits': ownedOutfits.toList(),
        'skin': skin,
        'outfit': outfit,
        'claimed': claimed.toList(),
        'stats': stats,
        'loginDay': lastLoginDay,
        'streak': loginStreak,
        'adDay': adGemDay,
        'adCount': adGemsToday,
        'sound': sound,
        'music': music,
        'haptics': haptics,
        'tutorial': tutorialDone,
        'pendingCrew': pendingStarCrew,
        'ship': shipType,
        'ships': ownedShips.toList(),
        'honor': honor,
        'ascensions': ascensions,
        'dailyDay': dailyDay,
        'dailyIds': dailyIds,
        'dailyBase': dailyBase,
        'dailyClaimed': dailyClaimed.toList(),
        'notifications': notifications,
      };

  static Profile fromJson(Map<String, dynamic> j) {
    final p = Profile()
      ..gems = j['gems'] as int? ?? 0
      ..premium = j['premium'] as bool? ?? false
      ..starterBought = j['starter'] as bool? ?? false
      ..extraCrewSlot = j['slot'] as bool? ?? false
      ..skin = j['skin'] as String? ?? 'default'
      ..outfit = j['outfit'] as String? ?? 'default'
      ..lastLoginDay = j['loginDay'] as int? ?? 0
      ..loginStreak = j['streak'] as int? ?? 0
      ..adGemDay = j['adDay'] as int? ?? 0
      ..adGemsToday = j['adCount'] as int? ?? 0
      ..sound = j['sound'] as bool? ?? true
      ..music = j['music'] as bool? ?? true
      ..haptics = j['haptics'] as bool? ?? true
      ..tutorialDone = j['tutorial'] as bool? ?? false
      ..pendingStarCrew = j['pendingCrew'] as int? ?? 0
      ..shipType = j['ship'] as String? ?? 'scout'
      ..honor = j['honor'] as int? ?? 0
      ..ascensions = j['ascensions'] as int? ?? 0
      ..dailyDay = j['dailyDay'] as int? ?? 0
      ..notifications = j['notifications'] as bool? ?? true;
    p.ownedShips.addAll(((j['ships'] as List?) ?? []).cast<String>());
    p.dailyIds.addAll(((j['dailyIds'] as List?) ?? []).cast<String>());
    p.dailyClaimed.addAll(((j['dailyClaimed'] as List?) ?? []).cast<String>());
    ((j['dailyBase'] as Map?) ?? {}).forEach((k, v) => p.dailyBase[k as String] = v as int);
    p.ownedSkins.addAll(((j['skins'] as List?) ?? []).cast<String>());
    p.ownedOutfits.addAll(((j['outfits'] as List?) ?? []).cast<String>());
    p.claimed.addAll(((j['claimed'] as List?) ?? []).cast<String>());
    final s = (j['stats'] as Map?) ?? {};
    s.forEach((k, v) => p.stats[k as String] = v as int);
    return p;
  }
}
