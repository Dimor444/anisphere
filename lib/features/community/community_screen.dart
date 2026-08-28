import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/room.dart';
import '../../services/anime_search_service.dart';
import '../../services/room_service.dart';
import '../../shared/widgets/gradient_button.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppGradients.pageBg),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
                  child: Row(children: [
                    // Always reached by push (drawer) — safe to pop.
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () => context.pop(),
                    ),
                    const Expanded(child: Text('Community', style: AppTextStyles.heading)),
                    Row(children: [Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)), const SizedBox(width: 6), Text('12,408 online', style: AppTextStyles.caption.copyWith(color: AppColors.success))]),
                  ]),
                ),
                const TabBar(tabs: [Tab(text: '🏘️ Rooms'), Tab(text: '🎌 Clubs')]),
                const Expanded(child: TabBarView(children: [_RoomsTab(), _ClubsTab()])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomsTab extends StatelessWidget {
  const _RoomsTab();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
      children: [
        _RoomCard(
          emoji: '🎨', title: 'Art Room', subtitle: 'Share & critique fan art', gradient: AppGradients.brand,
          imagePath: 'assets/images/community/art_room.jpg', imageHeight: 130,
          child: Row(children: [_pill('Traditional'), const SizedBox(width: 8), _pill('Digital')]),
        ),
        const _RoomCard(
          emoji: '🍿', title: 'Watch Party', subtitle: 'Sync-watch with friends', gradient: AppGradients.purpleCyan,
          imagePath: 'assets/images/community/watch_party.jpg', imageHeight: 110,
          child: _WatchPartyBody(),
        ),
        _RoomCard(
          emoji: '✍️', title: 'Writers Room', subtitle: 'Theories, reviews & fanfic', gradient: AppGradients.gem,
          imagePath: 'assets/images/community/writers_room.jpg', imageHeight: 110,
          child: Column(children: [
            Row(children: [_pill('Theory'), const SizedBox(width: 8), _pill('Review'), const SizedBox(width: 8), _pill('Fanfic')]),
            const SizedBox(height: 8),
            ...['Theory: Frieren\'s true age 🔮', 'Why Vinland Saga S2 is perfect'].map((p) => Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(10),
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 13)),
                )),
          ]),
        ),
        _RoomCard(
          emoji: '💬', title: 'Anime Chat', subtitle: 'Per-anime live rooms', gradient: AppGradients.brandTri,
          child: Column(children: [
            const TextField(decoration: InputDecoration(hintText: 'Search anime rooms…', isDense: true, prefixIcon: Icon(LucideIcons.search, size: 16))),
            const SizedBox(height: 8),
            ...[('Frieren', 3201), ('Solo Leveling', 2890), ('Dandadan', 1740)].map((r) => Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Expanded(child: Text('#${r.$1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                    Text('${r.$2} online', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 8),
                    _joinBtn(label: 'Enter'),
                  ]),
                )),
          ]),
        ),
      ],
    );
  }

  static Widget _pill(String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)), child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)));
  static Widget _joinBtn({String label = 'Join'}) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Text(label, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w800)));
}

/// Live contents of the Watch Party card: the create action plus every open
/// watch_party room, live ones first. Art Room / Anime Chat next to it are
/// still static — only Watch Party is Firestore-backed so far.
class _WatchPartyBody extends StatelessWidget {
  const _WatchPartyBody();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GradientButton(
        label: 'Create Room +',
        expand: true,
        gradient: const LinearGradient(colors: [Colors.white24, Colors.white10]),
        onPressed: () => _openCreateSheet(context),
      ),
      const SizedBox(height: 8),
      StreamBuilder<List<Room>>(
        stream: RoomService.instance.watchPartyRooms(),
        builder: (context, snap) {
          if (snap.hasError) return _note('Rooms are unavailable right now.');
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
            );
          }
          final rooms = snap.data!;
          if (rooms.isEmpty) return _note('No rooms yet — start one!');
          return Column(children: rooms.map((r) => _RoomRow(room: r)).toList());
        },
      ),
    ]);
  }

  static Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      );

  static void _openCreateSheet(BuildContext context) {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => const _CreateRoomSheet(),
    );
  }
}

/// One room in the Watch Party list. Joining writes the membership doc (which
/// is what moves memberCount, server-side) and then opens the room.
class _RoomRow extends StatefulWidget {
  final Room room;
  const _RoomRow({required this.room});

  @override
  State<_RoomRow> createState() => _RoomRowState();
}

class _RoomRowState extends State<_RoomRow> {
  bool _joining = false;

  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    Haptics.light();
    try {
      await RoomService.instance.joinRoom(widget.room.id);
      if (!mounted) return;
      context.push('/room/${widget.room.id}');
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Can't reach the server — check your connection."), duration: Duration(seconds: 3)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't join that room."), duration: Duration(seconds: 2)),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final subtitle = [
      if (room.episodeNumber != null) 'Ep ${room.episodeNumber}',
      room.memberCount == 1 ? '1 watching' : '${room.memberCount} watching',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                if (room.isLive) const Padding(padding: EdgeInsets.only(left: 6), child: Text('🔴', style: TextStyle(fontSize: 10))),
              ]),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _joining ? null : _join,
          child: Opacity(opacity: _joining ? 0.5 : 1, child: _RoomsTab._joinBtn()),
        ),
      ]),
    );
  }
}

/// Create-a-room sheet: a title, an optional AniList anime to hang the room
/// off (stored as an id — cover/title are fetched live), and an optional
/// episode number.
class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet();

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final _titleCtrl = TextEditingController();
  final _episodeCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<AnimeSearchResult> _results = const [];
  AnimeSearchResult? _picked;
  bool _searching = false;
  bool _submitting = false;
  // Shown INSIDE the sheet — a snackbar on the parent scaffold renders
  // underneath the open sheet, so the user never sees it (observed live).
  String? _error;
  // Guards against a slow earlier query landing after a newer one.
  int _searchSeq = 0;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _episodeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final seq = ++_searchSeq;
    if (q.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await AnimeSearchService.instance.searchAnime(q);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = results.take(6).toList();
      _searching = false;
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    Haptics.medium();
    try {
      final roomId = await RoomService.instance.createWatchParty(
        title: title,
        animeId: _picked != null && _picked!.anilistId > 0 ? '${_picked!.anilistId}' : null,
        episodeNumber: int.tryParse(_episodeCtrl.text.trim()),
      );
      if (!mounted) return;
      Navigator.pop(context);
      context.push('/room/$roomId');
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Can't reach the server — check your connection.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't create the room.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 18, right: 18, top: 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Start a Watch Party', style: AppTextStyles.heading),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Room title', hintText: 'Frieren ep 28', counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            if (_picked == null) ...[
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'Anime (optional)',
                  hintText: 'Search anime…',
                  prefixIcon: const Icon(LucideIcons.search, size: 16),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
                onSubmitted: _search,
                onChanged: (v) {
                  if (v.trim().isEmpty) _search(v);
                },
              ),
              ..._results.map((a) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: a.coverImage.isEmpty
                        ? null
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(a.coverImage, width: 32, height: 44, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(width: 32, height: 44)),
                          ),
                    title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body),
                    subtitle: Text(a.genre, style: AppTextStyles.captionMuted),
                    onTap: () => setState(() {
                      _picked = a;
                      _results = const [];
                    }),
                  )),
            ] else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  const Icon(LucideIcons.tv, size: 16, color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_picked!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body)),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => setState(() {
                      _picked = null;
                      _searchCtrl.clear();
                    }),
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _episodeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Episode number (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.5)),
                ),
                child: Row(children: [
                  const Icon(LucideIcons.wifiOff, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error))),
                ]),
              ),
            ],
            const SizedBox(height: 18),
            GradientButton(
              label: _submitting ? 'Creating…' : 'Create Room',
              onPressed: _titleCtrl.text.trim().isEmpty || _submitting ? null : _submit,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final String emoji, title, subtitle;
  final Gradient gradient;
  final Widget child;

  /// Optional illustration shown as a band along the bottom of the card.
  /// Pass an asset path (e.g. 'assets/images/community/art_room.jpg') to enable it;
  /// leave null for a plain card. Reusable across every room.
  final String? imagePath;

  /// Height of the illustration band. Tune per card if needed.
  final double imageHeight;

  const _RoomCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.child,
    this.imagePath,
    this.imageHeight = 120,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      // The gradient + shadow live on the outer Container so the shadow is not
      // clipped; ClipRRect (below) only clips the content/image to the corners.
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Text + interactive content. It is padded and always sits ABOVE
            //    the illustration in the layout flow, so the image can never
            //    overlap the title, description or buttons.
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: AppTextStyles.heading.copyWith(color: Colors.white)), Text(subtitle, style: AppTextStyles.caption.copyWith(color: Colors.white70))]),
                  ]),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
            // ── Illustration band: edge-to-edge at the bottom, bottom corners
            //    clipped by the ClipRRect above.
            if (imagePath != null) _RoomImage(imagePath: imagePath!, height: imageHeight, gradient: gradient),
          ],
        ),
      ),
    );
  }
}

/// Bottom illustration for a [_RoomCard]. Renders [imagePath] cover-fitted with
/// a top-down gradient (the card's own colour) fading into the image, so the
/// picture melts into the content above and any overlaid text stays readable.
class _RoomImage extends StatelessWidget {
  final String imagePath;
  final double height;
  final Gradient gradient;
  const _RoomImage({required this.imagePath, required this.height, required this.gradient});

  @override
  Widget build(BuildContext context) {
    final cardColor = gradient.colors.last;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The artwork. errorBuilder keeps the card rendering cleanly even
          // if the asset is missing: a neutral box instead of a crash.
          Image.asset(
            imagePath,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26),
          ),
          // Transparent gradient overlay on top of the image: solid card colour
          // at the seam → fully clear over the artwork.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cardColor, cardColor.withOpacity(0.0)],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClubsTab extends StatelessWidget {
  const _ClubsTab();
  @override
  Widget build(BuildContext context) {
    final myClubs = [('⚔️', 'Shonen Legends'), ('🌸', 'Slice of Life'), ('🔮', 'Isekai Hub')];
    final discover = [
      ('🧝‍♀️', 'Frieren Fans', 12400, 'Public'),
      ('👊', 'JJK Sorcerers', 9800, 'Public'),
      ('🏴‍☠️', 'Nakama Crew', 21000, 'Public'),
      ('🗡️', 'Demon Corps', 7600, 'Private'),
      ('⚡', 'Hunter Assoc.', 5400, 'Public'),
      ('🪓', 'Vinland', 3200, 'Private'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
      children: [
        const Text('My Clubs', style: AppTextStyles.subheading),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...myClubs.map((c) => GestureDetector(
                    onTap: () => context.push('/club/${c.$2}'),
                    child: Container(
                      width: 84,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(gradient: AppGradients.forSeed(c.$2), borderRadius: BorderRadius.circular(16)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(c.$1, style: const TextStyle(fontSize: 28)), const SizedBox(height: 4), Text(c.$2, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: AppGradients.onGradient(AppGradients.pairForSeed(c.$2)), fontSize: 10, fontWeight: FontWeight.w700))]),
                    ),
                  )),
              GestureDetector(
                onTap: () => _createClub(context),
                child: Container(
                  width: 84,
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                  child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(LucideIcons.plus, color: AppColors.primaryLight), SizedBox(height: 4), Text('Create', style: TextStyle(color: AppColors.textSecondary, fontSize: 10))]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('Discover', style: AppTextStyles.subheading),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.3),
          itemCount: discover.length,
          itemBuilder: (_, i) {
            final c = discover[i];
            return GestureDetector(
              onTap: () => context.push('/club/${c.$2}'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(gradient: AppGradients.forSeed(c.$2), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(c.$1, style: const TextStyle(fontSize: 30)),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)), child: Text(c.$4, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.$2, style: AppTextStyles.subheading.copyWith(color: Colors.white)), Text('${(c.$3 / 1000).toStringAsFixed(1)}K members', style: AppTextStyles.caption.copyWith(color: Colors.white70))]),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _createClub(BuildContext context) {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 18, right: 18, top: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create a Club', style: AppTextStyles.heading),
            const SizedBox(height: 14),
            const TextField(decoration: InputDecoration(labelText: 'Club name')),
            const SizedBox(height: 10),
            const TextField(maxLines: 2, decoration: InputDecoration(labelText: 'Description')),
            const SizedBox(height: 10),
            const TextField(decoration: InputDecoration(labelText: 'Tags (comma separated)')),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Icon:', style: AppTextStyles.body),
              const SizedBox(width: 12),
              ...['⚔️', '🌸', '🔮', '🏴‍☠️'].map((e) => Padding(padding: const EdgeInsets.only(right: 8), child: CircleAvatar(backgroundColor: AppColors.surfaceAlt, child: Text(e)))),
            ]),
            const SizedBox(height: 18),
            GradientButton(label: 'Create Club · 100🟡', onPressed: () {
              Haptics.medium();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Club created! −100🟡'), duration: Duration(seconds: 1)));
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
