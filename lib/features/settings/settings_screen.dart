import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/aniplus_paywall.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _private = false;
  bool _showStreak = true;
  bool _showRank = true;
  bool _spoilerShield = true;
  /// Stored as a stable code; the label is resolved at render time.
  String _dmWho = 'everyone';
  String _birthdayVis = 'Friends';
  String _sound = 'Default';
  final Map<String, bool> _notif = {'Follows': true, 'Likes': true, 'New episodes': true, 'Streaks': true, 'Messages': true};
  int _appIcon = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final lang = ref.watch(languageProvider).code;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          _section('Account'),
          _tile(LucideIcons.user, 'Edit Profile', () {}),
          _tile(LucideIcons.lock, 'Change Password', () {}),
          _tile(LucideIcons.link, 'Linked Accounts', () {}),

          _section('Appearance 💎'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('App Icon', style: AppTextStyles.captionMuted),
          ),
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: List.generate(5, (i) {
                final locked = i > 0 && !user.isPlusUser;
                return GestureDetector(
                  onTap: () {
                    if (locked) {
                      showAniPlusPaywall(context, 'Custom App Icons');
                    } else {
                      Haptics.light();
                      setState(() => _appIcon = i);
                    }
                  },
                  child: Container(
                    width: 60,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      gradient: AppGradients.palette[i].length >= 2 ? LinearGradient(colors: AppGradients.palette[i]) : AppGradients.brand,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _appIcon == i ? Colors.white : Colors.transparent, width: 2),
                    ),
                    child: Stack(
                      children: [
                        const Center(child: Text('∞', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900))),
                        if (locked) const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(14))), child: Center(child: Icon(LucideIcons.lock, color: Colors.white, size: 16)))),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          _tile(LucideIcons.palette, 'Profile Theme', () => user.isPlusUser ? null : showAniPlusPaywall(context, 'Profile Themes'), trailing: user.isPlusUser ? null : const Icon(LucideIcons.lock, size: 14, color: AppColors.aniGold)),

          _section('Privacy'),
          _switchTile('Private account', _private, (v) => setState(() => _private = v)),
          _choiceTile(ref.tr('whoCanDM'), _dmWho, const ['everyone', 'friends'],
              (v) => setState(() => _dmWho = v), labelFor: ref.tr),
          _switchTile('Show streak', _showStreak, (v) => setState(() => _showStreak = v)),
          _switchTile('Show True Fan rank', _showRank, (v) => setState(() => _showRank = v)),
          _choiceTile('Birthday visibility', _birthdayVis, ['Public', 'Friends', 'Private'], (v) => setState(() => _birthdayVis = v)),
          _switchTile('Spoiler Shield 💎', _spoilerShield, (v) {
            if (!user.isPlusUser) {
              showAniPlusPaywall(context, 'Spoiler Shield');
            } else {
              setState(() => _spoilerShield = v);
            }
          }),

          _section('Notifications'),
          ..._notif.keys.map((k) => _switchTile(k, _notif[k]!, (v) => setState(() => _notif[k] = v))),
          _tile(LucideIcons.music, 'Notification Sound', _pickSound, trailing: Text(_sound, style: AppTextStyles.captionMuted)),

          _section('Language'),
          ...AppStrings.languages.map((l) {
            final sel = l.code == lang;
            return ListTile(
              leading: Text(l.flag, style: const TextStyle(fontSize: 22)),
              title: Text(l.name, style: AppTextStyles.body),
              subtitle: l.isRTL ? const Text('Switches to RTL', style: AppTextStyles.captionMuted) : null,
              trailing: sel ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
              onTap: () {
                Haptics.select();
                ref.read(languageProvider.notifier).setLanguage(l.code);
              },
            );
          }),

          _section('More'),
          _tile(LucideIcons.ban, ref.tr('blockList'), () => context.push('/block-list')),
          _tile(LucideIcons.flag, 'Report a Problem', () {}),
          if (user.isPlusUser)
            _tile(LucideIcons.badgeCheck, 'Apply for Press Pass', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Press Pass application opened'), duration: Duration(seconds: 1))), trailing: const _PressEligible()),
          _tile(LucideIcons.info, 'About', () {}),
          _tile(LucideIcons.fileText, 'Terms & Privacy', () {}),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () {
                Haptics.medium();
                context.go('/onboarding');
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.error.withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.error.withOpacity(0.4))),
                child: Text('Logout', style: AppTextStyles.subheading.copyWith(color: AppColors.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pickSound() {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const _Waveform(),
            const SizedBox(height: 8),
            ...['Default', 'Power Up', 'Sword Clash', 'Magic Spell', 'Fireball'].map((s) => ListTile(
                  leading: const Icon(LucideIcons.volume2, color: AppColors.primaryLight, size: 20),
                  title: Text(s, style: AppTextStyles.body),
                  trailing: _sound == s ? const Icon(Icons.check, color: AppColors.primary) : null,
                  onTap: () {
                    Haptics.select();
                    setState(() => _sound = s);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(t, style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      );

  Widget _tile(IconData icon, String label, VoidCallback? onTap, {Widget? trailing}) => ListTile(
        leading: Icon(icon, size: 20, color: AppColors.textSecondary),
        title: Text(label, style: AppTextStyles.body),
        trailing: trailing ?? const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.textMuted),
        onTap: onTap,
      );

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        title: Text(label, style: AppTextStyles.body),
        value: value,
        onChanged: (v) {
          Haptics.light();
          onChanged(v);
        },
        activeColor: Colors.white,
        activeTrackColor: AppColors.primary,
      );

  /// [labelFor] maps an option's stored value to its display text; omit it
  /// when the value IS the label (the untranslated tiles).
  Widget _choiceTile(String label, String value, List<String> options, ValueChanged<String> onChanged,
          {String Function(String)? labelFor}) =>
      ListTile(
        title: Text(label, style: AppTextStyles.body),
        trailing: DropdownButton<String>(
          value: value,
          underline: const SizedBox.shrink(),
          dropdownColor: AppColors.surfaceAlt,
          style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(labelFor?.call(o) ?? o)))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              Haptics.select();
              onChanged(v);
            }
          },
        ),
      );
}

class _PressEligible extends StatelessWidget {
  const _PressEligible();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
      child: const Text('Eligible', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _Waveform extends StatefulWidget {
  const _Waveform();
  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(size: const Size(double.infinity, 50), painter: _WavePainter(_c.value)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double t;
  _WavePainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    const bars = 28;
    final w = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final h = (math.sin((i / bars * 2 * math.pi) + t * 2 * math.pi).abs() * 0.8 + 0.2) * size.height;
      final paint = Paint()
        ..shader = const LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.bottomCenter, end: Alignment.topCenter).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(i * w + w * 0.2, (size.height - h) / 2, w * 0.6, h), const Radius.circular(3));
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t;
}
