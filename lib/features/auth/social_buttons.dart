import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';

/// Outlined Google | Apple sign-in buttons (demo — no real auth).
class SocialButtons extends StatelessWidget {
  const SocialButtons({super.key});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _btn(context, 'G', 'Google', const Color(0xFFEA4335))),
        const SizedBox(width: 12),
        Expanded(child: _btn(context, '', 'Apple', Colors.white)),
      ],
    );
  }

  Widget _btn(BuildContext context, String glyph, String label, Color color) {
    return GestureDetector(
      onTap: () {
        Haptics.light();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label sign-in (demo)'), duration: const Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label == 'Apple' ? '' : glyph,
                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
            if (label == 'Apple') const Icon(Icons.apple, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.label),
          ],
        ),
      ),
    );
  }
}
