import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../services/auth_service.dart';
import '../../services/follow_service.dart';
import '../../services/true_fan_score_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/widgets/user_avatar.dart';

/// Per-anime True Fan leaderboard for the results screen: 🌍 Global and
/// 📍 Local (the viewer's country) tabs, each listing the fastest
/// [TrueFanScoreService.leaderboardSize] passed runs. When the viewer has
/// passed but their row isn't among the visible top, a separated "You: #N"
/// row shows their exact rank (count() aggregation); when they're already
/// visible, their inline row is highlighted instead.
class TrueFanLeaderboard extends ConsumerStatefulWidget {
  /// AniList media id of the anime — null when the id never resolved, which
  /// renders a muted "unavailable" note instead of a board.
  final int? anilistId;

  const TrueFanLeaderboard({super.key, required this.anilistId});

  @override
  ConsumerState<TrueFanLeaderboard> createState() => _TrueFanLeaderboardState();
}

/// One loaded tab: the visible rows plus the viewer's below-the-fold rank
/// (null when the viewer is visible, hasn't passed, or everyone fits).
class _BoardData {
  final List<TrueFanScoreEntry> rows;
  final TrueFanScoreEntry? myEntry;
  final int? myRank;
  const _BoardData({required this.rows, this.myEntry, this.myRank});
}

class _TrueFanLeaderboardState extends ConsumerState<TrueFanLeaderboard> {
  bool _local = false; // false = Global tab, true = Local tab
  bool _loading = true;
  bool _error = false;
  String _countryCode = '';
  String? _uid;
  final Map<bool, _BoardData> _cache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    final anilistId = widget.anilistId;
    if (anilistId == null) return;
    final local = _local;
    if (!refresh && _cache.containsKey(local)) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final svc = TrueFanScoreService.instance;
      final uid = (await AuthService.instance.initAuth()).uid;
      String? cc;
      if (local) {
        final profile = await FollowService.instance.getUser(uid);
        cc = (profile != null && profile.countryCode.isNotEmpty)
            ? profile.countryCode
            : FollowService.detectCountryCode();
      }

      final rows = await svc.topScores(anilistId, countryCode: cc);

      // "You: #N" only when the viewer passed, isn't visible above, and the
      // board is actually truncated (fewer rows than the limit means everyone
      // in this partition is already on screen).
      TrueFanScoreEntry? myEntry;
      int? myRank;
      final visible = rows.any((r) => r.userId == uid);
      if (!visible && rows.length >= TrueFanScoreService.leaderboardSize) {
        myEntry = await svc.myEntry(anilistId);
        // On Local, a stale entry recorded under another country isn't part
        // of this partition — no rank row for it.
        if (myEntry != null && (cc == null || myEntry.countryCode == cc)) {
          myRank = await svc.rankForTime(anilistId, myEntry.timeSeconds, countryCode: cc);
        } else {
          myEntry = null;
        }
      }

      if (!mounted || local != _local) return;
      setState(() {
        _uid = uid;
        _countryCode = cc ?? '';
        _cache[local] = _BoardData(rows: rows, myEntry: myEntry, myRank: myRank);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TrueFanLeaderboard] load failed: $e');
      if (!mounted || local != _local) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _switchTab(bool local) {
    if (_local == local) return;
    Haptics.light();
    setState(() {
      _local = local;
      _error = false;
      _loading = !_cache.containsKey(local);
    });
    _load();
  }

  /// "SA" → 🇸🇦. Empty for the "XX" unknown marker and non-alpha codes.
  static String _flag(String cc) {
    if (cc.length != 2 || cc == 'XX') return '';
    final units = cc.toUpperCase().codeUnits;
    if (units.any((u) => u < 0x41 || u > 0x5A)) return '';
    return String.fromCharCodes(units.map((u) => 0x1F1E6 + u - 0x41));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.anilistId == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Leaderboard unavailable for this anime.',
            style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabs(),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          )
        else if (_error)
          _errorView()
        else
          _board(_cache[_local]!),
      ],
    );
  }

  Widget _tabs() {
    return Row(
      children: [
        Expanded(child: _tabChip('🌍 Global', local: false)),
        const SizedBox(width: 8),
        Expanded(child: _tabChip('📍 Local', local: true)),
      ],
    );
  }

  Widget _tabChip(String label, {required bool local}) {
    final selected = _local == local;
    return GestureDetector(
      onTap: () => _switchTab(local),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 1.5),
        ),
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primaryLight : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          const Text("Couldn't load the leaderboard.", style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
          TextButton(
            onPressed: () => _load(refresh: true),
            child: const Text('Retry', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _board(_BoardData data) {
    if (data.rows.isEmpty) {
      final flag = _flag(_countryCode);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          _local
              ? 'Nobody from your country ${flag.isNotEmpty ? '$flag ' : ''}has passed this one yet — be the first! 🏁'
              : 'No one has passed this challenge yet — be the first! 🏁',
          style: AppTextStyles.bodyMuted,
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < data.rows.length; i++) _row(i + 1, data.rows[i]),
        if (data.myEntry != null && data.myRank != null) ...[
          const SizedBox(height: 4),
          const Divider(color: AppColors.border, height: 16),
          _youRow(data.myRank!, data.myEntry!),
        ],
      ],
    );
  }

  Widget _row(int rank, TrueFanScoreEntry entry) {
    final isMe = entry.userId == _uid;
    final flag = _flag(entry.countryCode);
    // Live identity from users/{uid}; the score doc's copy (frozen at pass
    // time) is only the paint-first fallback.
    final author = identityOf(ref, entry.userId);
    final name = author?.nameToShow ?? entry.userName;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe ? AppColors.primary.withOpacity(0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMe ? AppColors.primary : AppColors.border),
      ),
      child: Row(children: [
        SizedBox(width: 28, child: Text('$rank', style: AppTextStyles.numbersLg())),
        const SizedBox(width: 8),
        UserAvatar(name: name, imageUrl: author?.userAvatar ?? entry.userAvatar, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            isMe ? '$name (you)' : name,
            style: AppTextStyles.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (flag.isNotEmpty) ...[
          Text(flag, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
        ],
        Text(
          Fmt.stopwatch((entry.timeSeconds * 1000).round()),
          style: AppTextStyles.numbers.copyWith(color: AppColors.accent),
        ),
      ]),
    );
  }

  /// The viewer's exact rank when they've passed but sit below the visible
  /// top rows — clearly separated from the list above.
  Widget _youRow(int rank, TrueFanScoreEntry entry) {
    final author = identityOf(ref, entry.userId);
    final name = author?.nameToShow ?? entry.userName;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary),
      ),
      child: Row(children: [
        Text('You: #${Fmt.thousands(rank)}', style: AppTextStyles.numbersLg()),
        const SizedBox(width: 10),
        UserAvatar(name: name, imageUrl: author?.userAvatar ?? entry.userAvatar, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(name, style: AppTextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Text(
          Fmt.stopwatch((entry.timeSeconds * 1000).round()),
          style: AppTextStyles.numbers.copyWith(color: AppColors.accent),
        ),
      ]),
    );
  }
}
