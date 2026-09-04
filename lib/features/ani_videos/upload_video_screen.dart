import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/ani_video.dart';
import '../../services/anime_search_service.dart';
import '../../services/ani_video_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import '../feed/create_post_screen.dart' show showAnimePickerSheet;

/// Compose an Ani Video (`/ani-videos/upload`): pick/record a clip (≤60s),
/// caption (≤200), optional anime tag, spoiler flag → upload with progress.
class UploadVideoScreen extends ConsumerStatefulWidget {
  const UploadVideoScreen({super.key});

  @override
  ConsumerState<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends ConsumerState<UploadVideoScreen> {
  final _caption = TextEditingController();

  XFile? _file;
  VideoPlayerController? _preview;
  int _durationSeconds = 0;

  /// Allocated once for the chosen clip and REUSED by every retry.
  ///
  /// The server charges an upload grant per distinct videoId, so minting a
  /// fresh one per attempt would let three failed retries exhaust a guest's
  /// whole daily quota. Cleared whenever the clip itself changes — a
  /// different video is a different upload and must cost its own grant.
  String? _videoId;

  AnimeSearchResult? _anime;
  bool _spoiler = false;

  bool _uploading = false;
  double _progress = 0;

  bool get _tooLong => _durationSeconds > AniVideoData.maxDurationSeconds;
  bool get _canPost => _file != null && _preview != null && !_tooLong && !_uploading;

  @override
  void dispose() {
    _caption.dispose();
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    Haptics.light();
    try {
      // maxDuration caps camera recordings at the source; gallery picks are
      // validated below once the real duration is known.
      final picked = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: AniVideoData.maxDurationSeconds),
      );
      if (picked == null || !mounted) return;

      final old = _preview;
      final ctrl = VideoPlayerController.file(File(picked.path));
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await old?.dispose();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _file = picked;
        _preview = ctrl;
        // Round UP, never truncate. `inSeconds` floors, so a 120.9s clip
        // reported 120 and sailed through every layer that checks <= 120 —
        // the picker cap, the button gate, the service guard and the rule.
        // Ceiling makes the limit mean what it says; the cost is that a clip
        // a millisecond over reads as 121 and is refused, which is the side
        // to err on.
        _durationSeconds =
            (ctrl.value.duration.inMilliseconds / Duration.millisecondsPerSecond).ceil();
        _videoId = null; // new clip → new grant
      });
      if (_tooLong) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('videoTooLong'))));
      }
    } catch (e) {
      debugPrint('[UploadVideo] pick failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('actionFailed'))));
    }
  }

  Future<void> _pickAnime() async {
    Haptics.light();
    final result = await showAnimePickerSheet(context);
    if (result != null && mounted) setState(() => _anime = result);
  }

  Future<void> _submit() async {
    if (!_canPost) return;
    Haptics.medium();
    _preview?.pause();
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    final postedLabel = ref.tr('videoPosted');
    // Allocated on the first attempt only; every retry below re-enters this
    // method and finds the id already set, so it reuses the same grant.
    final videoId = _videoId ??= AniVideoService.instance.newVideoId();
    try {
      await AniVideoService.instance.uploadVideo(
        videoFile: File(_file!.path),
        videoId: videoId,
        durationSeconds: _durationSeconds,
        caption: _caption.text,
        anilistId: _anime != null && _anime!.anilistId > 0 ? _anime!.anilistId : null,
        animeTitle: _anime?.title,
        animeCover: _anime?.coverImage,
        isSpoiler: _spoiler,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      // Land on the Ani Videos tab — the feed stream pins the fresh upload
      // (pending server timestamp) to the top.
      context.go('/ani-videos');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$postedLabel 🎉'), duration: const Duration(seconds: 2)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      // Out of quota is not a transport failure: retrying cannot succeed, so
      // the server's own cap text is shown and the retry action is withheld.
      final capped = e is UploadCapExceededException ? e : null;
      showDialog<void>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: Text(ref.tr('videoUploadFailed')),
          content: capped == null ? null : Text(capped.message, style: AppTextStyles.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              // A cap is acknowledged, not cancelled — "Cancel" alongside no
              // other action reads as if dismissing undoes something.
              child: Text(ref.tr(capped == null ? 'cancel' : 'ok')),
            ),
            if (capped == null)
              TextButton(
                onPressed: () {
                  Navigator.pop(dCtx);
                  _submit();
                },
                child: Text(ref.tr('retry')),
              ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: _uploading ? null : () => Navigator.pop(context),
        ),
        title: Text(ref.tr('uploadVideo')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_preview == null)
                    _sourcePickers()
                  else
                    _previewBox(),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      '${ref.tr('maxVideoDuration')}${_durationSeconds > 0 ? '  ·  ${_durationSeconds}s' : ''}',
                      style: AppTextStyles.captionMuted.copyWith(
                        color: _tooLong ? AppColors.secondary : null,
                        fontWeight: _tooLong ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  if (_tooLong)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(ref.tr('videoTooLong'),
                            style: AppTextStyles.caption.copyWith(color: AppColors.secondary)),
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _caption,
                    maxLines: 4,
                    minLines: 2,
                    maxLength: AniVideoData.maxCaptionLength,
                    enabled: !_uploading,
                    style: AppTextStyles.body,
                    onChanged: (_) => setState(() {}),
                    buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
                      '$currentLength/$maxLength',
                      style: AppTextStyles.captionMuted.copyWith(
                        color: currentLength >= (maxLength ?? 0) ? AppColors.secondary : null,
                      ),
                    ),
                    decoration: InputDecoration(hintText: ref.tr('captionHint')),
                  ),
                  const SizedBox(height: 12),

                  if (_anime != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          if (_anime!.coverImage.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                  imageUrl: _anime!.coverImage, width: 26, height: 36, fit: BoxFit.cover),
                            )
                          else
                            const Icon(LucideIcons.clapperboard, size: 18, color: AppColors.primaryLight),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_anime!.title,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
                          ),
                          GestureDetector(
                            onTap: _uploading ? null : () => setState(() => _anime = null),
                            child: const Icon(LucideIcons.x, size: 16, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Row(
                    children: [
                      _ToolChip(icon: LucideIcons.clapperboard, label: ref.tr('tagAnime'), onTap: _pickAnime),
                    ],
                  ),
                  SwitchListTile(
                    value: _spoiler,
                    onChanged: _uploading
                        ? null
                        : (v) {
                            Haptics.light();
                            setState(() => _spoiler = v);
                          },
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.secondary,
                    title: Text(ref.tr('markAsSpoiler'), style: AppTextStyles.body),
                    secondary: const Icon(LucideIcons.eyeOff, size: 19, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: _uploading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 8,
                            backgroundColor: AppColors.surfaceAlt,
                            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('${ref.tr('uploading')} ${(_progress * 100).round()}%',
                            style: AppTextStyles.captionMuted),
                      ],
                    )
                  : GradientButton(
                      label: ref.tr('post'),
                      icon: LucideIcons.send,
                      onPressed: _canPost ? _submit : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourcePickers() {
    return Row(
      children: [
        Expanded(child: _SourceCard(icon: LucideIcons.image, label: ref.tr('pickFromGallery'), onTap: () => _pick(ImageSource.gallery))),
        const SizedBox(width: 12),
        Expanded(child: _SourceCard(icon: LucideIcons.video, label: ref.tr('recordVideo'), onTap: () => _pick(ImageSource.camera))),
      ],
    );
  }

  Widget _previewBox() {
    final p = _preview!;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
              // Tap: preview play/pause. Corner ✕ swaps the clip out.
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    Haptics.light();
                    setState(() => p.value.isPlaying ? p.pause() : p.play());
                  },
                ),
              ),
              if (!p.value.isPlaying)
                const IgnorePointer(
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 64)),
              Positioned(
                right: 8,
                top: 8,
                child: GestureDetector(
                  onTap: _uploading
                      ? null
                      : () {
                          Haptics.light();
                          _preview?.dispose();
                          setState(() {
                            _file = null;
                            _preview = null;
                            _durationSeconds = 0;
                            _videoId = null; // clip dropped → grant not reused
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.x, size: 15, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: AppColors.primaryLight),
            const SizedBox(height: 10),
            Text(label, textAlign: TextAlign.center, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primaryLight),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
