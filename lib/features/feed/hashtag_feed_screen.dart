import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../data/models/post.dart';
import '../../services/feed_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/post_card.dart';

/// All posts carrying one hashtag (opened by tapping a `#tag` in a post).
class HashtagFeedScreen extends ConsumerWidget {
  final String tag; // lowercase, no '#'
  const HashtagFeedScreen({super.key, required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (r) => AppGradients.brand.createShader(r),
          child: Text('#$tag', style: AppTextStyles.heading.copyWith(color: Colors.white)),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: StreamBuilder<List<PostData>>(
          stream: FeedService.instance.getHashtagPosts(tag),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text(ref.tr('loadFeedError'), style: AppTextStyles.captionMuted));
            }
            final posts = snap.data;
            if (posts == null) return const Center(child: CircularProgressIndicator());
            if (posts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.hash, size: 42, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(ref.tr('emptyListTitle'), style: AppTextStyles.captionMuted),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: posts.length,
              itemBuilder: (_, i) => PostCard(key: ValueKey(posts[i].id), post: posts[i]),
            );
          },
        ),
      ),
    );
  }
}
