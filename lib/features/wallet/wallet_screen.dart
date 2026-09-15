import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/sample_data.dart';
import '../../services/currency_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/ani_gem_icon.dart';
import '../../shared/widgets/ani_gold_icon.dart';
import '../../shared/widgets/currency_pill.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/verified_badge.dart';

class WalletScreen extends ConsumerWidget {
  final String? initialTab;
  const WalletScreen({super.key, this.initialTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Balances are read from users/{uid} — server-owned, client-immutable.
    // Nothing on this screen mutates a local balance any more: the shop goes
    // through the spendGold callable and the spin wheel grants nothing, so
    // currencyProvider is not imported here at all.
    final me = myIdentity(ref);
    final initial = switch (initialTab) {
      'spend' => 1,
      'recharge' => 2,
      'plus' => 3,
      _ => 0,
    };
    return DefaultTabController(
      length: 4,
      initialIndex: initial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wallet'),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                const AniGoldIcon(size: BadgeSize.lg),
                const SizedBox(width: 5),
                Text(Fmt.balance(me?.aniGold), style: AppTextStyles.numbersLg()),
                const SizedBox(width: 14),
                const AniGemIcon(size: BadgeSize.md),
                const SizedBox(width: 5),
                Text(Fmt.balance(me?.aniGem), style: AppTextStyles.numbersLg()),
              ]),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Earn'), Tab(text: 'Spend'), Tab(text: 'Recharge'), Tab(text: '💎 AniPlus')],
          ),
        ),
        body: const TabBarView(children: [_EarnTab(), _SpendTab(), _RechargeTab(), _PlusTab()]),
      ),
    );
  }
}

// ───────────────────────── EARN
class _EarnTab extends StatelessWidget {
  const _EarnTab();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const _LuckySpin(),
        const SectionHeader(title: 'Daily Tasks', padding: EdgeInsets.only(top: 16, bottom: 10)),
        ...[('Watch an episode', 1.0, 20), ('React to 3 posts', 0.66, 15), ('Play True Fan', 0.0, 40), ('Share a post', 0.0, 10)].map((t) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.$1, style: AppTextStyles.label),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: t.$2, minHeight: 5, backgroundColor: AppColors.background, valueColor: AlwaysStoppedAnimation(t.$2 == 1 ? AppColors.success : AppColors.primary))),
                  ]),
                ),
                const SizedBox(width: 12),
                GoldTag(t.$3),
              ]),
            )),
        const SectionHeader(title: 'Combo Bonus', padding: EdgeInsets.only(top: 8, bottom: 10)),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              final done = i < 3;
              return Column(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(gradient: done ? AppGradients.brand : null, color: done ? null : AppColors.surfaceAlt, shape: BoxShape.circle, border: Border.all(color: done ? Colors.transparent : AppColors.border)),
                  child: Icon([LucideIcons.eye, LucideIcons.heart, LucideIcons.messageCircle, LucideIcons.share2, LucideIcons.gamepad2][i], size: 18, color: done ? Colors.white : AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(done ? '✓' : '', style: const TextStyle(color: AppColors.success, fontSize: 12)),
              ]);
            }),
          ),
        ),
        const SectionHeader(title: 'Refer Friends', padding: EdgeInsets.only(top: 16, bottom: 10)),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: AppGradients.purpleCyan, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Invite friends = 50🟡 each', style: AppTextStyles.subheading.copyWith(color: AppGradients.onFill(AppGradients.purpleCyan.colors.first))),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Text('YUKI-X8F2', style: AppTextStyles.numbersLg(color: Colors.white)),
                const Spacer(),
                GestureDetector(onTap: () {}, child: const Icon(LucideIcons.copy, color: Colors.white, size: 18)),
                const SizedBox(width: 14),
                GestureDetector(onTap: () {}, child: const Icon(LucideIcons.share2, color: Colors.white, size: 18)),
              ]),
            ),
            const SizedBox(height: 12),
            Text('3 / 10 invited — next milestone: 200🟡', style: AppTextStyles.caption.copyWith(color: AppGradients.onFill(AppGradients.purpleCyan.colors.first))),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: const LinearProgressIndicator(value: 0.3, minHeight: 7, backgroundColor: Colors.black26, valueColor: AlwaysStoppedAnimation(Colors.white))),
          ]),
        ),
      ],
    );
  }
}

/// The Lucky Spin, shown but not live.
///
/// The draw was `math.Random()` on the device and the payout was a local
/// addGold, so the prize was decided by the client and the balance it moved
/// was invented. Against a server-owned balance neither survives: there is no
/// server-side draw to trust, and nothing may grant gold from the client.
///
/// `_spun` was widget state, so leaving the Wallet and returning re-armed it
/// — this was unbounded free gold, not a daily reward. That is why it is held
/// back rather than merely rate-limited.
///
/// The wheel, its face and its layout are deliberately kept. What is gone is
/// the machinery that pretended to work: the AnimationController, the ticker
/// mixin and the rotation angle, none of which can move anything now. The
/// face still renders so the feature reads as pending, not deleted.
class _LuckySpin extends StatelessWidget {
  const _LuckySpin();

  static const _prizes = [10, 25, 5, 50, 15, 100, 20, 30];

  void _announce(BuildContext context) {
    Haptics.light();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Lucky Spin is not available yet.'),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        const Text('🎡 Lucky Spin', style: AppTextStyles.subheading),
        const SizedBox(height: 4),
        const Text('Not available yet', style: AppTextStyles.captionMuted),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(size: const Size(190, 190), painter: _WheelPainter(_prizes)),
              const Positioned(top: 0, child: Icon(LucideIcons.triangle, color: AppColors.secondary, size: 26)),
              Container(width: 44, height: 44, decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle), child: Icon(LucideIcons.sparkles, color: AppGradients.onFill(AppGradients.brand.colors.first), size: 20)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GradientButton(label: 'Coming Soon', icon: LucideIcons.clock, onPressed: () => _announce(context)),
      ]),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<int> prizes;
  _WheelPainter(this.prizes);
  static const _colors = [
    AppColors.primary, AppColors.secondary, AppColors.accent, AppColors.aniGold,
    AppColors.aniGem, Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFFF97316),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    const sweep = 2 * math.pi / 8;
    for (var i = 0; i < 8; i++) {
      final paint = Paint()..color = _colors[i]..style = PaintingStyle.fill;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), i * sweep - math.pi / 2, sweep, true, paint);
      // label
      final angle = i * sweep - math.pi / 2 + sweep / 2;
      final tp = TextPainter(
        text: TextSpan(text: '${prizes[i]}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      final offset = Offset(center.dx + radius * 0.62 * math.cos(angle) - tp.width / 2, center.dy + radius * 0.62 * math.sin(angle) - tp.height / 2);
      tp.paint(canvas, offset);
    }
    canvas.drawCircle(center, radius, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ───────────────────────── SPEND
class _SpendTab extends ConsumerStatefulWidget {
  const _SpendTab();
  @override
  ConsumerState<_SpendTab> createState() => _SpendTabState();
}

class _SpendTabState extends ConsumerState<_SpendTab> {
  /// Items whose purchase CANNOT be delivered, whatever the balance says.
  ///
  /// Not "not built yet" — structurally impossible as written. `verification`
  /// would set users/{uid}.isVerified, which firestore.rules pins false on
  /// create and admits on no update path; `streak_restore` maps to
  /// CurrencyController.restoreStreak, which is `copyWith(streak: streak)` —
  /// a no-op with no callers.
  ///
  /// The cosmetics above them ARE charged, because the ledger entry is a
  /// receipt Phase 3 can grant from. These two have nothing to grant from, so
  /// charging for them would be taking real gold for something no future code
  /// is going to honour. They stay visible and say so.
  static const Set<String> _undeliverable = {'verification', 'streak_restore'};

  /// The purchase currently in flight, by item id.
  ///
  /// spendGold is deliberately not idempotent — it spends once per call, so a
  /// double tap spends twice. Nothing server-side dedupes that, which makes
  /// this guard the only thing between an impatient tap and a double charge.
  /// It disables EVERY buy button, not just the one tapped, because two
  /// different purchases racing is the same problem.
  String? _busyItemId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const SectionHeader(title: 'Cosmetics', padding: EdgeInsets.only(bottom: 10)),
        ...SampleData.storeItems.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Container(width: 50, height: 50, decoration: BoxDecoration(gradient: LinearGradient(colors: s.gradient), borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text(s.emoji, style: const TextStyle(fontSize: 24))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.name, style: AppTextStyles.label), Text(s.sub, style: AppTextStyles.captionMuted)])),
                _buyBtn(s),
              ]),
            )),
        const SectionHeader(title: 'Verification', padding: EdgeInsets.only(top: 8, bottom: 10)),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.verified.withOpacity(0.5))),
          child: Row(children: [
            const VerifiedBadge(size: BadgeSize.lg),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Get Verified', style: AppTextStyles.label), Text('Blue verification badge', style: AppTextStyles.captionMuted)])),
            // The same item as the 'verification' row above, shown again in
            // its own section. One id, so both render the same held-back
            // state and neither can be bought behind the other's back.
            _buyBtn(SampleData.storeItems.firstWhere((s) => s.id == 'verification')),
          ]),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => context.push('/cards'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: AppGradients.brandTri, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('🎴', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(child: Text('Gacha / Card Collection', style: AppTextStyles.subheading.copyWith(color: AppGradients.onFill(AppGradients.brandTri.colors.first)))),
              Icon(LucideIcons.chevronRight, color: AppGradients.onFill(AppGradients.brandTri.colors.first)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buyBtn(StoreItem item) {
    if (_undeliverable.contains(item.id)) return _comingSoonBtn(item);

    final busy = _busyItemId != null;
    final mine = _busyItemId == item.id;
    return Opacity(
      opacity: busy && !mine ? 0.4 : 1,
      child: GestureDetector(
        onTap: busy ? null : () => _buy(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(gradient: AppGradients.gold, borderRadius: BorderRadius.circular(20)),
          child: mine
              ? const SizedBox(
                  width: 34,
                  height: 17,
                  child: Center(
                    child: SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                )
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${item.price}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(width: 3),
                  const Text('🟡', style: TextStyle(fontSize: 12)),
                ]),
        ),
      ),
    );
  }

  /// Visible, priced, and plainly not for sale — the same treatment the
  /// Subscribe button got when AniPlus lost its client-side grant.
  Widget _comingSoonBtn(StoreItem item) {
    return GestureDetector(
      onTap: () {
        Haptics.light();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.name} is not available yet.')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(LucideIcons.clock, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('Soon', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
        ]),
      ),
    );
  }

  Future<void> _buy(StoreItem item) async {
    setState(() => _busyItemId = item.id);
    Haptics.medium();
    try {
      await CurrencyService.instance.spendGold(itemId: item.id, amount: item.price);
      if (!mounted) return;
      // No balance is set from here. users/{uid}.aniGold is watched through
      // myIdentity, so the header figure updates from the Firestore push when
      // the write lands — the number moving is evidence the server agreed,
      // not an optimistic guess this screen made.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${item.name} — ${item.price}🟡 deducted'),
        duration: const Duration(seconds: 2),
      ));
    } on InsufficientGoldException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Not enough AniGold — ${e.short}🟡 short'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't complete that purchase. Try again."),
        duration: Duration(seconds: 2),
      ));
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }
}

// ───────────────────────── RECHARGE
class _RechargeTab extends StatelessWidget {
  const _RechargeTab();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.05),
          itemCount: SampleData.rechargePacks.length,
          itemBuilder: (_, i) {
            final p = SampleData.rechargePacks[i];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.bestValue ? AppColors.aniGem : AppColors.border, width: p.bestValue ? 1.6 : 1),
              ),
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AniGemIcon(size: BadgeSize.lg),
                      const SizedBox(height: 10),
                      Text('${p.gems}', style: AppTextStyles.numbersXl(color: AppColors.aniGem)),
                      const SizedBox(height: 2),
                      const Text('AniGems', style: AppTextStyles.captionMuted),
                      const SizedBox(height: 12),
                      GradientButton(label: '\$${p.price}', expand: false, gradient: AppGradients.gem, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo — no real purchase'), duration: Duration(seconds: 1)))),
                    ],
                  ),
                  if (p.bestValue)
                    Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(gradient: AppGradients.gem, borderRadius: BorderRadius.circular(8)), child: const Text('Best Value', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)))),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text('Payment methods', style: AppTextStyles.captionMuted),
        const SizedBox(height: 10),
        Row(children: [
          for (final m in ['Apple Pay', 'Google Pay', 'Card', 'PayPal'])
            Expanded(child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)), child: Text(m, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.w600), textAlign: TextAlign.center))),
        ]),
      ],
    );
  }
}

// ───────────────────────── ANIPLUS
class _PlusTab extends ConsumerStatefulWidget {
  const _PlusTab();
  @override
  ConsumerState<_PlusTab> createState() => _PlusTabState();
}

class _PlusTabState extends ConsumerState<_PlusTab> {
  bool _annual = false;
  bool _showCode = false;
  final _code = TextEditingController();
  int? _discount;
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _applyCode() {
    final code = _code.text.trim().toUpperCase();
    final d = SampleData.plusDiscountCodes[code];
    Haptics.light();
    setState(() {
      if (d != null) {
        _discount = d;
        _codeError = null;
      } else {
        _discount = null;
        _codeError = 'Invalid code';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPlus = ref.watch(isPlusProvider);
    final base = _annual ? 44.4 : 4.44;
    final price = _discount != null ? base * (1 - _discount! / 100) : base;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.25), AppColors.secondary.withOpacity(0.15)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary, width: 1.4),
          ),
          child: Column(
            children: [
              const Text('💎', style: TextStyle(fontSize: 44)),
              const Text('AniPlus', style: AppTextStyles.display),
              const SizedBox(height: 4),
              const Text('Unlock everything', style: AppTextStyles.bodyMuted),
              const SizedBox(height: 16),
              // toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  _toggle('Monthly', !_annual, () => setState(() => _annual = false)),
                  _toggle('Annual · Save 17%', _annual, () => setState(() => _annual = true)),
                ]),
              ),
              const SizedBox(height: 16),
              RichText(text: TextSpan(children: [
                TextSpan(text: '\$${price.toStringAsFixed(2)}', style: AppTextStyles.numbersXl(color: Colors.white)),
                TextSpan(text: _annual ? '/year' : '/month', style: AppTextStyles.bodyMuted),
              ])),
              if (_discount != null)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('$_discount% off applied 🎉', style: AppTextStyles.caption.copyWith(color: AppColors.success))),
              const SizedBox(height: 14),
              // discount
              GestureDetector(
                onTap: () => setState(() => _showCode = !_showCode),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Have a discount code?', style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight)),
                  Icon(_showCode ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: AppColors.primaryLight),
                ]),
              ),
              if (_showCode) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'ANISPHERE', isDense: true))),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: _applyCode, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(12)), child: Text('Apply', style: TextStyle(color: AppGradients.onFill(AppGradients.brand.colors.first), fontWeight: FontWeight.w700)))),
                ]),
                if (_discount != null) Padding(padding: const EdgeInsets.only(top: 8), child: _codeChip('✓ $_discount% off', AppColors.success)),
                if (_codeError != null) Padding(padding: const EdgeInsets.only(top: 8), child: _codeChip('✗ $_codeError', AppColors.error)),
              ],
              const SizedBox(height: 16),
              // AniPlus cannot be granted from the client. isPlus is server-owned
              // (firestore.rules pins it false on create and forbids it on update),
              // and no payment integration exists yet — so this announces that
              // rather than flipping a local flag and feigning a purchase.
              GradientButton(
                label: isPlus ? 'You\'re on AniPlus 💎' : 'Coming Soon',
                icon: isPlus ? LucideIcons.check : LucideIcons.clock,
                onPressed: isPlus
                    ? null
                    : () {
                        Haptics.light();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('AniPlus subscriptions are not available yet.')),
                        );
                      },
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'Everything included', padding: EdgeInsets.only(top: 18, bottom: 10)),
        ...SampleData.plusFeatures.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Container(width: 22, height: 22, decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle), child: Icon(LucideIcons.check, size: 13, color: AppGradients.onFill(AppGradients.brand.colors.first))),
                const SizedBox(width: 12),
                Expanded(child: Text(f, style: AppTextStyles.body)),
              ]),
            )),
      ],
    );
  }

  Widget _toggle(String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: active ? AppGradients.brand : null, borderRadius: BorderRadius.circular(9)),
            child: Text(label, style: TextStyle(color: active ? Colors.white : AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ),
      );

  Widget _codeChip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: c)),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}
