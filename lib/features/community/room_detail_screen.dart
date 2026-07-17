import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../data/models/room.dart';
import '../../services/room_service.dart';

/// A Watch Party room.
///
/// Deliberately minimal: synchronized playback is v2, so this is the room's
/// identity (title, episode) plus its live roster size, which streams straight
/// off the Cloud-Function-owned memberCount.
class RoomDetailScreen extends StatelessWidget {
  final String roomId;
  const RoomDetailScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: SafeArea(
          child: StreamBuilder<Room?>(
            stream: RoomService.instance.roomById(roomId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final room = snap.data;
              // The host can delete a room while someone is standing in it.
              if (room == null) return _gone(context);
              return _body(context, room);
            },
          ),
        ),
      ),
    );
  }

  Widget _gone(BuildContext context) => Column(
        children: [
          _bar(context),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This room has ended.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMuted,
                ),
              ),
            ),
          ),
        ],
      );

  Widget _body(BuildContext context, Room room) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bar(context),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: AppGradients.purpleCyan,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: AppGradients.purpleCyan.colors.last.withOpacity(0.3), blurRadius: 16),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('🍿', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(room.title, style: AppTextStyles.heading.copyWith(color: Colors.white)),
                      ),
                      if (room.isLive) _liveDot(),
                    ]),
                    if (room.episodeNumber != null) ...[
                      const SizedBox(height: 4),
                      Text('Episode ${room.episodeNumber}',
                          style: AppTextStyles.caption.copyWith(color: Colors.white70)),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      const Icon(LucideIcons.users, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      // memberCount is server-owned — this reflects the trigger's
                      // view, so it settles a beat after a join lands.
                      Text(
                        room.memberCount == 1 ? '1 watching' : '${room.memberCount} watching',
                        style: AppTextStyles.body.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(children: [
                  Icon(LucideIcons.monitorPlay, size: 34, color: AppColors.primaryLight),
                  SizedBox(height: 12),
                  Text('Synced watching is coming soon',
                      textAlign: TextAlign.center, style: AppTextStyles.subheading),
                  SizedBox(height: 6),
                  Text(
                    'For now this room just keeps the crew together — everyone who joins shows up in the count above. Playback that stays in sync lands in a future update.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMuted,
                  ),
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _liveDot() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _bar(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
        child: Row(children: [
          IconButton(icon: const Icon(LucideIcons.arrowLeft), onPressed: () => context.pop()),
          const Expanded(child: Text('Watch Party', style: AppTextStyles.heading)),
        ]),
      );
}
