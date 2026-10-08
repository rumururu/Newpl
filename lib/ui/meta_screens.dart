import 'package:flutter/material.dart';

import '../game/models.dart';
import '../game/profile.dart';
import '../game/save.dart';
import '../services/app_state.dart';
import '../services/audio.dart';
import 'common.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  @override
  Widget build(BuildContext context) {
    final p = AppState.profile;
    final done = achievements.where((a) => p.claimed.contains(a.id)).length;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B26),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151236),
        title: Text('🏆 업적 ($done/${achievements.length})'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final a in achievements)
            Card(
              color: p.claimed.contains(a.id) ? const Color(0xFF1B3A2A) : const Color(0xFF1E1A4A),
              child: ListTile(
                title: Text(a.title, style: bodyStyle),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.desc, style: dimStyle),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (p.stat(a.stat) / a.target).clamp(0, 1),
                      color: const Color(0xFF7CFFB2),
                      backgroundColor: Colors.white12,
                    ),
                    Text('${p.stat(a.stat).clamp(0, a.target)} / ${a.target}', style: dimStyle),
                  ],
                ),
                trailing: p.claimed.contains(a.id)
                    ? const Text('✅ 완료', style: TextStyle(color: Color(0xFF7CFFB2)))
                    : actionBtn('⭐${a.gems} 받기', p.isComplete(a), () async {
                        p.claim(a);
                        AppState.play(Sfx.gem);
                        await SaveService.saveProfile(p);
                        setState(() {});
                      }, color: const Color(0xFFAD1457), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _save() async {
    await SaveService.saveProfile(AppState.profile);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = AppState.profile;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B26),
      appBar: AppBar(backgroundColor: const Color(0xFF151236), title: const Text('⚙ 설정')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('효과음'),
            value: p.sound,
            onChanged: (v) {
              p.sound = v;
              AudioService.instance.soundOn = v;
              _save();
            },
          ),
          SwitchListTile(
            title: const Text('배경음악'),
            value: p.music,
            onChanged: (v) {
              p.music = v;
              AudioService.instance.setMusic(v);
              _save();
            },
          ),
          SwitchListTile(
            title: const Text('진동'),
            value: p.haptics,
            onChanged: (v) {
              p.haptics = v;
              _save();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('구매 복원'),
            onTap: () async {
              await AppState.money.restore();
              if (context.mounted) toast(context, '구매 내역을 확인했어요');
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('개인정보처리방침'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                backgroundColor: kPanelColor,
                title: const Text('개인정보처리방침'),
                content: const SingleChildScrollView(child: Text(privacySummary)),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기'))],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('모든 데이터 초기화', style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text('진행 상황, 젬, 꾸미기가 모두 삭제돼요'),
            onTap: () async {
              if (!await confirmDialog(context, '정말 초기화할까요?', '되돌릴 수 없어요. 구매한 상품은 "구매 복원"으로 되찾을 수 있어요.',
                  ok: '초기화')) {
                return;
              }
              await SaveService.wipeAll();
              AppState.profile = Profile();
              AppState.world = null;
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          const Divider(),
          const ListTile(title: Text('STAR SETTLERS · 우주 개척단'), subtitle: Text('버전 1.0.0')),
        ],
      ),
    );
  }
}

const privacySummary = '''우주 개척단은 게임 진행 데이터(진행 상황, 설정)를 기기 안에만 저장하며, 개인을 식별할 수 있는 정보를 수집하지 않습니다.

인앱 결제는 Google Play / App Store가 처리하며, 결제 정보는 개발자에게 전달되지 않습니다.

보상형 광고가 적용될 경우 광고 제공사(Google AdMob)가 광고 식별자 등을 수집할 수 있습니다.

문의: 스토어 페이지의 개발자 연락처''';
