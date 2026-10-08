import 'dart:math';

import 'cosmetics.dart';

enum CrewRole { gunner, engineer, pilot, trader, miner, scientist }

extension CrewRoleInfo on CrewRole {
  String get label => switch (this) {
        CrewRole.gunner => '포수',
        CrewRole.engineer => '기관사',
        CrewRole.pilot => '조종사',
        CrewRole.trader => '상인',
        CrewRole.miner => '광부',
        CrewRole.scientist => '과학자',
      };
  String get icon => switch (this) {
        CrewRole.gunner => '🔫',
        CrewRole.engineer => '🔧',
        CrewRole.pilot => '🕹',
        CrewRole.trader => '💰',
        CrewRole.miner => '⛏',
        CrewRole.scientist => '🧪',
      };
  String get effect => switch (this) {
        CrewRole.gunner => '공격력',
        CrewRole.engineer => '최대 체력·수리',
        CrewRole.pilot => '속도',
        CrewRole.trader => '크레딧 수입',
        CrewRole.miner => '광석 획득',
        CrewRole.scientist => '스킬 쿨타임 감소',
      };
  int get suitColor => switch (this) {
        CrewRole.gunner => 0xFFE53935,
        CrewRole.engineer => 0xFFFFA000,
        CrewRole.pilot => 0xFF1E88E5,
        CrewRole.trader => 0xFF43A047,
        CrewRole.miner => 0xFF6D4C41,
        CrewRole.scientist => 0xFF8E24AA,
      };
}

const _names = [
  '뭉치', '코코', '별이', '두부', '콩이', '루루', '하루', '포포', '미미', '도리',
  '몽실', '나비', '초코', '보리', '구름', '단비', '토리', '해피', '찹쌀', '모찌',
  '라떼', '쿠키', '젤리', '솜이', '망고', '자두', '호두', '깜이', '밤비', '치즈',
];

const _hairColors = [
  0xFF5D4037, 0xFF212121, 0xFFFFD54F, 0xFFEC407A, 0xFF42A5F5,
  0xFF66BB6A, 0xFFFF7043, 0xFFB0BEC5, 0xFF7E57C2, 0xFFFFFFFF,
];
const _skinColors = [0xFFFFE0C7, 0xFFFFD3B0, 0xFFF1C27D, 0xFFE0AC69, 0xFFFFE6D5];

class CrewMember {
  CrewMember({
    required this.id,
    required this.name,
    required this.role,
    required this.rarity,
    required this.lookSeed,
    this.level = 1,
    this.assigned = false,
  });

  final int id;
  final String name;
  final CrewRole role;
  final int rarity; // 1..3
  final int lookSeed;
  int level;
  bool assigned;

  static const maxLevel = 5;

  /// 효과 (퍼센트)
  int get bonusPct => rarity * 5 + (level - 1) * 3;

  int get levelUpCost => 200 * level * rarity;

  int get hairColor => _hairColors[lookSeed % _hairColors.length];
  int get skinColor => _skinColors[(lookSeed ~/ 7) % _skinColors.length];
  bool get glasses => (lookSeed ~/ 13) % 4 == 0;
  Accessory get accessory {
    final opts = [
      Accessory.none, Accessory.none, Accessory.catEars, Accessory.bunnyEars,
      Accessory.antenna, Accessory.flower,
      if (rarity == 3) Accessory.crown,
    ];
    return opts[(lookSeed ~/ 31) % opts.length];
  }

  String get stars => '★' * rarity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.index,
        'rarity': rarity,
        'look': lookSeed,
        'level': level,
        'assigned': assigned,
      };

  static CrewMember fromJson(Map<String, dynamic> j) => CrewMember(
        id: j['id'] as int,
        name: j['name'] as String,
        role: CrewRole.values[j['role'] as int],
        rarity: j['rarity'] as int,
        lookSeed: j['look'] as int,
        level: j['level'] as int,
        assigned: j['assigned'] as bool,
      );

  /// 희귀도 확률표 (게임 내 공개용)
  static const creditOdds = {1: 70, 2: 25, 3: 5};
  static const gemOdds = {2: 80, 3: 20};

  static CrewMember random(Random r, int id, {required Map<int, int> odds}) {
    final roll = r.nextInt(100);
    var acc = 0;
    var rarity = odds.keys.first;
    for (final e in odds.entries) {
      acc += e.value;
      if (roll < acc) {
        rarity = e.key;
        break;
      }
    }
    return CrewMember(
      id: id,
      name: _names[r.nextInt(_names.length)],
      role: CrewRole.values[r.nextInt(CrewRole.values.length)],
      rarity: rarity,
      lookSeed: r.nextInt(1 << 20),
    );
  }
}
