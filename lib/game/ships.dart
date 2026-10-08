/// 격납고 함선 종류. 스킨(색)과 별개로 성능과 외형(실루엣)이 다르다.
class ShipType {
  const ShipType(
    this.id,
    this.name,
    this.desc, {
    this.hpMul = 1,
    this.speedMul = 1,
    this.dmgMul = 1,
    this.fireMul = 1,
    this.oreMul = 1,
    this.magnetMul = 1,
    this.crit = 0,
    this.unlockStat,
    this.unlockTarget = 0,
    this.unlockDesc = '',
    this.gemPrice = 0,
    this.wing = 26,
    this.length = 46,
  });

  final String id;
  final String name;
  final String desc;
  final double hpMul;
  final double speedMul;
  final double dmgMul;

  /// 발사 간격 배율 (작을수록 빠름)
  final double fireMul;
  final double oreMul;
  final double magnetMul;

  /// 치명타 확률 (치명타는 2.5배 피해)
  final double crit;

  /// 해금 조건: 프로필 통계 [unlockStat] >= [unlockTarget], 또는 젬 구매
  final String? unlockStat;
  final int unlockTarget;
  final String unlockDesc;
  final int gemPrice;

  /// 외형
  final double wing;
  final double length;
}

const shipTypes = [
  ShipType('scout', '스카우트', '균형 잡힌 기본 함선'),
  ShipType('interceptor', '인터셉터', '빠르고 연사가 빠르지만 장갑이 얇아요',
      hpMul: 0.8, speedMul: 1.3, dmgMul: 0.9, fireMul: 0.75,
      unlockStat: 'sector', unlockTarget: 2, unlockDesc: '섹터 2 도달', gemPrice: 150,
      wing: 34, length: 42),
  ShipType('fortress', '포트리스', '느리지만 단단하고 한 방이 세요',
      hpMul: 1.6, speedMul: 0.8, dmgMul: 1.15, fireMul: 1.1,
      unlockStat: 'bosses', unlockTarget: 3, unlockDesc: '해적 두목 3회 격파', gemPrice: 150,
      wing: 22, length: 52),
  ShipType('prospector', '프로스펙터', '광석 +50%, 아이템을 멀리서 끌어당겨요',
      hpMul: 1.1, dmgMul: 0.85, oreMul: 1.5, magnetMul: 1.8,
      unlockStat: 'ore', unlockTarget: 3000, unlockDesc: '광석 3000개 수집', gemPrice: 150,
      wing: 30, length: 44),
  ShipType('phantom', '팬텀', '25% 확률로 2.5배 치명타',
      hpMul: 0.9, speedMul: 1.15, crit: 0.25,
      unlockStat: 'sector', unlockTarget: 4, unlockDesc: '섹터 4 도달', gemPrice: 250,
      wing: 30, length: 50),
];

ShipType shipTypeById(String id) =>
    shipTypes.firstWhere((s) => s.id == id, orElse: () => shipTypes.first);
