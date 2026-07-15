import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';

/// AniBot — the AI assistant. ALWAYS FREE, never locked behind AniPlus.
void showAniBotSheet(BuildContext context) {
  Haptics.light();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AniBotSheet(),
  );
}

class _AniBotSheet extends StatefulWidget {
  const _AniBotSheet();
  @override
  State<_AniBotSheet> createState() => _AniBotSheetState();
}

class _Msg {
  final String text;
  final bool bot;
  _Msg(this.text, this.bot);
}

class _AniBotSheetState extends State<_AniBotSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [
    _Msg("Hey! I'm AniBot 🤖 Ask me for recommendations, who animated something, where to watch, or anything anime.", true),
  ];
  final _quick = ['Recommend me something', 'Best of this season', 'Where to watch Frieren?', 'Surprise me'];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _respond(String q) {
    final m = q.toLowerCase();
    if (m.contains('recommend') || m.contains('suggest')) {
      return "Based on your taste (Frieren, Vinland Saga, HxH) try **Mushoku Tensei** for the journey and **Vinland Saga S2** for the character drama. Both 8.6+ on AniSphere. 🎯";
    }
    if (m.contains('season') || m.contains('this season')) {
      return "🔥 This season's heavy hitters: Solo Leveling S3, Dandadan S2, Sakamoto Days, and Frieren still leading at 9.4. Want a watch order?";
    }
    if (m.contains('where') || m.contains('watch')) {
      return "You can stream most of these on Crunchyroll & Netflix. Frieren → Crunchyroll. Want me to set an episode reminder? 🔔";
    }
    if (m.contains('frieren')) {
      return "Frieren: Beyond Journey's End — Madhouse, 2023. A 9.4 masterpiece about an elf mage processing loss across centuries. Easily one of the best of the decade. 🧝‍♀️";
    }
    if (m.contains('surprise') || m.contains('random')) {
      return "🎲 Surprise pick: **Dandadan** — aliens, ghosts, and the best animation of 2024 from Science SARU. Wild ride, 8.7 rated.";
    }
    if (m.contains('hi') || m.contains('hello') || m.contains('hey')) {
      return "Hey there! 👋 Ready to find your next obsession? Tell me a vibe — action, cozy, tearjerker?";
    }
    return "Great question! While I'm a demo brain, I'd point you to AniMatch in Discover to find users with your exact taste, and the Top 100 chart for all-time greats. ✨";
  }

  void _send([String? preset]) {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    Haptics.light();
    setState(() {
      _messages.add(_Msg(text, false));
      _messages.add(_Msg(_respond(text), true));
      _controller.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _bubble(_messages[i]),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: _quick
                      .map((q) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(q, style: const TextStyle(fontSize: 12)),
                              onPressed: () => _send(q),
                              backgroundColor: AppColors.surfaceAlt,
                              side: const BorderSide(color: AppColors.border),
                            ),
                          ))
                      .toList(),
                ),
              ),
              _inputBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('🤖', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AniBot', style: AppTextStyles.subheading),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Powered by AI · Free',
                    style: TextStyle(fontSize: 10, color: AppColors.accent, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
    return Align(
      alignment: m.bot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          gradient: m.bot ? null : AppGradients.brand,
          color: m.bot ? AppColors.surface : null,
          borderRadius: BorderRadius.circular(16),
          border: m.bot ? Border.all(color: AppColors.border) : null,
        ),
        child: Text(
          m.text.replaceAll('**', ''),
          style: AppTextStyles.body.copyWith(color: Colors.white, height: 1.35),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: AppTextStyles.body,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Ask AniBot anything…'),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppGradients.brand,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(LucideIcons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
