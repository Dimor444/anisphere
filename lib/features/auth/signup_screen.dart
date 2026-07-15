import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/sample_data.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/language_sheet.dart';
import 'social_buttons.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});
  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  int _step = 0;
  bool _obscure = true;
  DateTime? _dob;
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _firstAnime = TextEditingController();
  final Set<String> _picked = {};
  final Set<String> _prefs = {};

  static const _prefOptions = [
    'Action', 'Romance', 'Isekai', 'Slice of Life', 'Shonen', 'Seinen',
    'Dark Fantasy', 'Comedy', 'Sports', 'Mecha', 'Horror', 'Mystery',
    'AMVs', 'Fan Art', 'Reviews', 'Cosplay', 'Manga', 'Theories',
  ];

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _firstAnime.dispose();
    super.dispose();
  }

  int _age(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 16, now.month, now.day),
      firstDate: DateTime(1950),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  void _ageRestriction() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(ref.tr('ageRestriction')),
        content: Text(ref.tr('ageRestrictionBody')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetForm();
              context.go('/onboarding');
            },
            child: Text(ref.tr('exit'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    _email.clear();
    _username.clear();
    _password.clear();
    _firstAnime.clear();
    setState(() {
      _dob = null;
      _picked.clear();
      _prefs.clear();
      _step = 0;
    });
  }

  void _next() {
    Haptics.light();
    if (_step == 0) {
      if (_dob == null) {
        _toast('Pick your date of birth');
        return;
      }
      if (_age(_dob!) < 14) {
        _ageRestriction();
        return;
      }
    }
    if (_step == 1 && _picked.length < 5) {
      _toast('Pick at least 5 anime');
      return;
    }
    if (_step == 2) {
      Haptics.medium();
      context.go('/feed');
      return;
    }
    setState(() => _step++);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 1)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () {
          if (_step == 0) {
            context.go('/onboarding');
          } else {
            setState(() => _step--);
          }
        }),
        title: Row(
          children: [
            Text([ref.tr('account'), ref.tr('pickAnime'), ref.tr('preferences')][_step]),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
              child: Text('+14', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_step + 1) / 3,
                minHeight: 6,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _step,
              children: [_stepAccount(), _stepAnime(), _stepPrefs()],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GradientButton(
                label: _step == 2 ? ref.tr('finishSetup') : ref.tr('continueLabel'),
                onPressed: _next,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1
  Widget _stepAccount() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(controller: _email, decoration: InputDecoration(labelText: ref.tr('email'), prefixIcon: const Icon(LucideIcons.mail, size: 18))),
        const SizedBox(height: 14),
        TextField(controller: _username, decoration: InputDecoration(labelText: ref.tr('username'), prefixIcon: const Icon(LucideIcons.atSign, size: 18))),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: ref.tr('password'),
            prefixIcon: const Icon(LucideIcons.lock, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: _pickDob,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: InputDecoration(labelText: ref.tr('dateOfBirth'), prefixIcon: const Icon(LucideIcons.calendar, size: 18)),
            child: Text(
              _dob == null ? 'Select date' : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
              style: AppTextStyles.body.copyWith(color: _dob == null ? AppColors.textMuted : AppColors.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Row(children: [
          Expanded(child: Divider()),
          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or sign up with', style: AppTextStyles.captionMuted)),
          Expanded(child: Divider()),
        ]),
        const SizedBox(height: 16),
        const SocialButtons(),
      ],
    );
  }

  // ── Step 2
  Widget _stepAnime() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Row(
            children: [
              const Text('Pick at least 5', style: AppTextStyles.subheading),
              const Spacer(),
              Text('${_picked.length}/5+', style: AppTextStyles.numbers.copyWith(color: _picked.length >= 5 ? AppColors.success : AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72),
            itemCount: SampleData.animeList.length,
            itemBuilder: (_, i) {
              final a = SampleData.animeList[i];
              final sel = _picked.contains(a.id);
              return AnimeCard(
                anime: a,
                width: double.infinity,
                height: double.infinity,
                selectable: true,
                selected: sel,
                onTap: () {
                  Haptics.light();
                  setState(() => sel ? _picked.remove(a.id) : _picked.add(a.id));
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: TextField(
            controller: _firstAnime,
            decoration: InputDecoration(labelText: ref.tr('firstAnimeEver'), prefixIcon: const Icon(LucideIcons.sparkles, size: 18)),
          ),
        ),
      ],
    );
  }

  // ── Step 3
  Widget _stepPrefs() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(ref.tr('whatYouEnjoy'), style: AppTextStyles.heading),
        const SizedBox(height: 14),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: _prefOptions.map((p) {
            final sel = _prefs.contains(p);
            return FilterChip(
              label: Text(p),
              selected: sel,
              showCheckmark: false,
              onSelected: (_) {
                Haptics.light();
                setState(() => sel ? _prefs.remove(p) : _prefs.add(p));
              },
              backgroundColor: AppColors.surfaceAlt,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13),
              side: BorderSide(color: sel ? AppColors.primary : AppColors.border),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        Text(ref.tr('language'), style: AppTextStyles.heading),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => showLanguageSheet(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.globe, size: 20, color: AppColors.primaryLight),
                const SizedBox(width: 12),
                Text(languageName(ref.watch(languageProvider).code), style: AppTextStyles.body),
                const Spacer(),
                const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.15), AppColors.secondary.withOpacity(0.1)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
          ),
          child: const Row(
            children: [
              Text('🎉', style: TextStyle(fontSize: 30)),
              SizedBox(width: 12),
              Expanded(child: Text('You\'re all set! Tap Finish to enter AniSphere.', style: AppTextStyles.body)),
            ],
          ),
        ),
      ],
    );
  }
}
