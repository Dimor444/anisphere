import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/post_image_compressor.dart';
import '../../data/models/post.dart';
import '../../services/anime_search_service.dart';
import '../../services/feed_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/user_avatar.dart';

/// Compose a feed post: text (≤500), up to [_CreatePostScreenState._maxImages]
/// images, optional anime tag, spoiler flag.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  static const int _maxImages = 3;

  final _text = TextEditingController();
  final List<XFile> _images = [];
  AnimeSearchResult? _anime;
  bool _spoiler = false;
  bool _posting = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    Haptics.light();
    try {
      // `limit` is only honored on some platforms — the take() below is the
      // real cap; extras past _maxImages are dropped with a notice.
      final picked = await ImagePicker().pickMultiImage(limit: _maxImages);
      if (picked.isEmpty || !mounted) return;
      final room = _maxImages - _images.length;
      setState(() => _images.addAll(picked.take(room)));
      if (picked.length > room) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ref.tr('maxImagesNote'))));
      }
    } catch (_) {
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
    final content = _text.text.trim();
    if ((content.isEmpty && _images.isEmpty) || _posting) return;
    Haptics.medium();
    setState(() => _posting = true);
    // Captured up front — this route is popped before the snackbar shows.
    final messenger = ScaffoldMessenger.of(context);
    final postedLabel = ref.tr('posted');
    try {
      // Compress everything first (each result is hard-asserted < 1 MB, the
      // Storage rule limit) so a rejected image aborts before any upload.
      final compressed = <Uint8List>[];
      for (final image in _images) {
        compressed.add(await PostImageCompressor.compress(image.path));
      }

      // The post id is generated before upload so posts/{uid}/{postId}/ is
      // stable and the Firestore doc lands under the same id.
      final postId = FeedService.instance.newPostId();
      var imageUrls = const <String>[];
      if (compressed.isNotEmpty) {
        imageUrls = await FeedService.instance.uploadPostImages(postId, compressed);
      }
      try {
        await FeedService.instance.createPost(
          postId: postId,
          content: content,
          anilistId: _anime != null && _anime!.anilistId > 0 ? _anime!.anilistId : null,
          animeTitle: _anime?.title,
          animeCover: _anime?.coverImage,
          imageUrls: imageUrls,
          isSpoiler: _spoiler,
        );
      } catch (_) {
        // Doc write failed after the images went up — remove them so nothing
        // orphaned stays behind, then fall through to the retry dialog.
        if (imageUrls.isNotEmpty) {
          await FeedService.instance.deletePostImages(postId, imageUrls.length);
        }
        rethrow;
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('$postedLabel 🎉'), duration: const Duration(seconds: 2)));
    } on ImageCompressException {
      // Retrying can't fix an image that won't fit under the rule — tell the
      // user to swap it out instead of offering the retry dialog.
      if (!mounted) return;
      setState(() => _posting = false);
      messenger.showSnackBar(SnackBar(content: Text(ref.tr('imageTooLarge'))));
    } catch (_) {
      if (!mounted) return;
      setState(() => _posting = false);
      showDialog<void>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: Text(ref.tr('postFailed')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(ref.tr('cancel'))),
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
    final me = myIdentity(ref);
    final length = _text.text.trim().length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
        title: Text(ref.tr('newPost')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        name: me?.nameToShow ?? '',
                        imageUrl: me?.userAvatar,
                        radius: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(me?.nameToShow ?? '', style: AppTextStyles.subheading),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _text,
                    maxLines: 7,
                    minLines: 4,
                    maxLength: PostData.maxContentLength,
                    autofocus: true,
                    style: AppTextStyles.body,
                    onChanged: (_) => setState(() {}),
                    buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
                      '$currentLength/$maxLength',
                      style: AppTextStyles.captionMuted.copyWith(
                        color: currentLength >= (maxLength ?? 0) ? AppColors.secondary : null,
                      ),
                    ),
                    decoration: InputDecoration(hintText: ref.tr('newPostHint')),
                  ),
                  const SizedBox(height: 12),

                  if (_images.isNotEmpty) ...[
                    SizedBox(
                      height: 104,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(File(_images[i].path), width: 104, height: 104, fit: BoxFit.cover),
                            ),
                            Positioned(
                              right: 6,
                              top: 6,
                              child: GestureDetector(
                                onTap: () => setState(() => _images.removeAt(i)),
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
                    const SizedBox(height: 12),
                  ],

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
                              child: CachedNetworkImage(imageUrl: _anime!.coverImage, width: 26, height: 36, fit: BoxFit.cover),
                            )
                          else
                            const Icon(LucideIcons.clapperboard, size: 18, color: AppColors.primaryLight),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_anime!.title,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _anime = null),
                            child: const Icon(LucideIcons.x, size: 16, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Row(
                    children: [
                      _ToolChip(icon: LucideIcons.image, label: ref.tr('addImage'), onTap: _pickImages),
                      const SizedBox(width: 8),
                      _ToolChip(icon: LucideIcons.clapperboard, label: ref.tr('tagAnime'), onTap: _pickAnime),
                    ],
                  ),
                  SwitchListTile(
                    value: _spoiler,
                    onChanged: (v) {
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
              child: _posting
                  ? const Center(
                      child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()),
                    )
                  : GradientButton(
                      label: ref.tr('post'),
                      icon: LucideIcons.send,
                      // Text or images — either alone makes a valid post.
                      onPressed: length > 0 || _images.isNotEmpty ? _submit : null,
                    ),
            ),
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

/// Debounced AniList title search in a bottom sheet; resolves to the picked
/// anime (or null). Shared by post compose and the Ani Video uploader.
Future<AnimeSearchResult?> showAnimePickerSheet(BuildContext context) {
  return showModalBottomSheet<AnimeSearchResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _AnimePickerSheet(),
  );
}

/// Bottom sheet: debounced AniList title search → pick one result.
class _AnimePickerSheet extends ConsumerStatefulWidget {
  const _AnimePickerSheet();

  @override
  ConsumerState<_AnimePickerSheet> createState() => _AnimePickerSheetState();
}

class _AnimePickerSheetState extends ConsumerState<_AnimePickerSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<AnimeSearchResult> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (q.trim().isEmpty) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      final results = await AnimeSearchService.instance.searchAnime(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const SizedBox(height: 14),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: _onChanged,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: ref.tr('searchHint'),
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  isDense: true,
                ),
              ),
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final r = _results[i];
                  return ListTile(
                    leading: r.coverImage.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: CachedNetworkImage(imageUrl: r.coverImage, width: 36, height: 48, fit: BoxFit.cover),
                          )
                        : const Icon(LucideIcons.clapperboard, color: AppColors.primaryLight),
                    title: Text(r.title, style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [if (r.genre.isNotEmpty) r.genre, if (r.rating > 0) '★ ${r.rating.toStringAsFixed(1)}'].join(' · '),
                      style: AppTextStyles.captionMuted,
                    ),
                    onTap: () {
                      Haptics.light();
                      Navigator.pop(context, r);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
