import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks lifetime AniScan usage. 3 free scans, then AniPlus paywall.
class AniScanController extends StateNotifier<int> {
  AniScanController() : super(0) {
    _load();
  }

  static const _key = 'aniscan_used';
  static const freeLimit = 3;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_key) ?? 0;
  }

  int get remaining => (freeLimit - state).clamp(0, freeLimit);
  bool get canScanFree => state < freeLimit;

  Future<void> use() async {
    state = state + 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, state);
  }

  Future<void> reset() async {
    state = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, 0);
  }
}

final aniScanProvider =
    StateNotifierProvider<AniScanController, int>((ref) => AniScanController());
