import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../services/my_list_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/pressable.dart';
import 'my_list_screen.dart' show showScorePicker;
import 'widgets/list_status_ui.dart';

/// Editor for one My List entry (`/my-list/:anilist_id`).
///
/// The entry itself streams from Firestore; richer metadata (total episodes,
/// year, genres) is fetched from AniList on demand and never persisted.
class MyListDetailScreen extends ConsumerStatefulWidget {
  final int anilistId;
  const MyListDetailScreen({super.key, required this.anilistId});

  @override
  ConsumerState<MyListDetailScreen> createState() => _MyListDetailScreenState();
}

class _MyListDetailScreenState extends ConsumerState<MyListDetailScreen> {
  late final Stream<MyListEntry?> _entryStream;
  AniListMeta? _meta;

  // Edit state — seeded from the first Firestore snapshot, then user-owned.
  bool _seeded = false;
  ListStatus _status = ListStatus.planning;
  int _episodes = 0;
  double? _score;
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _entryStream = MyListService.instance.watchEntry(widget.anilistId);
    MyListService.instance.fetchMeta(widget.anilistId).then((m) {
      if (mounted && m != null) setState(() => _meta = m);
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _seed(MyListEntry e) {
    if (_seeded) return;
    _seeded = true;
    _status = e.status;
    _episodes = e.episodesWatched;
    _score = e.score;
    _notesCtrl.text = e.notes;
  }

  int get _maxEpisodes => (_meta?.episodes ?? 0) > 0 ? _meta!.episodes : 10000;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await MyListService.instance.updateEntry(
        widget.anilistId,
        status: _status,
        episodesWatched: _episodes,
        score: _score,
        clearScore: _score == null,
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) showMyListError(context, ref, onRetry: _save);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(MyListEntry entry) async {
    try {
      await MyListService.instance.removeFromMyList(widget.anilistId);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) showMyListError(context, ref, onRetry: () => _remove(entry));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(ref.tr('myList'), style: AppTextStyles.subheading),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: StreamBuilder<MyListEntry?>(
          stream: _entryStream,
          builder: (context, snap) {
            if (snap.hasError) return _error();
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primaryLight));
            }
            final entry = snap.data;
            if (entry == null) return _removedState();
            _seed(entry);
            return _editor(entry);
          },
        ),
      ),
    );
  }

  Widget _editor(MyListEntry entry) {
    final meta = _meta;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        // ── Header: large cover + AniList facts
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 120,
              height: 170,
              child: CachedNetworkImage(
                imageUrl: entry.coverImage,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                errorWidget: (_, __, ___) =>
                    DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(entry.title))),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.title, style: AppTextStyles.heading),
              const SizedBox(height: 8),
              if (meta != null) ...[
                if (meta.episodes > 0)
                  _fact(LucideIcons.playCircle, '${meta.episodes} ${ref.tr('episodes')}'),
                if (meta.seasonYear != null) _fact(LucideIcons.calendar, '${meta.seasonYear}'),
                if (meta.genres.isNotEmpty) _fact(LucideIcons.tag, meta.genres.take(2).join(' · ')),
                if (meta.score > 0) _fact(Icons.star_rounded, '${meta.score.toStringAsFixed(1)} AniList'),
              ] else
                const Text('…', style: AppTextStyles.captionMuted),
            ]),
          ),
        ]),
        const SizedBox(height: 22),

        // ── Status
        Text(ref.tr('status'), style: AppTextStyles.label),
        const SizedBox(height: 8),
        Pressable(
          onTap: () async {
            final s = await showStatusPicker(context, selected: _status);
            if (s != null) setState(() => _status = s);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              StatusBadge(status: _status),
              const Spacer(),
              const Icon(LucideIcons.chevronsUpDown, size: 16, color: AppColors.textMuted),
            ]),
          ),
        ),
        const SizedBox(height: 18),

        // ── Episodes watched (0..total)
        Text(ref.tr('episodesWatched'), style: AppTextStyles.label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            _stepBtn(LucideIcons.minus, _episodes > 0 ? () => setState(() => _episodes--) : null),
            Expanded(
              child: Column(children: [
                Text('$_episodes', style: AppTextStyles.numbersLg()),
                if ((_meta?.episodes ?? 0) > 0)
                  Text('/ ${_meta!.episodes}', style: AppTextStyles.captionMuted),
              ]),
            ),
            _stepBtn(LucideIcons.plus, _episodes < _maxEpisodes ? () => setState(() => _episodes++) : null),
          ]),
        ),
        if ((_meta?.episodes ?? 0) > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (_episodes / _meta!.episodes).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.background,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
        const SizedBox(height: 18),

        // ── Score (star row, tap active star to clear)
        Text(ref.tr('yourScore'), style: AppTextStyles.label),
        const SizedBox(height: 8),
        Pressable(
          onTap: () async {
            final s = await showScorePicker(context, initial: _score);
            if (s != null) setState(() => _score = s < 0 ? null : s);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Row(
                children: List.generate(10, (i) {
                  final filled = _score != null && i < _score!.round();
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 22,
                    color: filled ? AppColors.aniGold : AppColors.textMuted,
                  );
                }),
              ),
              const Spacer(),
              Text(_score == null ? '—' : '${_score!.round()}/10', style: AppTextStyles.numbers),
            ]),
          ),
        ),
        const SizedBox(height: 18),

        // ── Notes
        Text(ref.tr('notes'), style: AppTextStyles.label),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 4,
          maxLength: MyListService.maxNoteLength,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surface,
            counterStyle: AppTextStyles.captionMuted,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (entry.updatedAt != null)
          Text(
            '${ref.tr('lastUpdated')}: ${DateFormat('MMM d, y · HH:mm').format(entry.updatedAt!.toLocal())}',
            style: AppTextStyles.captionMuted,
          ),
        const SizedBox(height: 20),

        GradientButton(
          label: ref.tr('save'),
          icon: LucideIcons.check,
          onPressed: _saving ? null : _save,
        ),
        const SizedBox(height: 12),
        Pressable(
          onTap: _saving ? null : () => _remove(entry),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.error.withOpacity(0.6)),
            ),
            alignment: Alignment.center,
            child: Text(ref.tr('removeFromList'),
                style: AppTextStyles.label.copyWith(color: AppColors.error)),
          ),
        ),
      ],
    );
  }

  Widget _fact(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: AppTextStyles.caption)),
        ]),
      );

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => Pressable(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: onTap == null ? AppColors.surfaceAlt.withOpacity(0.4) : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: onTap == null ? AppColors.textMuted : Colors.white),
        ),
      );

  /// Entry gone (removed elsewhere, or deep link to an anime not in the list).
  Widget _removedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(LucideIcons.listX, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(ref.tr('emptyListBody'), style: AppTextStyles.bodyMuted),
        ]),
      ),
    );
  }

  Widget _error() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(ref.tr('listError'), textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
      ),
    );
  }
}
