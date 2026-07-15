import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../services/my_list_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/pressable.dart';
import 'widgets/list_status_ui.dart';

/// My List — the user's personal anime list, live from Firestore
/// (`users/{uid}/myList`). Tabs: All | Watching | Completed | Planned.
class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});
  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  late Stream<List<MyListEntry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = MyListService.instance.getMyList();
  }

  // Re-created on retry so a failed auth/permission stream can recover.
  void _retry() => setState(() => _stream = MyListService.instance.getMyList());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppGradients.pageBg),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Header sits above the StreamBuilder so the back button is
                // visible in every state (loading, error, empty, data).
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 16, 4),
                  child: Row(children: [
                    // Always reached by push (drawer) — safe to pop.
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () => context.pop(),
                    ),
                    ShaderMask(
                      shaderCallback: (r) => AppGradients.brand.createShader(r),
                      blendMode: BlendMode.srcIn,
                      child: const Icon(LucideIcons.list, size: 24, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(ref.tr('myList'), style: AppTextStyles.display.copyWith(fontSize: 24)),
                  ]),
                ),
                Expanded(
                  child: StreamBuilder<List<MyListEntry>>(
                    stream: _stream,
                    builder: (context, snap) {
                      if (snap.hasError) return _ErrorState(onRetry: _retry);
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.primaryLight));
                      }
                      final all = snap.data!;
                      return Column(
                        children: [
                          if (all.isNotEmpty) _StatsCard(all: all),
                          TabBar(
                            indicator: const _GradientUnderline(),
                            indicatorSize: TabBarIndicatorSize.label,
                            labelColor: Colors.white,
                            unselectedLabelColor: AppColors.textMuted,
                            labelStyle: AppTextStyles.label,
                            dividerColor: Colors.transparent,
                            tabs: [
                              Tab(text: ref.tr('all')),
                              Tab(text: ref.tr('watching')),
                              Tab(text: ref.tr('completed')),
                              Tab(text: ref.tr('planning')),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(children: [
                              _EntryList(entries: all),
                              _EntryList(entries: all.where((e) => e.status == ListStatus.current).toList()),
                              _EntryList(entries: all.where((e) => e.status == ListStatus.completed).toList()),
                              _EntryList(entries: all.where((e) => e.status == ListStatus.planning).toList()),
                            ]),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "12 Anime | 3 Watching | 7 Completed | 1 Dropped" summary strip.
class _StatsCard extends ConsumerWidget {
  final List<MyListEntry> all;
  const _StatsCard({required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int count(ListStatus s) => all.where((e) => e.status == s).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          _stat('${all.length}', ref.tr('total')),
          _stat('${count(ListStatus.current)}', ref.tr('watching')),
          _stat('${count(ListStatus.completed)}', ref.tr('completed')),
          _stat('${count(ListStatus.dropped)}', ref.tr('dropped')),
        ]),
      ),
    );
  }

  Widget _stat(String v, String l) => Expanded(
        child: Column(children: [
          Text(v, style: AppTextStyles.numbersLg()),
          Text(l, style: AppTextStyles.captionMuted, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _EntryList extends StatelessWidget {
  final List<MyListEntry> entries;
  const _EntryList({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const _EmptyState();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _EntryTile(entry: entries[i]),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final MyListEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Pressable(
      onTap: () => context.push('/my-list/${entry.anilistId}'),
      onLongPress: () {
        Haptics.medium();
        _showQuickActions(context, ref);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 72,
              child: CachedNetworkImage(
                imageUrl: entry.coverImage,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                errorWidget: (_, __, ___) =>
                    DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(entry.title))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.subheading),
              const SizedBox(height: 6),
              Row(children: [
                StatusBadge(status: entry.status, compact: true),
                if (entry.episodesWatched > 0) ...[
                  const SizedBox(width: 8),
                  Text('Ep ${entry.episodesWatched}', style: AppTextStyles.captionMuted),
                ],
              ]),
            ]),
          ),
          if (entry.score != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 16),
              Text(' ${_fmtScore(entry.score!)}', style: AppTextStyles.numbers),
            ]),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {
      if (context.mounted) showMyListError(context, ref, onRetry: () => _run(context, ref, op));
    }
  }

  void _showQuickActions(BuildContext context, WidgetRef ref) {
    final id = entry.anilistId;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(children: [
              Expanded(child: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.heading)),
            ]),
          ),
          ListTile(
            leading: Icon(entry.status.icon, size: 20, color: entry.status.color),
            title: Text(ref.tr('status'), style: AppTextStyles.body),
            trailing: StatusBadge(status: entry.status, compact: true),
            onTap: () async {
              Navigator.pop(ctx);
              final s = await showStatusPicker(context, selected: entry.status);
              if (s != null && s != entry.status && context.mounted) {
                _run(context, ref, () => MyListService.instance.updateAnimeStatus(id, s));
              }
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.tv, size: 20, color: AppColors.textSecondary),
            title: Text(ref.tr('episodesWatched'), style: AppTextStyles.body),
            trailing: Text('${entry.episodesWatched}', style: AppTextStyles.numbers),
            onTap: () async {
              Navigator.pop(ctx);
              final n = await _promptEpisodes(context, ref);
              if (n != null && context.mounted) {
                _run(context, ref, () => MyListService.instance.updateEpisodesWatched(id, n));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.star_rounded, size: 20, color: AppColors.aniGold),
            title: Text(ref.tr('yourScore'), style: AppTextStyles.body),
            trailing: Text(entry.score == null ? '—' : _fmtScore(entry.score!), style: AppTextStyles.numbers),
            onTap: () async {
              Navigator.pop(ctx);
              final s = await showScorePicker(context, initial: entry.score);
              if (s != null && context.mounted) {
                _run(context, ref, () => MyListService.instance.updateScore(id, s < 0 ? null : s));
              }
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.trash2, size: 20, color: AppColors.error),
            title: Text(ref.tr('removeFromList'), style: AppTextStyles.body.copyWith(color: AppColors.error)),
            onTap: () {
              Navigator.pop(ctx);
              _run(context, ref, () => MyListService.instance.removeFromMyList(id));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<int?> _promptEpisodes(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: '${entry.episodesWatched}');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(ref.tr('episodesWatched'), style: AppTextStyles.subheading),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ref.tr('cancel'), style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: Text(ref.tr('save'), style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Star-row score picker (whole stars 1–10; tap the active star to clear).
/// Resolves to the score, -1 to clear, or null when dismissed.
Future<double?> showScorePicker(BuildContext context, {double? initial}) {
  return showModalBottomSheet<double>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Consumer(
        builder: (_, ref, __) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ref.tr('yourScore'), style: AppTextStyles.heading),
            const SizedBox(height: 14),
            _StarRow(
              initial: initial ?? 0,
              onPicked: (v) => Navigator.pop(ctx, v),
            ),
          ]),
        ),
      ),
    ),
  );
}

class _StarRow extends StatelessWidget {
  final double initial;
  final ValueChanged<double> onPicked;
  const _StarRow({required this.initial, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final current = initial.round();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(10, (i) {
        final v = i + 1;
        return GestureDetector(
          // Tapping the currently-selected star clears the rating.
          onTap: () => onPicked(v == current ? -1 : v.toDouble()),
          child: Icon(
            v <= current ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 30,
            color: v <= current ? AppColors.aniGold : AppColors.textMuted,
          ),
        );
      }),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: AppGradients.brand,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 24)],
          ),
          child: const Icon(LucideIcons.listPlus, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 16),
        Text(ref.tr('emptyListTitle'), style: AppTextStyles.subheading),
        const SizedBox(height: 4),
        Text(ref.tr('emptyListBody'), style: AppTextStyles.captionMuted),
        const SizedBox(height: 18),
        Pressable(
          onTap: () => context.push('/trending'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary),
            ),
            child: Text(ref.tr('trending'), style: AppTextStyles.label.copyWith(color: AppColors.primaryLight)),
          ),
        ),
      ]),
    );
  }
}

class _ErrorState extends ConsumerWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(LucideIcons.cloudOff, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(ref.tr('listError'), textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
          const SizedBox(height: 18),
          Pressable(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(14)),
              child: Text(ref.tr('retry'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Brand-gradient underline for the active tab.
class _GradientUnderline extends Decoration {
  const _GradientUnderline();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _GradientUnderlinePainter();
}

class _GradientUnderlinePainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size ?? Size.zero;
    final rect = Rect.fromLTWH(offset.dx, offset.dy + size.height - 3, size.width, 3);
    final paint = Paint()
      ..shader = AppGradients.brandTri.createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
  }
}

String _fmtScore(double s) => s == s.roundToDouble() ? '${s.toInt()}' : s.toStringAsFixed(1);
