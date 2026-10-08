import 'dart:math';

/// 내 행성: 환생해도 유지되는 나만의 행성.
/// 둘레의 칸에 건물을 지으면 모든 게임에 영구 보너스를 준다.
enum BuildingType { house, farm, mine, lab, tower, shipyard, park, statue }

extension BuildingInfo on BuildingType {
  String get label => switch (this) {
        BuildingType.house => '주택',
        BuildingType.farm => '우주 농장',
        BuildingType.mine => '광산',
        BuildingType.lab => '연구소',
        BuildingType.tower => '방어탑',
        BuildingType.shipyard => '조선소',
        BuildingType.park => '놀이공원',
        BuildingType.statue => '선장 동상',
      };

  String get icon => switch (this) {
        BuildingType.house => '🏠',
        BuildingType.farm => '🌾',
        BuildingType.mine => '⛏',
        BuildingType.lab => '🔬',
        BuildingType.tower => '🛡',
        BuildingType.shipyard => '🚀',
        BuildingType.park => '🎡',
        BuildingType.statue => '🗿',
      };

  /// 레벨당 효과 설명
  String effect(int level) => switch (this) {
        BuildingType.house => '주민 +${level * 2}명 (선물 증가)',
        BuildingType.farm => '크레딧 수입 +${level * 3}%',
        BuildingType.mine => '광석 획득 +${level * 4}%',
        BuildingType.lab => '스킬 쿨타임 -${level * 3}%',
        BuildingType.tower => '최대 체력 +${level * 4}%',
        BuildingType.shipyard => '공격력 +${level * 3}%',
        BuildingType.park => '오프라인 수입 +${level * 5}%p',
        BuildingType.statue => '행성 선물 젬 +$level',
      };

  /// 젬으로만 짓는 건물
  bool get gemOnly => this == BuildingType.statue;
}

class HomeSlot {
  HomeSlot(this.type, [this.level = 1]);
  final BuildingType type;
  int level;
  static const maxLevel = 5;
}

/// 행성 색상 팔레트 (밝은색, 어두운색). 마지막 3개는 젬 구매
const homePalettes = [
  ('초록 정원', 0xFF66BB6A, 0xFF1565C0, 0),
  ('모래 사막', 0xFFFFCC80, 0xFFBF6F2C, 0),
  ('얼음 왕국', 0xFFE1F5FE, 0xFF4FC3F7, 0),
  ('용암 섬', 0xFFFF7043, 0xFF3E2723, 0),
  ('보라 가스', 0xFFCE93D8, 0xFF5E35B1, 0),
  ('벚꽃', 0xFFF8BBD0, 0xFFC2185B, 50),
  ('오로라', 0xFF69F0AE, 0xFF304FFE, 50),
  ('황금', 0xFFFFE082, 0xFFFF8F00, 80),
];

class HomePlanet {
  String name = '나의 작은 별';
  int palette = 0;
  final ownedPalettes = <int>{0, 1, 2, 3, 4};
  bool ring = false;
  int level = 1;
  final slots = <HomeSlot?>[];
  int lastHarvestMs = 0;

  static const maxLevel = 4;
  static const harvestHours = 8;

  HomePlanet() {
    _fitSlots();
  }

  int get slotCount => 2 + level * 2; // 4, 6, 8, 10

  void _fitSlots() {
    while (slots.length < slotCount) {
      slots.add(null);
    }
  }

  int levelOf(BuildingType t) =>
      slots.whereType<HomeSlot>().where((s) => s.type == t).fold(0, (a, s) => a + s.level);

  int get buildingCount => slots.whereType<HomeSlot>().length;
  int get residents => 2 + levelOf(BuildingType.house) * 2;

  // ---------- 보너스 (게임 전체에 적용) ----------
  double get incomeMul => 1 + levelOf(BuildingType.farm) * 0.03;
  double get oreMul => 1 + levelOf(BuildingType.mine) * 0.04;
  double get cooldownMul => max(0.5, 1 - levelOf(BuildingType.lab) * 0.03);
  double get hpMul => 1 + levelOf(BuildingType.tower) * 0.04;
  double get damageMul => 1 + levelOf(BuildingType.shipyard) * 0.03;
  double get offlineEfficiency => min(1.0, 0.5 + levelOf(BuildingType.park) * 0.05);

  // ---------- 비용 ----------
  /// 새 건물 비용 (크레딧, 광석). 동상은 젬 (아래 [statueGemCost])
  (int, int) buildCost(BuildingType t) =>
      ((600 * pow(1.35, buildingCount)).round(), 100 + buildingCount * 40);

  (int, int) upgradeCost(HomeSlot s) =>
      ((800 * pow(1.8, s.level)).round(), 150 * s.level);

  int statueGemCost(int level) => 40 + level * 30;

  (int, int) get levelUpCost => ((3000 * pow(3, level - 1)).round(), 500 * level);

  void levelUp() {
    level++;
    _fitSlots();
  }

  // ---------- 행성 선물 ----------
  bool harvestReady(DateTime now) =>
      now.millisecondsSinceEpoch - lastHarvestMs >= harvestHours * 3600 * 1000;

  Duration harvestIn(DateTime now) {
    final ms = lastHarvestMs + harvestHours * 3600 * 1000 - now.millisecondsSinceEpoch;
    return Duration(milliseconds: max(0, ms));
  }

  /// 선물 내용 (크레딧 배율은 현재 섹터 배율을 곱해서 사용)
  (int credits, int gems) harvestReward(double sectorMul) => (
        (300 * (1 + residents * 0.1) * sectorMul).round(),
        1 + levelOf(BuildingType.statue) + (residents >= 12 ? 1 : 0),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'palette': palette,
        'owned': ownedPalettes.toList(),
        'ring': ring,
        'level': level,
        'slots': [
          for (final s in slots) s == null ? null : {'t': s.type.index, 'l': s.level}
        ],
        'harvest': lastHarvestMs,
      };

  static HomePlanet fromJson(Map<String, dynamic> j) {
    final h = HomePlanet()
      ..name = j['name'] as String? ?? '나의 작은 별'
      ..palette = j['palette'] as int? ?? 0
      ..ring = j['ring'] as bool? ?? false
      ..level = j['level'] as int? ?? 1
      ..lastHarvestMs = j['harvest'] as int? ?? 0;
    h.ownedPalettes.addAll(((j['owned'] as List?) ?? []).cast<int>());
    h.slots.clear();
    for (final s in (j['slots'] as List?) ?? []) {
      if (s == null) {
        h.slots.add(null);
      } else {
        final m = s as Map;
        h.slots.add(HomeSlot(BuildingType.values[m['t'] as int], m['l'] as int));
      }
    }
    h._fitSlots();
    return h;
  }
}
