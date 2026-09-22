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
import '../../shared/providers/inventory_provider.dart';
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
    // FIVE tabs, and five things move together: this length, the tabs list,
    // the TabBarView children, and the initialTab switch above. A length that
    // disagrees with the tab count is the assertion that bit the profile
    // header — the new tab is APPENDED so every existing index keeps its
    // meaning and that switch needs no edit.
    return DefaultTabController(
      length: 5,
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
            tabs: [
              Tab(text: 'Earn'),
              Tab(text: 'Spend'),
              Tab(text: 'Recharge'),
              Tab(text: '💎 AniPlus'),
              Tab(text: 'My Items'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_EarnTab(), _SpendTab(), _RechargeTab(), _PlusTab(), _MyItemsTab()],
        ),
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

/// The daily spin. The SERVER draws; this only shows the result.
///
/// WHY IT CALLS FIRST AND ANIMATES SECOND
///
/// The other order — start spinning, call, settle on the answer — looks
/// livelier and is worse. If the call fails mid-spin there is nothing to land
/// on: the wheel either stops dead on a wedge it was never awarded, or keeps
/// turning while an error appears beside it. A wheel that lands on 100 and
/// then says "failed" is a worse lie than a moment of stillness.
///
/// So: tap disables the button and shows a spinner, the call resolves, and
/// only then does the wheel turn — to the segment the server named. A failure
/// happens while the wheel is still, so there is nothing to take back.
class _LuckySpin extends ConsumerStatefulWidget {
  const _LuckySpin();
  @override
  ConsumerState<_LuckySpin> createState() => _LuckySpinState();
}

class _LuckySpinState extends ConsumerState<_LuckySpin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  /// Where the wheel is resting. State, not a build-local, so the rebuild
  /// that todaySpinProvider triggers when the spin record lands leaves the
  /// wheel where it stopped instead of snapping it back to zero.
  double _angle = 0;
  bool _calling = false;

  /// The face. Must stay in the same ORDER as SPIN_PRIZES in functions —
  /// the server returns an index into it. If they drift, the wheel rotates to
  /// the wrong wedge, which is why the dialog reports the server's prize and
  /// not the number painted under the pointer.
  static const _prizes = [10, 25, 5, 50, 15, 100, 20, 30];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_calling) return;
    setState(() => _calling = true);
    Haptics.medium();
    try {
      final result = await CurrencyService.instance.spinWheel();
      if (!mounted) return;
      await _settleOn(result.segment);
      if (!mounted) return;
      Haptics.heavy();
      // The server's number, not the one under the pointer.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🎉 You won!'),
          content: Row(mainAxisSize: MainAxisSize.min, children: [
            const AniGoldIcon(size: BadgeSize.lg),
            const SizedBox(width: 8),
            Text('+${result.prize} AniGold',
                style: AppTextStyles.numbersXl(color: AppColors.aniGold)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Collect')),
          ],
        ),
      );
    } on AlreadySpunException catch (e) {
      // Reachable without a bug: two devices, or a tap that raced the stream
      // arriving. The wheel has not moved.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Already spun today — next spin ${_whenLabel(e.nextSpinAt)}.'),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't spin. Try again."),
        duration: Duration(seconds: 2),
      ));
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  /// Rotates so [segment]'s CENTRE finishes under the pointer, after at least
  /// five whole turns.
  ///
  /// THE GEOMETRY, because getting it wrong is invisible for two of the eight
  /// prizes and badly wrong for the other six.
  ///
  /// The painter draws wedge i from `i*per - π/2`, sweeping CLOCKWISE (canvas
  /// angles run clockwise because y points down), so wedge i's centre sits at
  /// `i*per - π/2 + per/2`. The pointer is at 12 o'clock, `-π/2`. Rotating the
  /// wheel by θ moves a feature at α to α + θ, so wedge i lands under the
  /// pointer when:
  ///
  ///     (i*per - π/2 + per/2) + θ  ≡  -π/2      =>  θ ≡ -(i*per + per/2)
  ///
  /// The sign is the half of this that was wrong: rotating by `+i*per` turns
  /// the wheel the same way the wedges are numbered, which carries wedge i
  /// AWAY from the pointer and brings `(8-i) mod 8` to it instead. Only i=0
  /// and i=4 are their own mirror, so the fault was invisible for exactly the
  /// prize that was drawn.
  ///
  /// The `per/2` is the other half: without it the rotation is a whole number
  /// of wedges, which puts a SEAM under the pointer every time — ambiguous
  /// between two prizes rather than pointing at one.
  ///
  /// The base is rounded up to whole turns from wherever the wheel is resting,
  /// so a second spin still travels forward instead of unwinding.
  Future<void> _settleOn(int segment) {
    final per = 2 * math.pi / _prizes.length;
    final base = (_angle / (2 * math.pi)).ceil() * 2 * math.pi;
    final target = base + (5 * 2 * math.pi) - (segment * per) - (per / 2);
    final tween = Tween(begin: _angle, end: target)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    tween.addListener(() {
      if (mounted) setState(() => _angle = tween.value);
    });
    return _c.forward(from: 0);
  }

  /// "in 4h" / "in 20m" — relative, because a UTC timestamp means nothing to
  /// someone reading it in their own timezone.
  String _whenLabel(DateTime nextUtc) {
    final left = nextUtc.difference(DateTime.now().toUtc());
    if (left.inHours >= 1) return 'in ${left.inHours}h';
    if (left.inMinutes >= 1) return 'in ${left.inMinutes}m';
    return 'shortly';
  }

  @override
  Widget build(BuildContext context) {
    // Null while loading and when unused; a time when today is spent. The
    // stream means the wheel locks itself the moment the transaction commits.
    final nextSpinAt = ref.watch(todaySpinProvider).asData?.value;
    final used = nextSpinAt != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        const Text('🎡 Lucky Spin', style: AppTextStyles.subheading),
        const SizedBox(height: 4),
        Text(
          used ? 'Next spin ${_whenLabel(nextSpinAt)}' : 'One free spin daily',
          style: AppTextStyles.captionMuted,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: _angle,
                child: CustomPaint(size: const Size(190, 190), painter: _WheelPainter(_prizes)),
              ),
              const Positioned(top: 0, child: Icon(LucideIcons.triangle, color: AppColors.secondary, size: 26)),
              Container(width: 44, height: 44, decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle), child: Icon(LucideIcons.sparkles, color: AppGradients.onFill(AppGradients.brand.colors.first), size: 20)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GradientButton(
          // The icon already carries the tick; a second one in the text read
          // as "✓ Spun ✓".
          label: _calling ? 'Spinning…' : (used ? 'Spun' : 'SPIN'),
          icon: used ? LucideIcons.check : LucideIcons.rotateCw,
          onPressed: (used || _calling) ? null : _spin,
        ),
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

// ───────────────────────── MY ITEMS

/// Owning and wearing, made into different things.
///
/// A fifth tab rather than a block inside Spend. Spend is where gold leaves;
/// equipping costs nothing and is a different activity, and folding it in
/// would bury three slot groups under the shop list, the verification card
/// and the gacha banner. The bar is already `isScrollable` with
/// `tabAlignment: start`, so a fifth tab scrolls in rather than crowding the
/// other four.
class _MyItemsTab extends ConsumerStatefulWidget {
  const _MyItemsTab();
  @override
  ConsumerState<_MyItemsTab> createState() => _MyItemsTabState();
}

class _MyItemsTabState extends ConsumerState<_MyItemsTab> {
  /// The slot whose equip is in flight.
  ///
  /// Same shape as the shop's _busyItemId and for the same reason: it
  /// disables EVERY slot, not just the one tapped. Two slots changing at once
  /// are two writes to the same user document, and the second would be
  /// applied against a doc the first had not finished updating. One at a time
  /// also makes a double tap a no-op rather than two calls.
  String? _busySlot;

  Future<void> _set(String slot, String? itemId) async {
    if (_busySlot != null) return;
    setState(() => _busySlot = slot);
    Haptics.medium();
    try {
      await CurrencyService.instance.equip(slot: slot, itemId: itemId);
      // Nothing is written locally. equipped lives on users/{uid}, which
      // myIdentity streams, so the tick moves when the transaction commits —
      // the UI updating IS the evidence the server agreed.
    } on NotOwnedException {
      // Not reachable from this screen, which only offers what the inventory
      // stream returned. Handled anyway so the server's refusal never
      // surfaces as a generic failure.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("You don't own that item."),
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't change that. Try again."),
        duration: Duration(seconds: 2),
      ));
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = myIdentity(ref);
    final owned = ownedItemIds(ref);

    // Owned things that belong to no slot — the withdrawn sticker pack today.
    // Shown rather than dropped: it was bought, it is owned, and a screen
    // called My Items that silently omits an item would be lying by
    // arrangement. It is listed without controls because there is nothing to
    // put it on.
    final unwearable = owned.where((id) => CosmeticSlot.of(id) == null).toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final slot in CosmeticSlot.all) ...[
          _slotGroup(slot, owned, me?.equippedIn(slot)),
          const SizedBox(height: 14),
        ],
        if (unwearable.isNotEmpty) ...[
          const SectionHeader(title: 'Not wearable', padding: EdgeInsets.only(bottom: 10)),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final id in unwearable)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(_titleFor(id), style: AppTextStyles.label),
                  ),
                const SizedBox(height: 4),
                const Text('Owned, but nothing to wear it on.',
                    style: AppTextStyles.captionMuted),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _slotGroup(String slot, Set<String> owned, String? equipped) {
    final mine = owned.where((id) => CosmeticSlot.of(id) == slot).toList()..sort();
    final busy = _busySlot != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(CosmeticSlot.label(slot), style: AppTextStyles.subheading),
          const SizedBox(height: 8),
          // "None" is always offered, even with nothing owned. Choosing not to
          // wear a thing you own is a state the server models explicitly — an
          // absent slot key — so it gets a real control rather than being the
          // gap left by not picking anything.
          _option(
            slot: slot,
            itemId: null,
            title: 'None',
            selected: equipped == null,
            enabled: !busy,
          ),
          for (final id in mine)
            _option(
              slot: slot,
              itemId: id,
              title: _titleFor(id),
              selected: equipped == id,
              enabled: !busy,
            ),
          if (mine.isEmpty) ...[
            const SizedBox(height: 6),
            // An empty slot is SHOWN, not hidden. Hiding it would mean a user
            // never learns the slot exists or that the shop sells for it, and
            // the tab would reflow as items arrive. Empty and visible teaches
            // the model; absent teaches nothing.
            const Text('Nothing for this slot yet — the shop has some.',
                style: AppTextStyles.captionMuted),
          ],
        ],
      ),
    );
  }

  Widget _option({
    required String slot,
    required String? itemId,
    required String title,
    required bool selected,
    required bool enabled,
  }) {
    final pending = _busySlot == slot;
    return Opacity(
      opacity: enabled || pending ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled && !selected ? () => _set(slot, itemId) : null,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: selected
                    ? const Icon(LucideIcons.check, size: 16, color: AppColors.success)
                    : null,
              ),
              Expanded(
                child: Text(
                  title,
                  style: selected
                      ? AppTextStyles.label.copyWith(color: AppColors.success)
                      : AppTextStyles.label,
                ),
              ),
              if (pending)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Catalogue name for an owned id, falling back to the id when the item is
  /// no longer listed — a withdrawn item is still owned and still needs a
  /// label.
  String _titleFor(String id) {
    for (final s in SampleData.storeItems) {
      if (s.id == id) return s.name;
    }
    return id;
  }
}

// ───────────────────────── SPEND
class _SpendTab extends ConsumerStatefulWidget {
  const _SpendTab();
  @override
  ConsumerState<_SpendTab> createState() => _SpendTabState();
}

class _SpendTabState extends ConsumerState<_SpendTab> {
  /// Items to render as held back rather than buyable.
  ///
  /// This is now a DISPLAY HINT, not the gate. The gate moved to the server:
  /// STORE_ITEMS marks these `sellable: false` and spendGold refuses them
  /// with `not-for-sale`, which is what actually stops a modified client. It
  /// used to be the only check, and a set in a widget was never a check at
  /// all.
  ///
  /// It stays because deleting it would trade a clear "Soon" chip for a gold
  /// button that fails when tapped — the server would refuse correctly and
  /// the user would still have been invited to try. Keeping it means the
  /// round trip never happens; keeping it ALONE is what was wrong.
  ///
  /// It can drift from the server (this list ships inside the build), and the
  /// drift is handled rather than prevented: a stale client that offers a
  /// held-back item gets ItemUnavailableException and says so.
  ///
  /// Why these two: `verification` would set users/{uid}.isVerified, which
  /// firestore.rules pins false on create and admits on no update path;
  /// `streak_restore` maps to CurrencyController.restoreStreak, a no-op with
  /// no callers. The cosmetics are charged because their ledger entry is a
  /// receipt the grant reads from; these two have nothing to grant.
  static const Set<String> _undeliverable = {'verification', 'streak_restore'};

  /// The purchase currently in flight, by item id.
  ///
  /// spendGold is deliberately not idempotent — it spends once per call, so a
  /// double tap spends twice. Nothing server-side dedupes that, which makes
  /// this guard the only thing between an impatient tap and a double charge.
  /// It disables EVERY buy button, not just the one tapped, because two
  /// different purchases racing is the same problem.
  String? _busyItemId;

  /// Owned ids for this build. Read once here and passed down rather than
  /// watched inside each button, so every row in one frame agrees.
  Set<String> _owned = const {};

  @override
  Widget build(BuildContext context) {
    _owned = ownedItemIds(ref);
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
    // Owned is checked FIRST, ahead of the held-back list. Neither of those
    // two can be bought, so neither should be ownable — but if a backfill
    // ever grants one, "Owned" is the true thing to say and "Soon" would not
    // be.
    if (_owned.contains(item.id)) return _ownedBtn();
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

  /// Already owned: no price, nothing to tap. Items are one-time, so the
  /// honest control is not a disabled buy button but the absence of one.
  Widget _ownedBtn() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withOpacity(0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(LucideIcons.check, size: 12, color: AppColors.success),
        const SizedBox(width: 4),
        Text('Owned', style: AppTextStyles.caption.copyWith(color: AppColors.success)),
      ]),
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
    } on ItemUnavailableException catch (e) {
      // This client offered something the server will not sell — almost
      // always a build older than the catalogue.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.unavailable == 'withdrawn'
            ? '${item.name} is no longer available.'
            : '${item.name} is not available yet.'),
        duration: const Duration(seconds: 2),
      ));
    } on PriceChangedException catch (e) {
      // Nothing was charged. Saying the new price is more useful than saying
      // the attempt failed.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${item.name} now costs ${e.price}🟡 — nothing was charged.'),
        duration: const Duration(seconds: 3),
      ));
    } on AlreadyOwnedException {
      // Reachable without a bug: the inventory stream had not arrived when
      // the row rendered, so it offered a buy for something already held.
      // The stream lands moments later and the row becomes Owned on its own.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You already own ${item.name}.'),
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
