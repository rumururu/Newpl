import 'package:flutter/material.dart';

import '../game/models.dart';

final navigatorKey = GlobalKey<NavigatorState>();

const kPanelColor = Color(0xF0151236);
const kAccent = Color(0xFF7E57C2);
const kSky = Color(0xFF8AD8FF);

String costText(Cost c) => c.$2 > 0 ? '💰${c.$1} 💎${c.$2}' : '💰${c.$1}';

String compact(num v) {
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e4) return '${(v / 1e3).toStringAsFixed(1)}K';
  return v.floor().toString();
}

Widget glass(Widget child, {EdgeInsets? padding}) => Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC0D0B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x557E57C2)),
      ),
      child: child,
    );

Widget actionBtn(String label, bool enabled, VoidCallback? onTap,
        {Color color = const Color(0xFF5E35B1), double fontSize = 13}) =>
    ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF37305A),
        disabledForegroundColor: Colors.white54,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: enabled ? onTap : null,
      child: Text(label, style: TextStyle(fontSize: fontSize)),
    );

const titleStyle = TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold);
const bodyStyle = TextStyle(color: Colors.white, fontSize: 14);
const dimStyle = TextStyle(color: Colors.white60, fontSize: 12);
const sectionStyle = TextStyle(color: kSky, fontSize: 15, fontWeight: FontWeight.bold);

/// 반투명 배경 위 중앙 패널
class OverlayPanel extends StatelessWidget {
  const OverlayPanel({super.key, required this.child, required this.onClose, this.maxWidth = 560});
  final Widget child;
  final VoidCallback onClose;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(12),
              constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 640),
              decoration: BoxDecoration(
                color: kPanelColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kAccent),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        ),
      );
}

/// 확인 다이얼로그
Future<bool> confirmDialog(BuildContext context, String title, String body,
    {String ok = '확인', String cancel = '취소'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: kPanelColor,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}
