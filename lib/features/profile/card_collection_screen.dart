import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/card_model.dart';
import '../../data/sample_data.dart';
import '../../shared/widgets/character_card.dart';
import '../../shared/widgets/gradient_button.dart';

class CardCollectionScreen extends StatelessWidget {
  const CardCollectionScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const cards = SampleData.cards;
    final owned = cards.where((c) => c.owned).length;
    return Scaffold(
      appBar: AppBar(title: const Text('🎴 Card Collection')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(gradient: AppGradients.brandTri, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('🎴', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(child: Text('$owned / ${cards.length} collected', style: AppTextStyles.subheading.copyWith(color: AppGradients.onFill(AppGradients.brandTri.colors.first)))),
              Text('${((owned / cards.length) * 100).round()}%', style: AppTextStyles.numbersLg(color: AppGradients.onFill(AppGradients.brandTri.colors.first))),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('Open a Pack', style: AppTextStyles.subheading),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _packCard(context, 'Standard', '50🟡', [AppColors.primary, AppColors.primaryDark])),
            const SizedBox(width: 12),
            Expanded(child: _packCard(context, 'Premium', '120🟡', [AppColors.aniGold, const Color(0xFFB45309)], glow: true)),
          ]),
          const SizedBox(height: 18),
          const Text('My Cards', style: AppTextStyles.subheading),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72),
            itemCount: cards.length,
            itemBuilder: (_, i) => _CardFace(card: cards[i], dimmed: !cards[i].owned),
          ),
        ],
      ),
    );
  }

  /// [glow] adds a coloured halo. Reserved for packs whose gradient is a
  /// RARITY colour (gold), where the glow is deliberate. Brand-coloured
  /// packs pass false — the brand no longer glows anywhere.
  Widget _packCard(BuildContext context, String name, String price, List<Color> g,
      {bool glow = false}) {
    return GestureDetector(
      onTap: () => _openPack(context),
      child: Container(
        height: 150,
        decoration: BoxDecoration(gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(18), boxShadow: glow ? [BoxShadow(color: g.last.withOpacity(0.4), blurRadius: 16)] : null),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('📦', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 8),
          Text(name, style: AppTextStyles.subheading.copyWith(color: Colors.white)),
          Text(price, style: AppTextStyles.numbers.copyWith(color: Colors.white)),
        ]),
      ),
    );
  }

  void _openPack(BuildContext context) {
    Haptics.medium();
    final rng = math.Random();
    final pull = List.generate(5, (_) => SampleData.cards[rng.nextInt(SampleData.cards.length)]);
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PackOpening(cards: pull)));
  }
}

/// Thin adapter from [CardModel] to the reusable [CharacterCard].
class _CardFace extends StatelessWidget {
  final CardModel card;
  final bool dimmed;
  const _CardFace({required this.card, this.dimmed = false});
  @override
  Widget build(BuildContext context) {
    return CharacterCard(
      imageUrl: card.imageUrl,
      imagePath: card.imagePath,
      characterName: card.character,
      seriesName: card.anime,
      rarity: card.rarity,
      power: card.power,
      fallbackEmoji: card.emoji,
      dimmed: dimmed,
    );
  }
}

class _PackOpening extends StatefulWidget {
  final List<CardModel> cards;
  const _PackOpening({required this.cards});
  @override
  State<_PackOpening> createState() => _PackOpeningState();
}

class _PackOpeningState extends State<_PackOpening> {
  final _pc = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(alignment: Alignment.centerRight, child: IconButton(icon: const Icon(LucideIcons.x, color: Colors.white), onPressed: () => Navigator.pop(context))),
            Text('Card ${_index + 1} / ${widget.cards.length}', style: AppTextStyles.bodyMuted),
            const SizedBox(height: 10),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: widget.cards.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.all(40),
                  child: _FlipReveal(card: widget.cards[i]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: _index == widget.cards.length - 1
                  ? GradientButton(label: 'Add all to collection', onPressed: () => Navigator.pop(context))
                  : const Text('Swipe for next →', style: AppTextStyles.bodyMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlipReveal extends StatefulWidget {
  final CardModel card;
  const _FlipReveal({required this.card});
  @override
  State<_FlipReveal> createState() => _FlipRevealState();
}

class _FlipRevealState extends State<_FlipReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _c.forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && widget.card.rarity == CardRarity.legendary) Haptics.heavy();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final angle = _c.value * math.pi;
        final showFront = _c.value > 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..setEntry(3, 2, 0.0015)..rotateY(angle),
          child: showFront
              ? Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(math.pi), child: _CardFace(card: widget.card))
              : Container(decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24, width: 2)), child: Center(child: Text('∞', style: TextStyle(color: AppGradients.onFill(AppGradients.brand.colors.first), fontSize: 60, fontWeight: FontWeight.w900)))),
        );
      },
    );
  }
}
