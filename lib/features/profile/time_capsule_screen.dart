import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../shared/widgets/gradient_button.dart';

class TimeCapsuleScreen extends StatefulWidget {
  const TimeCapsuleScreen({super.key});
  @override
  State<TimeCapsuleScreen> createState() => _TimeCapsuleScreenState();
}

class _TimeCapsuleScreenState extends State<TimeCapsuleScreen> {
  final List<(String, String, bool)> _capsules = [
    ('To my future self after Frieren S2', 'Opens Mar 2026', false),
    ('My One Piece ending prediction', 'Opens when One Piece ends', false),
    ('2024 me\'s anime hopes', 'Opened Jan 2025', true),
  ];

  void _newCapsule() {
    final ctrl = TextEditingController();
    DateTime date = DateTime.now().add(const Duration(days: 365));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 18, right: 18, top: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Write New Capsule', style: AppTextStyles.heading),
              const SizedBox(height: 14),
              TextField(controller: ctrl, maxLines: 4, decoration: const InputDecoration(hintText: 'Dear future me…')),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime.now(), lastDate: DateTime(2035));
                  if (picked != null) setSheet(() => date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Delivery date', prefixIcon: Icon(LucideIcons.calendarClock, size: 18)),
                  child: Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}', style: AppTextStyles.body),
                ),
              ),
              const SizedBox(height: 18),
              GradientButton(label: 'Seal Capsule 🔒', onPressed: () {
                Haptics.medium();
                Navigator.pop(ctx);
                setState(() => _capsules.insert(0, (ctrl.text.isEmpty ? 'Untitled capsule' : ctrl.text, 'Opens ${date.year}', false)));
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⏰ Time Capsule')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: AppGradients.purpleCyan, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('⏳', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(child: Text('Write a message to your future self. We\'ll deliver it on the date you choose.', style: AppTextStyles.body.copyWith(color: Colors.white))),
            ]),
          ),
          const SizedBox(height: 18),
          ..._capsules.map((c) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.$3 ? AppColors.success.withOpacity(0.5) : AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(c.$3 ? LucideIcons.mailOpen : LucideIcons.lock, color: c.$3 ? AppColors.success : AppColors.aniGold, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.$1, style: AppTextStyles.subheading),
                          const SizedBox(height: 2),
                          Text(c.$2, style: AppTextStyles.captionMuted),
                        ],
                      ),
                    ),
                    if (c.$3) const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textMuted),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          GradientButton(label: 'Write New Capsule', icon: LucideIcons.plus, onPressed: _newCapsule),
        ],
      ),
    );
  }
}
